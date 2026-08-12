import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// C30 from version two onwards: a privileged launch item change carries who
/// asked for it, and every reply echoes the identifier of the request that
/// caused it.
///
/// The counter has moved on since (the archive family took it to three), so
/// what these pin is the shape rather than the number: whatever the current
/// version is, the version before it is refused and both numbers are named.
///
/// Version one carried a plan and an operation on that request, which meant a
/// change somebody made in the interface had no honest way onto the wire: it
/// belongs to no plan, so either the field lied or the change went out
/// unattributed. Version two carries a `ChangeAttribution` instead, which has
/// no case meaning none.
@Suite("Helper contract version two")
struct HelperContractVersionTwoTests {

  @Test("the contract is past version one, where the attribution went onto the wire")
  func theContractIsPastVersionOne() {
    #expect(HelperContract.version >= 2)
  }

  @Test("the version both processes enforce is the one declaration, not a copy")
  func theVersionBothProcessesEnforceIsTheOneDeclaration() async throws {
    let policy = makeHelperPolicy(denylist: try await HelperFixture.verifiedDenylist())
    #expect(
      policy.admit(
        HelperFixture.handshake(version: HelperContract.version),
        from: HelperFixture.trustedClient) == .admitted)
    #expect(
      policy.admit(
        HelperFixture.handshake(version: HelperContract.version - 1),
        from: HelperFixture.trustedClient) == .refused(.versionMismatch))
  }

  @Test("a client one version behind is refused, and the refusal names both numbers")
  func aClientOneVersionBehindIsRefusedNamingBothNumbers() async throws {
    let transport = LoopbackHelperTransport(
      policy: makeHelperPolicy(denylist: try await HelperFixture.verifiedDenylist()))
    let reply = try transport.send(
      HelperFixture.handshake(version: HelperContract.version - 1),
      from: HelperFixture.trustedClient)
    let versions = try #require(reply.refusedVersions)
    #expect(versions.helperVersion == HelperContract.version)
    #expect(versions.clientVersion == HelperContract.version - 1)
  }

  @Test("a client one version behind is refused every request after the handshake too")
  func aClientOneVersionBehindIsRefusedEveryLaterRequest() async throws {
    let policy = makeHelperPolicy(denylist: try await HelperFixture.verifiedDenylist())
    _ = policy.admit(
      HelperFixture.handshake(version: HelperContract.version - 1),
      from: HelperFixture.trustedClient)
    #expect(
      policy.admit(
        HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem),
        from: HelperFixture.trustedClient) == .refused(.versionMismatch))
  }

  // MARK: - Attribution on the wire

  @Test("a planned change names the plan and echoes the operation")
  func aPlannedChangeNamesThePlanAndEchoesTheOperation() {
    let request = HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem)
    #expect(request.planID == HelperFixture.planID)
    #expect(request.correlationID == HelperFixture.operationID)
  }

  @Test("a direct change belongs to no plan and echoes its own identifier")
  func aDirectChangeBelongsToNoPlan() {
    let request = HelperFixture.directLaunchItemChange(HelperFixture.systemLaunchItem)
    #expect(request.planID == nil)
    #expect(request.correlationID == HelperFixture.directChangeID)
  }

  @Test("the attribution survives the wire, both kinds, byte for byte")
  func theAttributionSurvivesTheWire() throws {
    let codec = HelperWireCodec()
    for request in [
      HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem, enabled: true),
      HelperFixture.directLaunchItemChange(HelperFixture.systemLaunchItem, enabled: true),
    ] {
      let decoded = try codec.decodeRequest(from: codec.encode(request))
      #expect(decoded == request)
      #expect(decoded.correlationID == request.correlationID)
      #expect(decoded.planID == request.planID)
    }
  }

  @Test("the encoded change carries an attribution and no bare operation identifier")
  func theEncodedChangeCarriesAnAttribution() throws {
    let body = try helperWireBody(
      of: HelperWireCodec().encode(
        HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem)))
    #expect(body["attribution"] != nil)
    #expect(body["operationID"] == nil)
    #expect(body["planID"] == nil)
  }

  // MARK: - The reply echoes what caused it

  @Test("every reply echoes the correlation identifier of the request that caused it")
  func everyReplyEchoesTheCorrelationIdentifier() async throws {
    let transport = LoopbackHelperTransport(
      policy: try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist()))
    let requests = [
      HelperFixture.remove(HelperFixture.systemAllowedTarget),
      HelperFixture.runMaintenance(),
      HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem),
      HelperFixture.directLaunchItemChange(HelperFixture.systemLaunchItem),
    ]
    for request in requests {
      let reply = try transport.send(request, from: HelperFixture.trustedClient)
      #expect(reply.correlationID == request.correlationID)
    }
  }

  @Test("a refused change echoes its own identifier, planned and direct alike")
  func aRefusedChangeEchoesItsOwnIdentifier() async throws {
    let transport = LoopbackHelperTransport(
      policy: try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist()))
    for request in [
      HelperFixture.setLaunchItemEnabled(HelperFixture.denylistedLaunchItem),
      HelperFixture.directLaunchItemChange(HelperFixture.denylistedLaunchItem),
    ] {
      let reply = try transport.send(request, from: HelperFixture.trustedClient)
      #expect(reply.kind == .refused)
      #expect(reply.correlationID == request.correlationID)
    }
  }

  @Test("a direct change identifier reaches the reply unchanged, over many identifiers")
  func aDirectChangeIdentifierReachesTheReplyUnchanged() async throws {
    let transport = LoopbackHelperTransport(
      policy: try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist()))
    for suffix in UInt8(0x10)...UInt8(0x1F) {
      let changeID = HelperFixture.uuid(suffix)
      let reply = try transport.send(
        HelperFixture.directLaunchItemChange(
          HelperFixture.systemLaunchItem, changeID: changeID),
        from: HelperFixture.trustedClient)
      #expect(reply.correlationID == changeID)
    }
  }
}

extension HelperResponse {
  /// The request a reply answers, as the app reads it. Duplicated from the
  /// client rather than shared, because a test that borrowed the client's own
  /// reading of the wire would prove only that it agrees with itself.
  var correlationID: UUID? {
    switch self {
    case .handshakeAccepted, .handshakeRefused:
      return nil
    case .success(let id, _), .launchItemChanged(let id, _), .failed(let id, _),
      .archived(let id, _), .restoredArchive(let id, _), .discardedArchive(let id):
      return id
    case .refused(let id, _):
      return id
    }
  }
}
