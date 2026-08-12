import Foundation

/// Trial and licence lifecycle.
///
/// Guarantees:
/// - `currentState` is a pure function of the persisted record and `now`, so
///   every trial boundary is testable against a controlled clock rather than
///   by waiting fourteen days.
/// - The trial starts at first launch and runs fourteen days, full featured.
///   No feature gate exists during it, anywhere.
/// - The recorded start never moves backwards, so quitting, relaunching or
///   putting the clock back does not buy another trial.
/// - `verify` is offline, against the embedded public key, and answers the
///   same whether or not there is a network.
/// - `activate` is the only network call here and one of the three permitted
///   outbound endpoints. Any server failure leaves the persisted state exactly
///   as it was and reports a plain sentence.
public protocol LicenceValidating: Sendable {
  func currentState(now: Date) async -> LicenceState
  func verify(_ licence: SignedLicence) -> Bool
  func activate(licenceKey: String) async throws -> LicenceState
}

public enum LicenceActivationError: Error, Sendable, Equatable {
  case keyRejected(reason: String)
  case serverUnreachable(description: String)
  case malformedResponse
}

extension LicenceActivationError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .keyRejected(let reason):
      return reason
    case .serverUnreachable:
      return
        "The licence server could not be reached, so nothing changed. MacGleam keeps working "
        + "exactly as it did."
    case .malformedResponse:
      return
        "The licence server answered with something MacGleam could not read, so nothing "
        + "changed."
    }
  }
}

/// What the app remembers between launches about trial and licence. It is the
/// whole persisted state: everything else is derived from this and a clock.
public struct LicenceRecord: Codable, Sendable, Equatable {
  public let trialStartedAt: Date
  public let licence: SignedLicence?

  public init(trialStartedAt: Date, licence: SignedLicence?) {
    self.trialStartedAt = trialStartedAt
    self.licence = licence
  }
}

/// Where the record is kept. A store that cannot read answers nil, which
/// starts a fresh trial rather than locking somebody out of an app they may
/// have paid for: the failure that costs a sale is worse than the one that
/// gives away a fortnight.
public protocol LicenceRecordStoring: Sendable {
  func load() async -> LicenceRecord?
  func save(_ record: LicenceRecord) async throws
}

/// The licence server, behind one method. It is one of exactly three outbound
/// endpoints in the app.
public protocol LicenceActivating: Sendable {
  func activate(licenceKey: String) async throws -> SignedLicence
}
