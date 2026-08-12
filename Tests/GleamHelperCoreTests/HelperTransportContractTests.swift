import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// C31's last guarantee: the full policy runs against a test double transport
/// in continuous integration. Every message here crosses the wire encoding in
/// both directions, so a policy answer and a serialisation break are caught by
/// the same test.
@Suite("Helper policy across the test double transport")
struct HelperTransportContractTests {

  /// Both sides of a disagreement, at the extremes and away from them: the
  /// helper ahead of the app and the app ahead of the helper. Which of the two
  /// is larger is the whole content of the reply for the app, so every test
  /// here runs against both directions rather than one.
  static let disagreements: [HelperVersionDisagreement] = [
    HelperVersionDisagreement(helperVersion: 7, clientVersion: 3),
    HelperVersionDisagreement(helperVersion: 3, clientVersion: 7),
    HelperVersionDisagreement(helperVersion: 0, clientVersion: UInt16.max),
    HelperVersionDisagreement(helperVersion: UInt16.max, clientVersion: 0),
  ]

  private func transport(
    policy: HelperConnectionPolicy,
    helperContractVersion: UInt16 = HelperContract.version
  ) -> LoopbackHelperTransport {
    LoopbackHelperTransport(policy: policy, helperContractVersion: helperContractVersion)
  }

  /// A connection whose helper speaks one version and whose client claimed
  /// another, driven the way the app drives it: a handshake sent across the
  /// transport, and whatever came back.
  private func replyToDisagreeingHandshake(
    _ disagreement: HelperVersionDisagreement
  ) async throws -> HelperResponse {
    let policy = makeHelperPolicy(
      denylist: try await HelperFixture.verifiedDenylist(),
      contractVersion: disagreement.helperVersion)
    return try transport(policy: policy, helperContractVersion: disagreement.helperVersion)
      .send(
        HelperFixture.handshake(version: disagreement.clientVersion),
        from: HelperFixture.trustedClient)
  }

  @Test("a handshake at the helper's version is accepted across the wire")
  func handshakeIsAcceptedAcrossTheWire() async throws {
    let policy = makeHelperPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let reply = try transport(policy: policy)
      .send(HelperFixture.handshake(), from: HelperFixture.trustedClient)
    #expect(reply == .handshakeAccepted(contractVersion: HelperContract.version))
  }

  @Test("an admitted remove comes back as a success naming its own operation")
  func admittedRemoveComesBackAsSuccess() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let reply = try transport(policy: policy)
      .send(
        HelperFixture.remove(HelperFixture.systemAllowedTarget),
        from: HelperFixture.trustedClient)
    #expect(reply == .success(correlationID: HelperFixture.operationID, bytesReclaimed: 4096))
  }

  @Test("a refused remove comes back naming the operation it refused, so the report reconciles")
  func refusedRemoveNamesTheOperationItRefused() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let reply = try transport(policy: policy)
      .send(
        HelperFixture.remove(
          HelperFixture.systemDenylistedTarget, operationID: HelperFixture.otherOperationID),
        from: HelperFixture.trustedClient)
    #expect(reply == .refused(correlationID: HelperFixture.otherOperationID, reason: .denylisted))
  }

  @Test("a refused handshake comes back naming no operation")
  func refusedHandshakeNamesNoOperation() async throws {
    let policy = makeHelperPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let reply = try transport(policy: policy)
      .send(HelperFixture.handshake(), from: HelperFixture.intruderClient)
    #expect(reply == .refused(correlationID: nil, reason: .identityRejected))
  }

  // MARK: The version disagreement the app acts on

  @Test(
    "a version disagreement comes back as a handshake refusal naming both versions",
    arguments: disagreements
  )
  func versionDisagreementComesBackNamingBothVersions(
    disagreement: HelperVersionDisagreement
  ) async throws {
    let reply = try await replyToDisagreeingHandshake(disagreement)
    #expect(
      reply
        == .handshakeRefused(
          helperContractVersion: disagreement.helperVersion,
          clientContractVersion: disagreement.clientVersion),
      "the app learns the two numbers from the exchange, never from the helper's own records")
  }

  @Test("a helper behind the app is visible to the app from the reply alone")
  func helperBehindTheAppIsVisibleFromTheReply() async throws {
    let reply = try await replyToDisagreeingHandshake(
      HelperVersionDisagreement(helperVersion: 3, clientVersion: 7))
    let versions = try #require(reply.refusedVersions)
    #expect(
      versions.helperVersion < versions.clientVersion,
      "the helper is the old one here, so the update prompt is for the helper")
  }

  @Test("an app behind the helper is visible to the app from the reply alone")
  func appBehindTheHelperIsVisibleFromTheReply() async throws {
    let reply = try await replyToDisagreeingHandshake(
      HelperVersionDisagreement(helperVersion: 7, clientVersion: 3))
    let versions = try #require(reply.refusedVersions)
    #expect(
      versions.helperVersion > versions.clientVersion,
      "the app is the old one here, so the update prompt is for the app")
  }

  @Test(
    "the two versions a handshake refusal carries are never equal", arguments: disagreements)
  func theTwoVersionsInAHandshakeRefusalAreNeverEqual(
    disagreement: HelperVersionDisagreement
  ) async throws {
    let reply = try await replyToDisagreeingHandshake(disagreement)
    let versions = try #require(reply.refusedVersions)
    #expect(versions.helperVersion != versions.clientVersion)
  }

  @Test("a handshake the helper agrees with is never answered with a refusal")
  func agreedHandshakeIsNeverAnsweredWithARefusal() async throws {
    let policy = makeHelperPolicy(
      denylist: try await HelperFixture.verifiedDenylist(), contractVersion: 7)
    let reply = try transport(policy: policy, helperContractVersion: 7)
      .send(HelperFixture.handshake(version: 7), from: HelperFixture.trustedClient)
    #expect(reply == .handshakeAccepted(contractVersion: 7))
  }

  // MARK: What a refusal tells a client the helper could not verify

  @Test(
    "a client that fails identity verification is told nothing about the helper's version",
    arguments: [UInt16(0), 3, 7, UInt16.max]
  )
  func identityRefusalCarriesNoVersion(claimedVersion: UInt16) async throws {
    let policy = makeHelperPolicy(
      denylist: try await HelperFixture.verifiedDenylist(), contractVersion: 7)
    let reply = try transport(policy: policy, helperContractVersion: 7)
      .send(
        HelperFixture.handshake(version: claimedVersion), from: HelperFixture.intruderClient)
    #expect(
      reply.refusedVersions == nil,
      "a handshake refused on identity must not name a version, whatever the intruder claimed")
  }

  @Test("an identity refusal is a plain refusal, not a handshake refusal")
  func identityRefusalIsAPlainRefusal() async throws {
    let policy = makeHelperPolicy(
      denylist: try await HelperFixture.verifiedDenylist(), contractVersion: 7)
    let reply = try transport(policy: policy, helperContractVersion: 7)
      .send(HelperFixture.handshake(version: 3), from: HelperFixture.intruderClient)
    #expect(reply == .refused(correlationID: nil, reason: .identityRejected))
  }

  // MARK: A refused connection stays refused

  @Test("a corrected handshake after a refused one is still not accepted across the wire")
  func correctedHandshakeAfterARefusedOneIsStillNotAccepted() async throws {
    let policy = makeHelperPolicy(
      denylist: try await HelperFixture.verifiedDenylist(), contractVersion: 7)
    let wire = transport(policy: policy, helperContractVersion: 7)
    _ = try wire.send(HelperFixture.handshake(version: 3), from: HelperFixture.trustedClient)
    let reply = try wire.send(
      HelperFixture.handshake(version: 7), from: HelperFixture.trustedClient)
    #expect(
      reply.kind != .handshakeAccepted,
      "a stale app must not be able to retry its way into a refused connection")
  }

  @Test("a request before any handshake comes back refused versionMismatch, naming no version")
  func requestBeforeAnyHandshakeComesBackRefusedNamingNoVersion() async throws {
    let policy = makeHelperPolicy(
      denylist: try await HelperFixture.verifiedDenylist(), contractVersion: 7)
    let reply = try transport(policy: policy, helperContractVersion: 7)
      .send(
        HelperFixture.remove(HelperFixture.systemAllowedTarget),
        from: HelperFixture.trustedClient)
    #expect(
      reply == .refused(correlationID: HelperFixture.operationID, reason: .versionMismatch))
  }

  @Test("a user domain remove comes back refused notSystemDomain")
  func userDomainRemoveComesBackRefused() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let reply = try transport(policy: policy)
      .send(
        HelperFixture.remove(HelperFixture.userAllowedTarget), from: HelperFixture.trustedClient)
    #expect(
      reply == .refused(correlationID: HelperFixture.operationID, reason: .notSystemDomain))
  }

  @Test("an admitted launch item change comes back as the recorded change")
  func admittedLaunchItemChangeComesBackAsTheRecordedChange() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let reply = try transport(policy: policy)
      .send(
        HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem, enabled: false),
        from: HelperFixture.trustedClient)
    #expect(
      reply
        == .launchItemChanged(
          correlationID: HelperFixture.operationID,
          change: LaunchItemChange(
            item: HelperFixture.systemLaunchItem,
            previousEnabled: true,
            newEnabled: false,
            changedAt: HelperFixture.changeInstant
          )
        )
    )
  }

  @Test("a maintenance run reclaims nothing and comes back naming its operation")
  func maintenanceRunComesBackNamingItsOperation() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let reply = try transport(policy: policy)
      .send(
        HelperFixture.runMaintenance(.rebuildLaunchServicesDatabase),
        from: HelperFixture.trustedClient)
    #expect(reply == .success(correlationID: HelperFixture.operationID, bytesReclaimed: 0))
  }

  @Test("a target with spaces and unicode survives the transport and is still admitted")
  func awkwardTargetSurvivesTheTransport() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let target = HelperFixture.path("/Library/Application Support/Ünïcödé 🚀/файл.log")
    let reply = try transport(policy: policy)
      .send(HelperFixture.remove(target), from: HelperFixture.trustedClient)
    #expect(reply == .success(correlationID: HelperFixture.operationID, bytesReclaimed: 4096))
  }

  @Test("the transport never admits a message the helper's policy refused")
  func transportNeverAdmitsARefusedMessage() async throws {
    let policy = try mismatchedVersionPolicy()
    let requests = [
      HelperFixture.remove(HelperFixture.systemAllowedTarget),
      HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem),
      HelperFixture.runMaintenance(),
    ]
    for request in requests {
      let reply = try transport(policy: policy).send(request, from: HelperFixture.trustedClient)
      #expect(
        reply == .refused(correlationID: HelperFixture.operationID, reason: .versionMismatch))
    }
  }

  private func mismatchedVersionPolicy() throws -> HelperConnectionPolicy {
    let denylist = Denylist(
      patterns: HelperFixture.denylistedRoots.map { PathPattern(pattern: $0) })
    let policy = makeHelperPolicy(denylist: denylist, contractVersion: 7)
    try #require(
      policy.admit(HelperFixture.handshake(version: 3), from: HelperFixture.trustedClient)
        == .refused(.versionMismatch))
    return policy
  }
}
