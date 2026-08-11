import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// Encodes, decodes and expects equality, then re encodes the decoded value
/// and expects the same bytes. The second half is what stops the two
/// processes drifting: a decoder that quietly repairs a payload would pass the
/// first check and fail this one. It also requires the encoding to be
/// canonical, key order included, so a payload can be logged, diffed and
/// reasoned about identically on both sides of the connection.
func expectRequestRoundTrip(
  _ request: HelperRequest,
  sourceLocation: SourceLocation = #_sourceLocation
) throws {
  let codec = HelperWireCodec()
  let encoded = try codec.encode(request)
  let decoded = try codec.decodeRequest(from: encoded)
  #expect(decoded == request, sourceLocation: sourceLocation)
  let reencoded = try codec.encode(decoded)
  #expect(reencoded == encoded, sourceLocation: sourceLocation)
}

func expectResponseRoundTrip(
  _ response: HelperResponse,
  sourceLocation: SourceLocation = #_sourceLocation
) throws {
  let codec = HelperWireCodec()
  let encoded = try codec.encode(response)
  let decoded = try codec.decodeResponse(from: encoded)
  #expect(decoded == response, sourceLocation: sourceLocation)
  let reencoded = try codec.encode(decoded)
  #expect(reencoded == encoded, sourceLocation: sourceLocation)
}

@Suite("Helper request wire encoding")
struct HelperRequestWireTests {

  static let handshakes: [HelperRequest] = [
    .handshake(contractVersion: 0),
    .handshake(contractVersion: 1),
    .handshake(contractVersion: HelperContract.version),
    .handshake(contractVersion: UInt16.max),
  ]

  static let destinations: [HelperRemovalDestination] = [
    .permanent,
    .userTrash(userHome: HelperFixture.userHome),
    .safetyNetStore(storeDirectory: HelperFixture.safetyNetStore),
  ]

  static let targets: [AbsolutePath] = [
    HelperFixture.path("/"),
    HelperFixture.path("/Library"),
    HelperFixture.path("/Library/Application Support/Ünïcödé 🚀/файл.log"),
    HelperFixture.path("/Library/Caches/a name with spaces"),
  ]

  static let launchItems: [LaunchItemID] = [
    LaunchItemID(value: ""),
    LaunchItemID(value: "com.example.agent|system"),
    LaunchItemID(value: "Ünïcödé.agent 🚀|system"),
  ]

  @Test("a handshake round trips at every contract version", arguments: handshakes)
  func handshakeRoundTrips(request: HelperRequest) throws {
    try expectRequestRoundTrip(request)
  }

  @Test("a remove round trips for every removal destination", arguments: destinations)
  func removeRoundTripsForEveryDestination(destination: HelperRemovalDestination) throws {
    try expectRequestRoundTrip(
      HelperFixture.remove(HelperFixture.systemAllowedTarget, destination: destination))
  }

  @Test(
    "a remove round trips for the root, spaced and unicode targets a real machine has",
    arguments: targets
  )
  func removeRoundTripsForAwkwardTargets(target: AbsolutePath) throws {
    try expectRequestRoundTrip(HelperFixture.remove(target))
  }

  @Test("a launch item change round trips for both enabled states")
  func launchItemChangeRoundTripsForBothStates() throws {
    try expectRequestRoundTrip(
      HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem, enabled: true))
    try expectRequestRoundTrip(
      HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem, enabled: false))
  }

  @Test("a launch item identifier round trips empty and in unicode", arguments: launchItems)
  func launchItemIdentifierRoundTrips(item: LaunchItemID) throws {
    try expectRequestRoundTrip(HelperFixture.setLaunchItemEnabled(item))
  }

  @Test("every maintenance task round trips", arguments: MaintenanceTask.allCases)
  func everyMaintenanceTaskRoundTrips(task: MaintenanceTask) throws {
    try expectRequestRoundTrip(HelperFixture.runMaintenance(task))
  }

  @Test("the plan and operation identifiers survive the wire unchanged")
  func planAndOperationIdentifiersSurviveTheWire() throws {
    let request = HelperFixture.remove(
      HelperFixture.systemAllowedTarget,
      planID: HelperFixture.otherPlanID,
      operationID: HelperFixture.otherOperationID)
    let codec = HelperWireCodec()
    let decoded = try codec.decodeRequest(from: codec.encode(request))
    #expect(decoded.planID == HelperFixture.otherPlanID)
    #expect(decoded.operationID == HelperFixture.otherOperationID)
  }
}

@Suite("Helper response wire encoding")
struct HelperResponseWireTests {

  static let refusals: [HelperRefusal] = [
    .denylisted, .notSystemDomain, .versionMismatch, .identityRejected, .malformedRequest,
  ]

  static let reclaimedByteCounts: [UInt64] = [0, 1, 4096, UInt64.max]

  static let failureReasons: [String] = [
    "",
    "The file was gone by the time the helper reached it. Nothing was changed.",
    "Ünïcödé 🚀 \"quoted\" and\nnewlined",
  ]

  /// Both ends of the version range in both orders, and a pair that is
  /// neither extreme, because the two numbers are not interchangeable: the app
  /// reads which of them is larger to decide which side to prompt about.
  static let handshakeRefusals: [HelperResponse] = [
    .handshakeRefused(helperContractVersion: 0, clientContractVersion: UInt16.max),
    .handshakeRefused(helperContractVersion: UInt16.max, clientContractVersion: 0),
    .handshakeRefused(helperContractVersion: 3, clientContractVersion: 7),
    .handshakeRefused(helperContractVersion: 7, clientContractVersion: 3),
    .handshakeRefused(helperContractVersion: HelperContract.version, clientContractVersion: 0),
  ]

  @Test("a handshake acceptance round trips at the extremes of the version range")
  func handshakeAcceptanceRoundTripsAtVersionExtremes() throws {
    try expectResponseRoundTrip(.handshakeAccepted(contractVersion: 0))
    try expectResponseRoundTrip(.handshakeAccepted(contractVersion: UInt16.max))
  }

  @Test(
    "a handshake refusal round trips at the version extremes and at an asymmetric pair",
    arguments: handshakeRefusals
  )
  func handshakeRefusalRoundTrips(response: HelperResponse) throws {
    try expectResponseRoundTrip(response)
  }

  @Test("the handshake refusal encoding names both versions, each in its own field")
  func handshakeRefusalEncodingNamesBothVersions() throws {
    let encoded = try HelperWireCodec().encode(
      .handshakeRefused(helperContractVersion: 7, clientContractVersion: 3))
    let body = try helperWireBody(of: encoded)
    #expect(body["helperContractVersion"] as? Int == 7)
    #expect(body["clientContractVersion"] as? Int == 3)
  }

  @Test("the two versions of a handshake refusal do not swap places on the wire")
  func theTwoVersionsDoNotSwapPlacesOnTheWire() throws {
    let codec = HelperWireCodec()
    let helperBehind = try codec.encode(
      .handshakeRefused(helperContractVersion: 3, clientContractVersion: 7))
    let appBehind = try codec.encode(
      .handshakeRefused(helperContractVersion: 7, clientContractVersion: 3))
    #expect(helperBehind != appBehind)
    let versions = try #require(codec.decodeResponse(from: helperBehind).refusedVersions)
    #expect(versions == HelperVersionDisagreement(helperVersion: 3, clientVersion: 7))
  }

  @Test("a success round trips at every reclaimed byte count", arguments: reclaimedByteCounts)
  func successRoundTripsAtEveryByteCount(bytes: UInt64) throws {
    try expectResponseRoundTrip(
      .success(operationID: HelperFixture.operationID, bytesReclaimed: bytes))
  }

  @Test("a launch item change round trips with a far future instant")
  func launchItemChangeRoundTripsWithFarFutureInstant() throws {
    try expectResponseRoundTrip(
      .launchItemChanged(
        operationID: HelperFixture.operationID,
        change: LaunchItemChange(
          item: HelperFixture.systemLaunchItem,
          previousEnabled: true,
          newEnabled: false,
          changedAt: HelperFixture.farFutureInstant
        )
      )
    )
  }

  @Test("every refusal round trips carrying the refused operation", arguments: refusals)
  func everyRefusalRoundTripsCarryingTheOperation(refusal: HelperRefusal) throws {
    try expectResponseRoundTrip(
      .refused(operationID: HelperFixture.operationID, reason: refusal))
  }

  @Test("a refusal with no operation round trips as no operation", arguments: refusals)
  func refusalWithNoOperationRoundTrips(refusal: HelperRefusal) throws {
    try expectResponseRoundTrip(.refused(operationID: nil, reason: refusal))
  }

  @Test("a failure round trips its reason verbatim", arguments: failureReasons)
  func failureRoundTripsItsReasonVerbatim(reason: String) throws {
    try expectResponseRoundTrip(
      .failed(operationID: HelperFixture.operationID, reason: reason))
  }

  @Test("the refusal raw values are the five the contract names")
  func refusalRawValuesAreTheContractsFive() {
    #expect(HelperRefusal.denylisted.rawValue == "denylisted")
    #expect(HelperRefusal.notSystemDomain.rawValue == "notSystemDomain")
    #expect(HelperRefusal.versionMismatch.rawValue == "versionMismatch")
    #expect(HelperRefusal.identityRejected.rawValue == "identityRejected")
    #expect(HelperRefusal.malformedRequest.rawValue == "malformedRequest")
  }
}

@Suite("Helper wire direction separation")
struct HelperWireDirectionTests {

  static let requests: [HelperRequest] = [
    HelperFixture.handshake(),
    HelperFixture.remove(HelperFixture.systemAllowedTarget),
    HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem),
    HelperFixture.runMaintenance(),
  ]

  /// Every response case the contract declares, not a sample of them.
  /// `responseFixturesCoverEveryCaseTheContractDeclares` is what keeps this
  /// list honest as the message set grows.
  static let responses: [HelperResponse] = [
    .handshakeAccepted(contractVersion: HelperContract.version),
    .handshakeRefused(
      helperContractVersion: HelperContract.version, clientContractVersion: 0),
    .success(operationID: HelperFixture.operationID, bytesReclaimed: 1),
    .launchItemChanged(
      operationID: HelperFixture.operationID,
      change: LaunchItemChange(
        item: HelperFixture.systemLaunchItem,
        previousEnabled: true,
        newEnabled: false,
        changedAt: HelperFixture.changeInstant
      )
    ),
    .refused(operationID: nil, reason: .versionMismatch),
    .failed(operationID: HelperFixture.operationID, reason: "gone"),
  ]

  @Test("a request payload cannot be read as a response", arguments: requests)
  func requestPayloadCannotBeReadAsResponse(request: HelperRequest) throws {
    let codec = HelperWireCodec()
    let encoded = try codec.encode(request)
    #expect(throws: (any Error).self) {
      try codec.decodeResponse(from: encoded)
    }
  }

  @Test("a response payload cannot be read as a request", arguments: responses)
  func responsePayloadCannotBeReadAsRequest(response: HelperResponse) throws {
    let codec = HelperWireCodec()
    let encoded = try codec.encode(response)
    #expect(throws: (any Error).self) {
      try codec.decodeRequest(from: encoded)
    }
  }

  @Test("the response fixtures cover every case the contract declares")
  func responseFixturesCoverEveryCaseTheContractDeclares() {
    #expect(Set(Self.responses.map(\.kind)) == Set(HelperResponseKind.allCases))
  }

  /// An encoder whose key order is arbitrary fails this intermittently, which
  /// is the point: the wire form has to be one form, not one of several.
  @Test("encoding is stable, so the same message twice is the same bytes")
  func encodingIsStable() throws {
    let codec = HelperWireCodec()
    let request = HelperFixture.remove(
      HelperFixture.systemAllowedTarget,
      destination: .safetyNetStore(storeDirectory: HelperFixture.safetyNetStore))
    let first = try codec.encode(request)
    let second = try codec.encode(request)
    #expect(first == second)
  }
}

@Suite("Helper request reconciliation identifiers")
struct HelperRequestIdentifierTests {

  @Test("a handshake belongs to no plan and no operation")
  func handshakeBelongsToNoPlanAndNoOperation() {
    #expect(HelperFixture.handshake().planID == nil)
    #expect(HelperFixture.handshake().operationID == nil)
  }

  @Test("a remove names the plan and operation it belongs to")
  func removeNamesItsPlanAndOperation() {
    let request = HelperFixture.remove(HelperFixture.systemAllowedTarget)
    #expect(request.planID == HelperFixture.planID)
    #expect(request.operationID == HelperFixture.operationID)
  }

  @Test("a launch item change names the plan and operation it belongs to")
  func launchItemChangeNamesItsPlanAndOperation() {
    let request = HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem)
    #expect(request.planID == HelperFixture.planID)
    #expect(request.operationID == HelperFixture.operationID)
  }

  @Test("a maintenance run names the plan and operation it belongs to")
  func maintenanceRunNamesItsPlanAndOperation() {
    let request = HelperFixture.runMaintenance()
    #expect(request.planID == HelperFixture.planID)
    #expect(request.operationID == HelperFixture.operationID)
  }
}
