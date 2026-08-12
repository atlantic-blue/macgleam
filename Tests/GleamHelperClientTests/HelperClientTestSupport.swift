import CryptoKit
import Foundation
import GleamCore
import GleamHelperClient
import GleamHelperCore
import Testing
import os

/// Fixtures and doubles for the app side of the privileged boundary: the
/// registration coordinator and the helper client.
///
/// Nothing here registers a real service, launches a process, opens a
/// connection or reads a wall clock. The system service is a double whose
/// status a test moves the way a human moves it in System Settings, and the
/// transport is a double that records what crossed the boundary and answers
/// with a scripted reply encoded through the real C30 codec.

typealias PlanOperation = GleamCore.Operation

enum HelperClientFixture {
  static let userHome = AbsolutePath(normalising: "/Users/julian")
  static let safetyNetStore = AbsolutePath(
    normalising: "/Users/julian/Library/Application Support/MacGleam/SafetyNet")
  static let environment = OwnershipEnvironment(currentUserHome: userHome, currentUserID: 501)
  static let executionInstant = Date(timeIntervalSince1970: 1_723_000_000)

  /// System domain under the ownership double below, and not denylisted.
  static let systemTarget = AbsolutePath(normalising: "/Library/Caches/com.example.helper")
  static let otherSystemTarget = AbsolutePath(normalising: "/Library/Caches/com.example.other")
  /// System domain and denylisted, for the tests that prove a blocked target
  /// is never transmitted.
  static let systemDenylistedTarget = AbsolutePath(
    normalising: "/Library/Blocked/com.example.agent.plist")
  static let userTarget = AbsolutePath(normalising: "/Users/julian/Caches/mine.log")
  static let otherUserTarget = AbsolutePath(normalising: "/Users/julian/Caches/other.log")

  static let systemLaunchItem = LaunchItemID(value: "com.example.agent|system")
  static let denylistedRoots = ["/Library/Blocked"]

  static func path(_ value: String) -> AbsolutePath {
    AbsolutePath(normalising: value)
  }

  // MARK: Operations and plans

  static func trash(
    _ target: AbsolutePath,
    privilege: PlanOperation.Privilege = .root
  ) -> PlanOperation {
    PlanOperation(
      id: UUID(), findingID: UUID(), kind: .moveToTrash(target: target), privilege: privilege)
  }

  static func permanent(
    _ target: AbsolutePath,
    privilege: PlanOperation.Privilege = .root
  ) -> PlanOperation {
    PlanOperation(
      id: UUID(), findingID: UUID(), kind: .deletePermanently(target: target),
      privilege: privilege)
  }

  static func quarantine(_ target: AbsolutePath) -> PlanOperation {
    PlanOperation(
      id: UUID(), findingID: UUID(), kind: .quarantine(target: target), privilege: .root)
  }

  static func archive(_ target: AbsolutePath, groupID: UUID = UUID()) -> PlanOperation {
    PlanOperation(
      id: UUID(), findingID: UUID(), kind: .archive(target: target, groupID: groupID),
      privilege: .root)
  }

  static func launchItem(
    _ item: LaunchItemID = HelperClientFixture.systemLaunchItem,
    enabled: Bool = false
  ) -> PlanOperation {
    PlanOperation(
      id: UUID(), findingID: UUID(),
      kind: .setLaunchItemEnabled(item: item, enabled: enabled), privilege: .root)
  }

  static func maintenance(_ task: MaintenanceTask = .flushDomainNameSystemCache) -> PlanOperation {
    PlanOperation(
      id: UUID(), findingID: UUID(), kind: .runMaintenance(task: task), privilege: .root)
  }

  static func plan(_ operations: [PlanOperation], totalBytes: UInt64 = 0) -> OperationPlan {
    OperationPlan(
      id: UUID(), sessionID: UUID(), operations: operations, totalBytes: totalBytes,
      permanentDeletionConfirmation: nil)
  }

  // MARK: The denylist, obtained the way production obtains one

  /// A signing seed owned by this file alone, distinct from every other
  /// fixture file's key material.
  static let signingKeySeed = Data((0..<32).map { UInt8(truncatingIfNeeded: 0xC0 &+ $0 &* 5) })

  static func signedDenylist(blocking patterns: [String] = denylistedRoots) async throws
    -> Denylist
  {
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: signingKeySeed)
    let unsigned = RuleCatalog(
      version: RuleCatalogVersion(value: 1),
      signature: Data(),
      cleanupRules: [],
      adwareRules: [],
      denylist: Denylist(patterns: patterns.map { PathPattern(pattern: $0) })
    )
    let signed = RuleCatalog(
      version: unsigned.version,
      signature: try key.signature(for: unsigned.canonicalContentEncoding()),
      cleanupRules: [],
      adwareRules: [],
      denylist: unsigned.denylist
    )
    let verifier = try RuleCatalogVerifier(publicKey: key.publicKey.rawRepresentation)
    let store = try RuleCatalogStore(baseline: signed, verifier: verifier)
    return await store.effectiveDenylist
  }

  static func emptyDenylist() async throws -> Denylist {
    try await signedDenylist(blocking: [])
  }
}

/// The same deterministic ownership rule the executor tests use: everything at
/// or under /Library is system domain, everything else is user domain.
struct HelperClientLibraryOwnershipPolicy: PathOwnershipPolicy {
  private static let systemRoot = AbsolutePath(normalising: "/Library")

  func ownership(of path: AbsolutePath, environment: OwnershipEnvironment) -> PathOwnership {
    if path == Self.systemRoot || path.isDescendant(of: Self.systemRoot) {
      return .systemDomain
    }
    return .userDomain
  }
}

// MARK: - The system service double

/// What `register()` does on the double, named after the behaviour rather than
/// after an implementation detail.
enum FakeRegistrationOutcome: Sendable {
  /// The observed first registration on a real machine: `register()` throws
  /// SMAppServiceErrorDomain code 1, "Operation not permitted", and the
  /// service's status becomes `requiresApproval` and stays there until a human
  /// enables the item in System Settings. This is the successful path, not a
  /// failure, and the coordinator must read it as such.
  case throwsOperationNotPermittedAndAwaitsApproval
  /// The same throw with no approval pending behind it. Nothing is waiting for
  /// the user, so there is nothing to wait for: this is a real failure.
  case throwsOperationNotPermittedAndStaysNotRegistered
  /// Any other error, beside the status the service is left reporting once it
  /// has thrown. The double cannot express one without the other, because the
  /// status after the attempt is what decides the state and a throw on its own
  /// decides nothing.
  case throwsError(NSError, leaving: HelperServiceStatus)
  /// `register()` returns without throwing and leaves the given status.
  case succeeds(leaving: HelperServiceStatus)
}

/// Stands in for the system's registration service. The status is a value a
/// test moves, the way a human moves it in System Settings, and every
/// `register()` call is counted, because "registered lazily, exactly once" is
/// a claim about that count.
final class FakeHelperService: HelperServiceRegistering, @unchecked Sendable {
  private struct State {
    var status: HelperServiceStatus
    var registerCallCount = 0
  }

  /// The literal domain and code observed on a real machine. Written out here
  /// rather than read from the production constants, so a wrong constant
  /// cannot make its own test pass.
  static let serviceManagementErrorDomain = "SMAppServiceErrorDomain"
  static let operationNotPermittedCode = 1

  static var operationNotPermitted: NSError {
    NSError(
      domain: serviceManagementErrorDomain,
      code: operationNotPermittedCode,
      userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"]
    )
  }

  private let state: OSAllocatedUnfairLock<State>
  private let outcome: FakeRegistrationOutcome

  init(
    status: HelperServiceStatus = .notRegistered,
    onRegister outcome: FakeRegistrationOutcome = .throwsOperationNotPermittedAndAwaitsApproval
  ) {
    self.state = OSAllocatedUnfairLock(initialState: State(status: status))
    self.outcome = outcome
  }

  var status: HelperServiceStatus {
    state.withLock { $0.status }
  }

  var registerCallCount: Int {
    state.withLock { $0.registerCallCount }
  }

  func register() throws {
    state.withLock { $0.registerCallCount += 1 }
    switch outcome {
    case .throwsOperationNotPermittedAndAwaitsApproval:
      state.withLock { $0.status = .requiresApproval }
      throw Self.operationNotPermitted
    case .throwsOperationNotPermittedAndStaysNotRegistered:
      state.withLock { $0.status = .notRegistered }
      throw Self.operationNotPermitted
    case .throwsError(let error, let resulting):
      state.withLock { $0.status = resulting }
      throw error
    case .succeeds(let resulting):
      state.withLock { $0.status = resulting }
    }
  }

  /// The human enables the item in System Settings, which is the only thing
  /// that completes a registration.
  func approveInSystemSettings() {
    state.withLock { $0.status = .enabled }
  }

  /// The human turns the item off again, or removes it.
  func setStatus(_ status: HelperServiceStatus) {
    state.withLock { $0.status = status }
  }
}

// MARK: - The transport double

enum ScriptedHelperReply: Sendable {
  /// A contract message, carried back across the wire through the real codec.
  case message(HelperResponse)
  /// Bytes the contract cannot decode, for the tests that prove the client
  /// does not trust what comes back.
  case rawPayload(Data)
  /// The connection failed while the request was in flight.
  case transportFailure
}

struct HelperTransportFailure: Error {}
struct HelperTransportScriptExhausted: Error {}

/// Records every payload the client transmits and answers with the scripted
/// reply. A handshake is answered by the handshake reply the test set and does
/// not consume the script, so a test can script operation replies without
/// counting connection setup.
///
/// When the script runs out, a transport built with `succeedingWith` answers
/// every further request with a plain success naming the operation that
/// request carried; one built without it records that it was overrun and
/// throws, so a test cannot pass on a reply nobody wrote.
final class RecordingHelperTransport: HelperTransporting, @unchecked Sendable {
  private struct State {
    var sent: [Data] = []
    var remaining: [ScriptedHelperReply]
    var overranScript = false
    var handshakeCount = 0
  }

  private let state: OSAllocatedUnfairLock<State>
  private let handshakeReply: HelperResponse
  private let defaultSuccessBytes: UInt64?
  private let codec = HelperWireCodec()

  init(
    handshake: HelperResponse = .handshakeAccepted(contractVersion: HelperContract.version),
    script: [ScriptedHelperReply] = [],
    succeedingWith defaultSuccessBytes: UInt64? = nil
  ) {
    self.handshakeReply = handshake
    self.defaultSuccessBytes = defaultSuccessBytes
    self.state = OSAllocatedUnfairLock(initialState: State(remaining: script))
  }

  var sentPayloads: [Data] {
    state.withLock { $0.sent }
  }

  var sendCount: Int {
    state.withLock { $0.sent.count }
  }

  var transmittedNothing: Bool {
    sendCount == 0
  }

  var handshakeCount: Int {
    state.withLock { $0.handshakeCount }
  }

  var overranScript: Bool {
    state.withLock { $0.overranScript }
  }

  /// Every request that crossed the boundary, decoded through the real codec.
  /// A payload the contract cannot decode is a failure of the client, so it
  /// fails here rather than being quietly skipped.
  func sentRequests() throws -> [HelperRequest] {
    try sentPayloads.map { try codec.decodeRequest(from: $0) }
  }

  /// Every request that crossed the boundary except the connection handshake.
  func sentOperationRequests() throws -> [HelperRequest] {
    try sentRequests().filter {
      if case .handshake = $0 { return false }
      return true
    }
  }

  /// True when the given text appears verbatim in anything transmitted. Used
  /// to prove a denylisted path never crossed the boundary at all, rather than
  /// only that no decoded request named it.
  func transmitted(text: String) -> Bool {
    let needle = Data(text.utf8)
    return sentPayloads.contains { $0.range(of: needle) != nil }
  }

  func send(_ payload: Data) async throws -> Data {
    let request = try? codec.decodeRequest(from: payload)
    let isHandshake: Bool
    if case .some(.handshake) = request {
      isHandshake = true
    } else {
      isHandshake = false
    }
    state.withLock {
      $0.sent.append(payload)
      if isHandshake {
        $0.handshakeCount += 1
      }
    }
    if isHandshake {
      return try codec.encode(handshakeReply)
    }
    let next: ScriptedHelperReply? = state.withLock {
      $0.remaining.isEmpty ? nil : $0.remaining.removeFirst()
    }
    guard let next else {
      if let bytes = defaultSuccessBytes, let operationID = request?.replyOperationID {
        return try codec.encode(.success(correlationID: operationID, bytesReclaimed: bytes))
      }
      state.withLock { $0.overranScript = true }
      throw HelperTransportScriptExhausted()
    }
    switch next {
    case .message(let response):
      return try codec.encode(response)
    case .rawPayload(let data):
      return data
    case .transportFailure:
      throw HelperTransportFailure()
    }
  }
}

extension HelperRequest {
  /// The operation a request belongs to, for the transport double's default
  /// success. The handshake belongs to none.
  var replyOperationID: UUID? {
    switch self {
    case .handshake:
      return nil
    case .remove(_, _, _, let operationID):
      return operationID
    case .setLaunchItemEnabled(_, _, let attribution):
      return attribution.correlationID
    case .runMaintenance(_, _, let operationID):
      return operationID
    }
  }

  /// The plan a request belongs to, and nil for the handshake, which belongs
  /// to no plan.
  var requestPlanID: UUID? {
    switch self {
    case .handshake:
      return nil
    case .remove(_, _, let planID, _):
      return planID
    case .setLaunchItemEnabled(_, _, let attribution):
      guard case .operation(let planID, _) = attribution else { return nil }
      return planID
    case .runMaintenance(_, let planID, _):
      return planID
    }
  }

  /// The target of a removal, and nil for every other request. The tests that
  /// pin what the app named read this rather than a path they built again.
  var removalTarget: AbsolutePath? {
    guard case .remove(let target, _, _, _) = self else { return nil }
    return target
  }

  var removalDestination: HelperRemovalDestination? {
    guard case .remove(_, let destination, _, _) = self else { return nil }
    return destination
  }
}

// MARK: - Construction surfaces the tests demand

func makeRegistrationCoordinator(
  service: any HelperServiceRegistering
) -> HelperRegistrationCoordinator {
  HelperRegistrationCoordinator(service: service)
}

/// The construction surface the tests demand of the helper client. The user
/// home and the SafetyNet store are injected because C30 requires the app to
/// name the destination: the helper never chooses where a file goes.
func makeHelperClient(
  transport: any HelperTransporting,
  registration: HelperRegistrationCoordinator,
  contractVersion: UInt16 = HelperContract.version
) -> HelperClient {
  HelperClient(
    transport: transport,
    registration: registration,
    userHome: HelperClientFixture.userHome,
    safetyNetStoreDirectory: HelperClientFixture.safetyNetStore,
    contractVersion: contractVersion
  )
}

/// A client whose helper is already approved and running, which is the state
/// every test about replies wants to start in.
func makeApprovedHelperClient(
  transport: any HelperTransporting,
  contractVersion: UInt16 = HelperContract.version
) -> HelperClient {
  makeHelperClient(
    transport: transport,
    registration: makeRegistrationCoordinator(
      service: FakeHelperService(status: .enabled, onRegister: .succeeds(leaving: .enabled))),
    contractVersion: contractVersion
  )
}

func makeExecutor(
  fileSystem: any FileSystem,
  denylist: Denylist,
  helper: (any PrivilegedOperationPerforming)?
) -> PlanExecutor {
  PlanExecutor(
    fileSystem: fileSystem,
    denylist: denylist,
    helper: helper,
    ownershipPolicy: HelperClientLibraryOwnershipPolicy(),
    environment: HelperClientFixture.environment,
    now: { HelperClientFixture.executionInstant },
    isCancelled: { false }
  )
}

// MARK: - Reading a run

func collect(_ executor: PlanExecutor, executing plan: OperationPlan) async -> [ExecutionEvent] {
  var events: [ExecutionEvent] = []
  for await event in executor.execute(plan) {
    events.append(event)
  }
  return events
}

func finalReport(in events: [ExecutionEvent]) -> ExecutionReport? {
  let reports = events.compactMap { event -> ExecutionReport? in
    if case .planCompleted(let report) = event {
      return report
    }
    return nil
  }
  guard reports.count == 1, let last = events.last, case .planCompleted = last else {
    return nil
  }
  return reports.first
}

func helperUnavailableReason(in events: [ExecutionEvent]) -> String? {
  for event in events {
    if case .refused(.helperUnavailable(let reason)) = event {
      return reason
    }
  }
  return nil
}

func failureReason(_ result: OperationResult?) -> String? {
  if case .failed(let reason) = result {
    return reason
  }
  return nil
}

/// A reason string a user can read: words, not a diagnostic dump.
func expectPlainSentence(
  _ reason: String?,
  sourceLocation: SourceLocation = #_sourceLocation
) throws {
  let sentence = try #require(reason, sourceLocation: sourceLocation)
  #expect(sentence.isEmpty == false, sourceLocation: sourceLocation)
  #expect(sentence.contains(" "), "a sentence has words", sourceLocation: sourceLocation)
  #expect(
    sentence.contains("Error Domain=") == false,
    "a raw NSError description is not a sentence a user can read",
    sourceLocation: sourceLocation)
  #expect(sentence.contains("NSError") == false, sourceLocation: sourceLocation)
  #expect(sentence.contains("Optional(") == false, sourceLocation: sourceLocation)
}

/// The sentence the app shows when the only thing standing between the user
/// and the work is the approval in System Settings. It has to say so, because
/// degrading honestly is the whole point of that path.
func expectApprovalSentence(
  _ reason: String?,
  sourceLocation: SourceLocation = #_sourceLocation
) throws {
  try expectPlainSentence(reason, sourceLocation: sourceLocation)
  let sentence = try #require(reason, sourceLocation: sourceLocation).lowercased()
  #expect(
    sentence.contains("approv"),
    "an operation waiting on approval must say so, not fail anonymously",
    sourceLocation: sourceLocation)
}
