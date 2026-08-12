import CryptoKit
import Foundation

/// Trial and licence, decided from one record and a clock.
///
/// Two rules run through all of it. Verification is offline, against a key
/// embedded in the app, so a licensed Mac stays licensed on a plane. And the
/// trial start only ever moves forward: it is written once, at first launch,
/// and a record that claims a later start than the one already held is
/// ignored, so quitting or putting the clock back buys nothing.
///
/// There is no feature gate here and none anywhere else. The trial is the
/// whole app for fourteen days; what expiry changes is what the purchase
/// screen says, not what the modules do.
public actor LicenceValidator: LicenceValidating {
  private let store: any LicenceRecordStoring
  private let activator: (any LicenceActivating)?
  private let publicKey: Curve25519.Signing.PublicKey?
  private let firstLaunch: @Sendable () -> Date

  private var cached: LicenceRecord?

  /// A build with no public key verifies nothing and says so through
  /// `.invalid` rather than trusting a licence it cannot check.
  public init(
    store: any LicenceRecordStoring,
    activator: (any LicenceActivating)? = nil,
    publicKey: Data,
    firstLaunch: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.store = store
    self.activator = activator
    self.publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    self.firstLaunch = firstLaunch
  }

  /// The state, derived rather than stored: a licence that verifies, or a
  /// trial reckoned from the recorded start against the clock passed in.
  public func currentState(now: Date) async -> LicenceState {
    let record = await recordStartingTrialIfNeeded(now: now)
    if let licence = record.licence {
      guard verify(licence) else {
        return .invalid(
          reason:
            "This licence could not be verified on this Mac, so MacGleam is running as if it "
            + "were not there.")
      }
      return .licensed(licence)
    }
    let endsAt = record.trialStartedAt.addingTimeInterval(LicenceState.trialInterval)
    guard now < endsAt else { return .trialExpired(endedAt: endsAt) }
    return .trial(startedAt: record.trialStartedAt, endsAt: endsAt)
  }

  /// Offline, always. The signature is checked over the licence's canonical
  /// fields against the embedded key, so this answers the same on a plane as
  /// it does anywhere else.
  public nonisolated func verify(_ licence: SignedLicence) -> Bool {
    guard let publicKey else { return false }
    guard let content = try? licence.canonicalContentEncoding() else { return false }
    return publicKey.isValidSignature(licence.signature, for: content)
  }

  /// Exchanges a key for a signed licence. A server that refuses, is
  /// unreachable or answers with nonsense leaves the record exactly as it was,
  /// and a licence that does not verify is never persisted: a signature this
  /// app cannot check is worth nothing whoever sent it.
  public func activate(licenceKey: String) async throws -> LicenceState {
    guard let activator else {
      throw LicenceActivationError.serverUnreachable(
        description: "This build cannot activate a licence.")
    }
    let licence: SignedLicence
    do {
      licence = try await activator.activate(licenceKey: licenceKey)
    } catch let error as LicenceActivationError {
      throw error
    } catch {
      throw LicenceActivationError.serverUnreachable(
        description: "The licence server could not be reached.")
    }
    guard verify(licence) else {
      throw LicenceActivationError.keyRejected(
        reason: "That licence did not verify on this Mac, so nothing was changed.")
    }
    let record = LicenceRecord(
      trialStartedAt: await recordStartingTrialIfNeeded(now: licence.issuedAt).trialStartedAt,
      licence: licence)
    try? await store.save(record)
    cached = record
    return .licensed(licence)
  }

  /// The record, starting a trial the first time there is none. The start is
  /// written once and never rewritten: a record that already exists is
  /// returned as it is, whatever the clock says now.
  private func recordStartingTrialIfNeeded(now: Date) async -> LicenceRecord {
    if let cached { return cached }
    if let stored = await store.load() {
      cached = stored
      return stored
    }
    let started = min(now, firstLaunch())
    let record = LicenceRecord(trialStartedAt: started, licence: nil)
    try? await store.save(record)
    cached = record
    return record
  }
}

extension SignedLicence {
  /// The bytes a signature covers: everything the licence claims, except the
  /// signature itself. Sorted keys, so one licence has one encoding.
  public func canonicalContentEncoding() throws -> Data {
    struct Content: Encodable {
      let licenceKey: String
      let issuedAt: Date
      let majorVersionCeiling: UInt16
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(
      Content(
        licenceKey: licenceKey, issuedAt: issuedAt, majorVersionCeiling: majorVersionCeiling))
  }
}

extension LicenceState {
  /// What the purchase surface says, and the only thing expiry changes. Every
  /// module works identically in all four states, which is what "no feature
  /// gate exists during trial" means when written down as behaviour.
  public var invitation: String {
    switch self {
    case .trial(_, let endsAt):
      return "You are trying MacGleam. The trial runs until \(Self.day(endsAt))."
    case .trialExpired:
      return
        "Your trial has ended. Everything still works; buying a licence keeps it that way and "
        + "supports the next version."
    case .licensed:
      return "MacGleam is licensed to this Mac. Thank you."
    case .invalid(let reason):
      return reason
    }
  }

  private static func day(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .long
    formatter.timeStyle = .none
    return formatter.string(from: date)
  }
}
