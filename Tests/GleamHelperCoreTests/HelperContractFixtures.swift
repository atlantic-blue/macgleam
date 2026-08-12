import CryptoKit
import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// Deterministic fixtures for the C30 and C31 contract tests. Every instant,
/// identifier and key seed is fixed, nothing reads a wall clock, nothing
/// launches a process and nothing opens a real connection, so a failing test
/// reproduces byte for byte.
enum HelperFixture {

  // MARK: Identifiers and instants

  static let planID = uuid(0x01)
  static let operationID = uuid(0x02)
  static let otherPlanID = uuid(0x03)
  static let otherOperationID = uuid(0x04)

  /// Whole second instants: the wire encoding is compared for byte equality,
  /// so no fixture depends on sub second date precision.
  static let changeInstant = Date(timeIntervalSince1970: 1_723_000_000)
  static let farFutureInstant = Date(timeIntervalSince1970: 4_102_444_800)

  static func uuid(_ suffix: UInt8) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000000%02X", suffix))!
  }

  static func path(_ value: String) -> AbsolutePath {
    AbsolutePath(normalising: value)
  }

  // MARK: Client identity

  static let expectedTeamIdentifier = "TESTTEAM01"
  static let expectedBundleIdentifier = "com.atlanticblue.macgleam"

  static let expectedClient = ExpectedClientIdentity(
    teamIdentifier: expectedTeamIdentifier,
    bundleIdentifier: expectedBundleIdentifier
  )

  /// The one identity the helper serves: exact team identifier, exact bundle
  /// identifier, code signature verified.
  static let trustedClient = ClientIdentity(
    teamIdentifier: expectedTeamIdentifier,
    bundleIdentifier: expectedBundleIdentifier,
    codeSigningValid: true
  )

  /// A client that fails identity verification, for the tests that pin what a
  /// helper tells a caller it could not verify.
  static let intruderClient = client(bundleIdentifier: "com.example.intruder")

  static func client(
    teamIdentifier: String = expectedTeamIdentifier,
    bundleIdentifier: String = expectedBundleIdentifier,
    codeSigningValid: Bool = true
  ) -> ClientIdentity {
    ClientIdentity(
      teamIdentifier: teamIdentifier,
      bundleIdentifier: bundleIdentifier,
      codeSigningValid: codeSigningValid
    )
  }

  // MARK: Paths

  /// System domain under the ownership double, not on the helper denylist.
  static let systemAllowedTarget = path("/Library/Caches/com.example.helper")
  /// System domain under the ownership double and on the helper denylist.
  static let systemDenylistedTarget = path("/Library/Blocked/com.example.agent.plist")
  /// User domain under the ownership double, not on the helper denylist.
  static let userAllowedTarget = path("/Users/julian/Library/Caches/com.example.helper")
  /// User domain under the ownership double and on the helper denylist.
  static let userDenylistedTarget = path("/Users/julian/Blocked/keep.txt")

  static let userHome = path("/Users/julian")
  static let safetyNetStore = path("/Users/julian/Library/Application Support/MacGleam/SafetyNet")
  static let environment = OwnershipEnvironment(currentUserHome: userHome, currentUserID: 501)

  // MARK: Launch items

  static let systemLaunchItem = LaunchItemID(value: "com.example.agent|system")
  static let userLaunchItem = LaunchItemID(value: "com.example.agent|user")
  static let denylistedLaunchItem = LaunchItemID(value: "com.example.blocked|system")
  static let unresolvableLaunchItem = LaunchItemID(value: "com.example.ghost|system")

  static let launchItemLocations: [LaunchItemID: AbsolutePath] = [
    systemLaunchItem: path("/Library/LaunchDaemons/com.example.agent.plist"),
    userLaunchItem: path("/Users/julian/Library/LaunchAgents/com.example.agent.plist"),
    denylistedLaunchItem: path("/Library/Blocked/com.example.blocked.plist"),
  ]

  // MARK: The helper's own denylist

  /// A signing seed owned by this file alone, distinct from every other
  /// fixture file's key material.
  static let signingKeySeed = Data((0..<32).map { UInt8(truncatingIfNeeded: 0x40 &+ $0 &* 7) })

  static let denylistedRoots = ["/System", "/Library/Blocked", "/Users/julian/Blocked"]

  static func signedCatalog(
    version: UInt32 = 1,
    blocking patterns: [String]
  ) throws -> RuleCatalog {
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: signingKeySeed)
    let unsigned = RuleCatalog(
      version: RuleCatalogVersion(value: version),
      signature: Data(),
      cleanupRules: [],
      adwareRules: [],
      denylist: Denylist(patterns: patterns.map { PathPattern(pattern: $0) })
    )
    return RuleCatalog(
      version: unsigned.version,
      signature: try key.signature(for: unsigned.canonicalContentEncoding()),
      cleanupRules: [],
      adwareRules: [],
      denylist: unsigned.denylist
    )
  }

  static func catalogStore(blocking patterns: [String] = denylistedRoots) throws -> RuleCatalogStore
  {
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: signingKeySeed)
    let verifier = try RuleCatalogVerifier(publicKey: key.publicKey.rawRepresentation)
    return try RuleCatalogStore(baseline: signedCatalog(blocking: patterns), verifier: verifier)
  }

  /// The effective denylist obtained the way the helper obtains one: from a
  /// catalogue the helper itself verified, never from anything the app sent.
  static func verifiedDenylist(blocking patterns: [String] = denylistedRoots) async throws
    -> Denylist
  {
    try await catalogStore(blocking: patterns).effectiveDenylist
  }

  // MARK: Requests

  static func handshake(version: UInt16 = HelperContract.version) -> HelperRequest {
    .handshake(contractVersion: version)
  }

  static func remove(
    _ target: AbsolutePath,
    destination: HelperRemovalDestination = .permanent,
    planID: UUID = HelperFixture.planID,
    operationID: UUID = HelperFixture.operationID
  ) -> HelperRequest {
    .remove(target: target, destination: destination, planID: planID, operationID: operationID)
  }

  /// The planned change: the attribution names the plan and the operation it
  /// belongs to. There is no unattributed form of this fixture because there
  /// is no unattributed form of the request.
  static func setLaunchItemEnabled(
    _ item: LaunchItemID,
    enabled: Bool = false,
    attribution: ChangeAttribution = .operation(
      planID: HelperFixture.planID, operationID: HelperFixture.operationID)
  ) -> HelperRequest {
    .setLaunchItemEnabled(item: item, enabled: enabled, attribution: attribution)
  }

  /// The change somebody made in the interface: it belongs to no plan, and
  /// its identifier is minted for the change and names nothing else.
  static let directChangeID = uuid(0x05)

  static func directLaunchItemChange(
    _ item: LaunchItemID,
    enabled: Bool = false,
    changeID: UUID = HelperFixture.directChangeID
  ) -> HelperRequest {
    .setLaunchItemEnabled(
      item: item, enabled: enabled, attribution: .directChange(changeID: changeID))
  }

  static func runMaintenance(
    _ task: MaintenanceTask = .flushDomainNameSystemCache,
    planID: UUID = HelperFixture.planID,
    operationID: UUID = HelperFixture.operationID
  ) -> HelperRequest {
    .runMaintenance(task: task, planID: planID, operationID: operationID)
  }
}

// MARK: - Versions

/// A helper's contract version beside the version a client claimed, for the
/// tests that drive a disagreement from both sides of it. The app reads the
/// pair to decide which side is behind, so the two are carried together and
/// never as one number plus an assumption.
struct HelperVersionDisagreement: Sendable, Equatable {
  let helperVersion: UInt16
  let clientVersion: UInt16
}

// MARK: - Response cases

/// C30's response cases named one by one. The mapping below is an exhaustive
/// switch, so a seventh case added to the contract stops this file compiling
/// until the tests that enumerate responses cover it. That is the point of it:
/// a list of fixtures cannot silently fall behind the message set.
enum HelperResponseKind: String, CaseIterable, Sendable {
  case handshakeAccepted
  case handshakeRefused
  case success
  case launchItemChanged
  case refused
  case failed
}

extension HelperResponse {
  var kind: HelperResponseKind {
    switch self {
    case .handshakeAccepted: return .handshakeAccepted
    case .handshakeRefused: return .handshakeRefused
    case .success: return .success
    case .launchItemChanged: return .launchItemChanged
    case .refused: return .refused
    case .failed: return .failed
    }
  }

  /// The two versions a handshake refusal names, and nil for every other
  /// reply. A refusal that named no version answers nil here, so a test about
  /// which side is behind cannot pass on a reply that told the app nothing.
  var refusedVersions: HelperVersionDisagreement? {
    guard case .handshakeRefused(let helperVersion, let clientVersion) = self else { return nil }
    return HelperVersionDisagreement(helperVersion: helperVersion, clientVersion: clientVersion)
  }
}

// MARK: - Test doubles

/// A deterministic stand in for the C16 ownership policy: the three system
/// roots the helper exists for are system domain, everything else is user
/// domain. Pure, so admission behaviour is pinned without depending on a
/// concrete C16 implementation.
struct HelperSystemRootsOwnershipPolicy: PathOwnershipPolicy {
  static let systemRoots = [
    AbsolutePath(normalising: "/Library"),
    AbsolutePath(normalising: "/System"),
    AbsolutePath(normalising: "/Applications"),
  ]

  func ownership(of path: AbsolutePath, environment: OwnershipEnvironment) -> PathOwnership {
    for root in Self.systemRoots where path == root || path.isDescendant(of: root) {
      return .systemDomain
    }
    return .userDomain
  }
}

/// Resolves a launch item to the file the helper would mutate. The helper
/// resolves the item itself; the request carries an identifier, never a path.
struct HelperLaunchItemTable: HelperLaunchItemLocating {
  var locations: [LaunchItemID: AbsolutePath] = HelperFixture.launchItemLocations

  func location(of item: LaunchItemID) -> AbsolutePath? {
    locations[item]
  }
}

/// The construction surface the tests demand of the concrete C31 policy. One
/// instance guards one connection, which is why the handshake state it keeps
/// is per instance.
func makeHelperPolicy(
  denylist: Denylist,
  expectedClient: ExpectedClientIdentity = HelperFixture.expectedClient,
  contractVersion: UInt16 = HelperContract.version,
  ownership: any PathOwnershipPolicy = HelperSystemRootsOwnershipPolicy(),
  environment: OwnershipEnvironment = HelperFixture.environment,
  launchItems: any HelperLaunchItemLocating = HelperLaunchItemTable()
) -> HelperConnectionPolicy {
  HelperConnectionPolicy(
    expectedClient: expectedClient,
    contractVersion: contractVersion,
    denylist: denylist,
    ownership: ownership,
    environment: environment,
    launchItems: launchItems
  )
}

/// A policy whose connection has already completed a matching handshake from
/// the trusted client, which is the state every request after the first one
/// arrives in.
func makeHandshakenPolicy(
  denylist: Denylist,
  expectedClient: ExpectedClientIdentity = HelperFixture.expectedClient,
  ownership: any PathOwnershipPolicy = HelperSystemRootsOwnershipPolicy(),
  launchItems: any HelperLaunchItemLocating = HelperLaunchItemTable()
) throws -> HelperConnectionPolicy {
  let policy = makeHelperPolicy(
    denylist: denylist,
    expectedClient: expectedClient,
    ownership: ownership,
    launchItems: launchItems)
  try #require(
    policy.admit(HelperFixture.handshake(), from: HelperFixture.trustedClient) == .admitted,
    "the fixture handshake must be admitted before a test can exercise a later stage")
  return policy
}

/// The test double transport. It carries a request across a wire made of the
/// contract's own encoding, runs the policy on the far side, and carries the
/// reply back the same way, so a policy test also proves the message survived
/// the round trip. No real inter process communication, no process launch.
struct LoopbackHelperTransport {
  let policy: HelperConnectionPolicy
  /// The version this daemon compiles against, which is the version it names
  /// in an acceptance and the one it was built to enforce. It is carried here
  /// so a transport standing in for an older or newer helper answers with
  /// that helper's number rather than this build's.
  var helperContractVersion: UInt16 = HelperContract.version
  let codec = HelperWireCodec()

  func send(_ request: HelperRequest, from client: ClientIdentity) throws -> HelperResponse {
    let outbound = try codec.encode(request)
    let received = try codec.decodeRequest(from: outbound)
    let gate: any HelperPolicy = policy
    let reply: HelperResponse
    switch gate.admit(received, from: client) {
    case .admitted:
      reply = completion(for: received)
    case .refused(let reason):
      reply = refusal(for: received, reason: reason)
    }
    let inbound = try codec.encode(reply)
    return try codec.decodeResponse(from: inbound)
  }

  /// The reply the daemon sends when admission refused the request. A
  /// handshake refused because the versions disagreed is answered with
  /// `handshakeRefused`, built from the disagreement the connection recorded,
  /// because the exchange is the only place the app learns the two numbers.
  /// Every other refusal, a handshake refused on identity included, is
  /// answered with `refused`, which names no version at all.
  private func refusal(for request: HelperRequest, reason: HelperRefusal) -> HelperResponse {
    guard case .handshake = request, reason == .versionMismatch,
      let mismatch = policy.versionMismatch
    else {
      return .refused(correlationID: request.correlationID, reason: reason)
    }
    return .handshakeRefused(
      helperContractVersion: mismatch.helperContractVersion,
      clientContractVersion: mismatch.clientContractVersion)
  }

  /// What the daemon would answer once admission passed. The real work is
  /// s3b; this double stands in for it so the reply path is exercised.
  private func completion(for request: HelperRequest) -> HelperResponse {
    switch request {
    case .handshake:
      return .handshakeAccepted(contractVersion: helperContractVersion)
    case .remove(_, _, _, let operationID):
      return .success(correlationID: operationID, bytesReclaimed: 4096)
    case .setLaunchItemEnabled(let item, let enabled, let attribution):
      return .launchItemChanged(
        correlationID: attribution.correlationID,
        change: LaunchItemChange(
          item: item,
          previousEnabled: !enabled,
          newEnabled: enabled,
          changedAt: HelperFixture.changeInstant
        )
      )
    case .runMaintenance(_, _, let operationID):
      return .success(correlationID: operationID, bytesReclaimed: 0)
    }
  }
}

// MARK: - Wire helpers

/// The single top level verb of an encoded message and its body. A message
/// that does not encode as exactly one named verb fails here rather than
/// letting a closed set test pass for the wrong reason.
func helperWireVerb(
  of data: Data,
  sourceLocation: SourceLocation = #_sourceLocation
) throws -> String {
  let object = try JSONSerialization.jsonObject(with: data)
  let payload = try #require(
    object as? [String: Any],
    "the wire encoding must be a JSON object naming one message",
    sourceLocation: sourceLocation)
  #expect(payload.count == 1, sourceLocation: sourceLocation)
  return try #require(payload.keys.first, sourceLocation: sourceLocation)
}

/// The body of an encoded message: the fields the receiving process reads
/// once it knows the verb. Used by the tests that pin which values a message
/// carries by name, rather than only that it round trips.
func helperWireBody(
  of data: Data,
  sourceLocation: SourceLocation = #_sourceLocation
) throws -> [String: Any] {
  let object = try JSONSerialization.jsonObject(with: data)
  let payload = try #require(object as? [String: Any], sourceLocation: sourceLocation)
  let verb = try #require(payload.keys.first, sourceLocation: sourceLocation)
  return try #require(payload[verb] as? [String: Any], sourceLocation: sourceLocation)
}

/// The same payload with its verb renamed, keeping the body byte for byte.
/// This is how a hostile encoder would try to smuggle a verb the contract
/// does not have past a helper that trusted the body.
func helperWirePayload(
  _ data: Data,
  renamingVerbTo newVerb: String,
  sourceLocation: SourceLocation = #_sourceLocation
) throws -> Data {
  let object = try JSONSerialization.jsonObject(with: data)
  let payload = try #require(object as? [String: Any], sourceLocation: sourceLocation)
  let verb = try #require(payload.keys.first, sourceLocation: sourceLocation)
  let body = try #require(payload[verb], sourceLocation: sourceLocation)
  return try JSONSerialization.data(withJSONObject: [newVerb: body])
}

/// A payload built from raw JSON text, for the messages the contract does not
/// have and the values it does not accept.
func helperWirePayload(json: String) throws -> Data {
  try #require(json.data(using: .utf8))
}

/// The same payload with one field of the message body replaced. The field
/// must already be there, so a body whose shape has changed fails here rather
/// than letting a mutation slip past unnoticed.
func helperWirePayload(
  _ data: Data,
  replacingBodyField field: String,
  with value: Any,
  sourceLocation: SourceLocation = #_sourceLocation
) throws -> Data {
  let object = try JSONSerialization.jsonObject(with: data)
  let payload = try #require(object as? [String: Any], sourceLocation: sourceLocation)
  let verb = try #require(payload.keys.first, sourceLocation: sourceLocation)
  var body = try #require(payload[verb] as? [String: Any], sourceLocation: sourceLocation)
  try #require(
    body[field] != nil,
    "the message body must already carry a \(field) field",
    sourceLocation: sourceLocation)
  body[field] = value
  return try JSONSerialization.data(withJSONObject: [verb: body])
}

func helperWirePayload(
  _ data: Data,
  replacingTargetWith target: String,
  sourceLocation: SourceLocation = #_sourceLocation
) throws -> Data {
  try helperWirePayload(
    data, replacingBodyField: "target", with: target, sourceLocation: sourceLocation)
}

func helperWirePayload(
  _ data: Data,
  replacingDestinationWith destination: [String: Any],
  sourceLocation: SourceLocation = #_sourceLocation
) throws -> Data {
  try helperWirePayload(
    data, replacingBodyField: "destination", with: destination, sourceLocation: sourceLocation)
}
