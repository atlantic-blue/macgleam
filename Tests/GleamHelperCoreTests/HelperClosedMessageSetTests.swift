import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// C30's first guarantee: the helper is not a general file service. There is
/// no request carrying a command string, a shell fragment or an arbitrary
/// verb, and none can be smuggled in over the wire either.
@Suite("Helper closed message set")
struct HelperClosedMessageSetTests {

  static let hostileVerbs = [
    "runShell",
    "exec",
    "run",
    "command",
    "adoptRuleCatalog",
    "setDenylist",
    "removeAnything",
    "Remove",
    "remove ",
  ]

  static let hostilePayloads = [
    #"{"runShell":{"command":"rm -rf /"}}"#,
    #"{"exec":{"_0":"/bin/sh","_1":["-c","rm -rf /"]}}"#,
    #"{"adoptRuleCatalog":{"denylist":{"patterns":[]}}}"#,
    #"{"setDenylist":{"patterns":[]}}"#,
    #"{}"#,
    #"[]"#,
    #""remove""#,
    #"{"remove":{},"runShell":{"command":"rm -rf /"}}"#,
  ]

  /// A handshake refusal names both versions by construction. A payload that
  /// names one of them is not a refusal the app can act on, so it must fail to
  /// decode rather than arrive with a zero in the missing half.
  static let halfNamedHandshakeRefusals = [
    #"{"handshakeRefused":{"helperContractVersion":7}}"#,
    #"{"handshakeRefused":{"clientContractVersion":3}}"#,
    #"{"handshakeRefused":{}}"#,
  ]

  static let knownRequests: [HelperRequest] = [
    HelperFixture.handshake(),
    HelperFixture.remove(HelperFixture.systemAllowedTarget),
    HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem),
    HelperFixture.runMaintenance(),
  ]

  @Test("each contract message encodes as exactly one named verb", arguments: knownRequests)
  func eachMessageEncodesAsOneNamedVerb(request: HelperRequest) throws {
    let verb = try helperWireVerb(of: HelperWireCodec().encode(request))
    #expect(
      ["handshake", "remove", "setLaunchItemEnabled", "runMaintenance"].contains(verb),
      "the wire verb must be one of the contract's four, not \(verb)")
  }

  @Test(
    "renaming the verb of a valid remove makes the payload undecodable",
    arguments: hostileVerbs
  )
  func renamingTheVerbMakesThePayloadUndecodable(verb: String) throws {
    let codec = HelperWireCodec()
    let valid = try codec.encode(HelperFixture.remove(HelperFixture.systemAllowedTarget))
    let mutated = try helperWirePayload(valid, renamingVerbTo: verb)
    #expect(throws: (any Error).self) {
      try codec.decodeRequest(from: mutated)
    }
  }

  @Test("a payload naming a verb outside the contract fails to decode", arguments: hostilePayloads)
  func payloadNamingAVerbOutsideTheContractFailsToDecode(json: String) throws {
    let data = try helperWirePayload(json: json)
    #expect(throws: (any Error).self) {
      try HelperWireCodec().decodeRequest(from: data)
    }
  }

  @Test("a remove missing its target fails to decode rather than defaulting one")
  func removeMissingItsTargetFailsToDecode() throws {
    let data = try helperWirePayload(
      json: #"{"remove":{"destination":{"permanent":{}},"planID":"\#(HelperFixture.planID)"}}"#)
    #expect(throws: (any Error).self) {
      try HelperWireCodec().decodeRequest(from: data)
    }
  }

  @Test(
    "a target that is not an absolute normalised path fails to decode rather than normalising",
    arguments: ["../../etc/passwd", "/Library/../etc/passwd", "Library/Blocked", "/Library/", ""]
  )
  func nonConformingTargetFailsToDecode(target: String) throws {
    let codec = HelperWireCodec()
    let valid = try codec.encode(HelperFixture.remove(HelperFixture.systemAllowedTarget))
    let mutated = try helperWirePayload(valid, replacingTargetWith: target)
    #expect(throws: (any Error).self) {
      try codec.decodeRequest(from: mutated)
    }
  }

  @Test("a removal destination outside the contract's three fails to decode")
  func removalDestinationOutsideTheContractFailsToDecode() throws {
    let codec = HelperWireCodec()
    let valid = try codec.encode(
      HelperFixture.remove(
        HelperFixture.systemAllowedTarget,
        destination: .safetyNetStore(storeDirectory: HelperFixture.safetyNetStore)))
    let mutated = try helperWirePayload(
      valid, replacingDestinationWith: ["anywhere": ["path": "/"]])
    #expect(throws: (any Error).self) {
      try codec.decodeRequest(from: mutated)
    }
  }

  @Test("a maintenance task outside the contract's five fails to decode")
  func maintenanceTaskOutsideTheContractFailsToDecode() throws {
    let data = try helperWirePayload(
      json: """
        {"runMaintenance":{"task":"eraseDisk","planID":"\(HelperFixture.planID)",\
        "operationID":"\(HelperFixture.operationID)"}}
        """)
    #expect(throws: (any Error).self) {
      try HelperWireCodec().decodeRequest(from: data)
    }
  }

  @Test(
    "a handshake refusal naming only one version fails to decode rather than defaulting one",
    arguments: halfNamedHandshakeRefusals
  )
  func handshakeRefusalNamingOneVersionFailsToDecode(json: String) throws {
    let data = try helperWirePayload(json: json)
    #expect(throws: (any Error).self) {
      try HelperWireCodec().decodeResponse(from: data)
    }
  }

  @Test("a version outside the range the contract declares fails to decode")
  func versionOutsideTheContractsRangeFailsToDecode() throws {
    let codec = HelperWireCodec()
    #expect(throws: (any Error).self) {
      try codec.decodeResponse(
        from: try helperWirePayload(
          json: #"{"handshakeRefused":{"helperContractVersion":70000,"clientContractVersion":3}}"#))
    }
    #expect(throws: (any Error).self) {
      try codec.decodeResponse(
        from: try helperWirePayload(
          json: #"{"handshakeRefused":{"helperContractVersion":7,"clientContractVersion":-1}}"#))
    }
  }

  @Test("a refusal outside the contract's five fails to decode")
  func refusalOutsideTheContractFailsToDecode() throws {
    let data = try helperWirePayload(
      json: #"{"refused":{"reason":"allowedBecauseTheAppSaidSo"}}"#)
    #expect(throws: (any Error).self) {
      try HelperWireCodec().decodeResponse(from: data)
    }
  }

  @Test("empty bytes decode as nothing in either direction")
  func emptyBytesDecodeAsNothing() {
    let codec = HelperWireCodec()
    #expect(throws: (any Error).self) {
      try codec.decodeRequest(from: Data())
    }
    #expect(throws: (any Error).self) {
      try codec.decodeResponse(from: Data())
    }
  }
}
