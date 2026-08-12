import CryptoKit
import Foundation
import GleamCore
import Testing

/// Trial and licence, against a controlled clock.
///
/// Two things are worth more than the rest here. Nothing is gated: the trial
/// is the whole app, expiry changes what the purchase screen says and nothing
/// else, and that is asserted rather than assumed. And verification is
/// offline, so a licensed Mac stays licensed with no network at all.
@Suite("Licence")
struct LicenceValidatorTests {

  private static let firstLaunch = Date(timeIntervalSince1970: 1_726_000_000)
  private static let signingSeed = Data(
    (0..<32).map { UInt8(truncatingIfNeeded: 0x33 &+ $0 &* 13) })

  private func key() throws -> Curve25519.Signing.PrivateKey {
    try Curve25519.Signing.PrivateKey(rawRepresentation: Self.signingSeed)
  }

  private func licence(
    key licenceKey: String = "GLEAM-0001",
    issuedAt: Date = LicenceValidatorTests.firstLaunch,
    ceiling: UInt16 = 1,
    signedWith signingKey: Curve25519.Signing.PrivateKey? = nil
  ) throws -> SignedLicence {
    let unsigned = SignedLicence(
      licenceKey: licenceKey,
      issuedAt: issuedAt,
      majorVersionCeiling: ceiling,
      signature: Data())
    let content = try unsigned.canonicalContentEncoding()
    let signature = try (signingKey ?? key()).signature(for: content)
    return SignedLicence(
      licenceKey: licenceKey,
      issuedAt: issuedAt,
      majorVersionCeiling: ceiling,
      signature: signature)
  }

  private func validator(
    record: LicenceRecord? = nil,
    activator: (any LicenceActivating)? = nil,
    store: RecordingLicenceStore? = nil
  ) throws -> (validator: LicenceValidator, store: RecordingLicenceStore) {
    let store = store ?? RecordingLicenceStore(record: record)
    return (
      LicenceValidator(
        store: store,
        activator: activator,
        publicKey: try key().publicKey.rawRepresentation,
        firstLaunch: { Self.firstLaunch }),
      store
    )
  }

  // MARK: - The trial

  @Test("first launch starts a fourteen day trial and records when it started")
  func firstLaunchStartsATrial() async throws {
    let world = try validator()

    let state = await world.validator.currentState(now: Self.firstLaunch)

    #expect(
      state
        == .trial(
          startedAt: Self.firstLaunch,
          endsAt: Self.firstLaunch.addingTimeInterval(LicenceState.trialInterval)))
    #expect(await world.store.saved.first?.trialStartedAt == Self.firstLaunch)
  }

  @Test("day fourteen is still the trial and day fifteen is not")
  func theTrialBoundaryIsExact() async throws {
    let world = try validator(record: LicenceRecord(trialStartedAt: Self.firstLaunch, licence: nil))
    let dayFourteen = Self.firstLaunch.addingTimeInterval(14 * 24 * 60 * 60 - 1)
    let dayFifteen = Self.firstLaunch.addingTimeInterval(14 * 24 * 60 * 60)

    guard case .trial = await world.validator.currentState(now: dayFourteen) else {
      Issue.record("a trial sold as fourteen days is fourteen days")
      return
    }
    guard case .trialExpired = await world.validator.currentState(now: dayFifteen) else {
      Issue.record("and not a minute more")
      return
    }
  }

  @Test("the recorded start never moves, whatever the clock says later")
  func theRecordedStartNeverMoves() async throws {
    let world = try validator()
    _ = await world.validator.currentState(now: Self.firstLaunch)

    let later = Self.firstLaunch.addingTimeInterval(10 * 24 * 60 * 60)
    let state = await world.validator.currentState(now: later)

    guard case .trial(let startedAt, _) = state else {
      Issue.record("the trial is still running ten days in")
      return
    }
    #expect(startedAt == Self.firstLaunch)
    #expect(await world.store.saved.count == 1, "the start is written once")
  }

  @Test("putting the clock back does not buy a second trial")
  func puttingTheClockBackBuysNothing() async throws {
    let started = Self.firstLaunch
    let world = try validator(record: LicenceRecord(trialStartedAt: started, licence: nil))

    let state = await world.validator.currentState(
      now: started.addingTimeInterval(-30 * 24 * 60 * 60))

    guard case .trial(let startedAt, _) = state else {
      Issue.record("a clock in the past is still the same trial")
      return
    }
    #expect(startedAt == started)
  }

  @Test("a store that cannot read starts a trial rather than locking anybody out")
  func aStoreThatCannotReadStartsATrial() async throws {
    let world = try validator(store: RecordingLicenceStore(record: nil, failsToSave: true))

    guard case .trial = await world.validator.currentState(now: Self.firstLaunch) else {
      Issue.record(
        "the failure that costs a sale is worse than the one that gives away a fortnight")
      return
    }
  }

  // MARK: - The licence

  @Test("a licence that verifies makes the state licensed, expired trial or not")
  func aLicenceThatVerifiesMakesTheStateLicensed() async throws {
    let licence = try licence()
    let world = try validator(
      record: LicenceRecord(trialStartedAt: Self.firstLaunch, licence: licence))

    let longAfter = Self.firstLaunch.addingTimeInterval(365 * 24 * 60 * 60)
    #expect(await world.validator.currentState(now: longAfter) == .licensed(licence))
  }

  @Test("verifying needs no network at all, and answers the same every time")
  func verifyingNeedsNoNetwork() async throws {
    // The validator is built with no activator, which is a build that cannot
    // reach the network at all, and verification still answers.
    let world = try validator()
    let licence = try licence()

    #expect(world.validator.verify(licence))
    #expect(world.validator.verify(licence))
  }

  @Test("a licence signed with another key does not verify and is reported plainly")
  func aLicenceSignedWithAnotherKeyDoesNotVerify() async throws {
    let intruder = Curve25519.Signing.PrivateKey()
    let forged = try licence(signedWith: intruder)
    let world = try validator(
      record: LicenceRecord(trialStartedAt: Self.firstLaunch, licence: forged))

    #expect(!world.validator.verify(forged))
    guard case .invalid(let reason) = await world.validator.currentState(now: Self.firstLaunch)
    else {
      Issue.record("a licence this Mac cannot check is not a licence")
      return
    }
    #expect(reason.hasSuffix("."))
  }

  @Test("a licence whose fields were edited after signing does not verify")
  func anEditedLicenceDoesNotVerify() async throws {
    let world = try validator()
    let genuine = try licence(ceiling: 1)
    let edited = SignedLicence(
      licenceKey: genuine.licenceKey,
      issuedAt: genuine.issuedAt,
      majorVersionCeiling: 99,
      signature: genuine.signature)

    #expect(world.validator.verify(genuine))
    #expect(!world.validator.verify(edited))
  }

  // MARK: - Activation

  @Test("activating exchanges a key for a licence and records it")
  func activatingRecordsTheLicence() async throws {
    let licence = try licence()
    let world = try validator(activator: ScriptedActivator(licence: licence))

    let state = try await world.validator.activate(licenceKey: "GLEAM-0001")

    #expect(state == .licensed(licence))
    #expect(await world.store.saved.last?.licence == licence)
  }

  @Test("a server that refuses leaves the state exactly as it was")
  func aServerThatRefusesChangesNothing() async throws {
    let world = try validator(
      activator: ScriptedActivator(
        failure: .keyRejected(reason: "That key belongs to another product.")))

    await #expect(throws: LicenceActivationError.self) {
      _ = try await world.validator.activate(licenceKey: "WRONG")
    }
    guard case .trial = await world.validator.currentState(now: Self.firstLaunch) else {
      Issue.record("a refused activation changes nothing about the trial")
      return
    }
    #expect(await world.store.saved.allSatisfy { $0.licence == nil })
  }

  @Test("a server that cannot be reached leaves the state exactly as it was")
  func anUnreachableServerChangesNothing() async throws {
    let world = try validator(activator: ScriptedActivator(throwing: ScriptedFailure()))

    await #expect(throws: LicenceActivationError.self) {
      _ = try await world.validator.activate(licenceKey: "GLEAM-0001")
    }
    #expect(await world.store.saved.allSatisfy { $0.licence == nil })
  }

  @Test("a licence the server sent that does not verify is never recorded")
  func aLicenceThatDoesNotVerifyIsNeverRecorded() async throws {
    let forged = try licence(signedWith: Curve25519.Signing.PrivateKey())
    let world = try validator(activator: ScriptedActivator(licence: forged))

    await #expect(throws: LicenceActivationError.self) {
      _ = try await world.validator.activate(licenceKey: "GLEAM-0001")
    }
    #expect(await world.store.saved.allSatisfy { $0.licence == nil })
  }

  // MARK: - No feature gate

  @Test("every state says what it says and gates nothing")
  func everyStateGatesNothing() throws {
    let states: [LicenceState] = [
      .trial(startedAt: Self.firstLaunch),
      .trialExpired(endedAt: Self.firstLaunch),
      .licensed(try licence()),
      .invalid(reason: "Something."),
    ]

    for state in states {
      #expect(!state.invitation.isEmpty)
      #expect(state.invitation.hasSuffix("."))
    }
    #expect(
      states[1].invitation.contains("still works"),
      """
      the trial ending changes what the purchase screen says and nothing else. \
      An app that stopped working here would be one nobody could evaluate and \
      nobody would buy
      """)
  }
}

struct ScriptedFailure: Error {}

/// The licence server at the boundary the validator sees.
struct ScriptedActivator: LicenceActivating {
  var licence: SignedLicence?
  var failure: LicenceActivationError?
  var thrown: (any Error)?

  init(licence: SignedLicence) {
    self.licence = licence
  }

  init(failure: LicenceActivationError) {
    self.failure = failure
  }

  init(throwing error: any Error) {
    self.thrown = error
  }

  func activate(licenceKey: String) async throws -> SignedLicence {
    if let failure { throw failure }
    if let thrown { throw thrown }
    guard let licence else { throw LicenceActivationError.malformedResponse }
    return licence
  }
}

/// The record store, recording every write so a test can tell a validator that
/// persisted something from one that only said it did.
actor RecordingLicenceStore: LicenceRecordStoring {
  private var record: LicenceRecord?
  private let failsToSave: Bool
  private(set) var saved: [LicenceRecord] = []

  init(record: LicenceRecord?, failsToSave: Bool = false) {
    self.record = record
    self.failsToSave = failsToSave
  }

  func load() async -> LicenceRecord? { record }

  func save(_ record: LicenceRecord) async throws {
    saved.append(record)
    if failsToSave { throw ScriptedFailure() }
    self.record = record
  }
}

/// The no feature gate promise, read from the tree rather than asserted at a
/// boundary that could not express it.
///
/// No module takes a licence at all, so none of them can behave differently in
/// one state than another. That is a property of the source, and this is where
/// it is checked: an engine or a module model that started importing the
/// licence types would fail here on the day it was written rather than on the
/// day somebody noticed the trial had started gating something.
@Suite("No feature gate")
struct NoFeatureGateTests {

  private static let repositoryRoot: URL = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { url.deleteLastPathComponent() }
    return url
  }()

  /// Every engine and every module surface. The licence lives in GleamCore
  /// beside them, so a check on the package would prove nothing; this is the
  /// list of things that do the work.
  private static let moduleDirectories = [
    "Sources/CleanupEngine", "Sources/CleanupModule",
    "Sources/LeftoversEngine", "Sources/DiskMapEngine", "Sources/DiskMapModule",
    "Sources/ApplicationsEngine", "Sources/PerformanceEngine",
    "Sources/ProtectionEngine", "Sources/ProtectionModule",
    "Sources/FullSweepModule", "Sources/GleamHub",
  ]

  @Test("no engine and no module surface knows anything about a licence")
  func nothingThatDoesTheWorkKnowsAboutALicence() throws {
    var checked = 0
    for directory in Self.moduleDirectories {
      let url = Self.repositoryRoot.appending(path: directory)
      let files = try FileManager.default.contentsOfDirectory(atPath: url.path)
        .filter { $0.hasSuffix(".swift") }
      #expect(!files.isEmpty, "\(directory) holds no source, so this proves nothing")
      for file in files {
        let contents = try String(
          contentsOf: url.appending(path: file), encoding: .utf8)
        checked += 1
        for name in ["LicenceState", "LicenceValidating", "SignedLicence", "LicenceRecord"] {
          #expect(
            !contents.contains(name),
            """
            \(directory)/\(file) mentions \(name). The trial is the whole app: \
            a module that can read the licence state is a module that can \
            behave differently in it
            """)
        }
      }
    }
    #expect(checked > 50, "a sweep over a handful of files is not a sweep over the app")
  }
}
