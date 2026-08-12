import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// The daemon's answers, decided from the request alone.
///
/// The rule under test is one sentence: a reply carries the correlation
/// identifier of the request that caused it. It is asserted over every request
/// the contract has and over both kinds of attribution, because the whole
/// point of version two is that a change somebody made by hand reconciles
/// against itself rather than against a plan that never existed.
@Suite("Helper reply routing")
struct HelperReplyRouterTests {

  private static let router = HelperReplyRouter()

  private static let change = LaunchItemChange(
    item: HelperFixture.systemLaunchItem,
    previousEnabled: true,
    newEnabled: false,
    changedAt: HelperFixture.changeInstant
  )

  /// Every request that performs work, so a case added to the contract
  /// arrives here rather than being covered by whichever ones a test named.
  private static let workingRequests: [HelperRequest] = [
    HelperFixture.remove(HelperFixture.systemAllowedTarget),
    HelperFixture.runMaintenance(),
    HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem),
    HelperFixture.directLaunchItemChange(HelperFixture.systemLaunchItem),
  ]

  @Test("a completion echoes the request that caused it", arguments: workingRequests)
  func aCompletionEchoesTheRequestThatCausedIt(request: HelperRequest) {
    let reply = Self.router.completed(request, bytesReclaimed: 4096)
    #expect(reply.correlationID == request.correlationID)
  }

  @Test("a failure echoes the request that caused it", arguments: workingRequests)
  func aFailureEchoesTheRequestThatCausedIt(request: HelperRequest) {
    let reply = Self.router.failed(request, because: "The volume is read only.")
    #expect(reply.kind == .failed)
    #expect(reply.correlationID == request.correlationID)
  }

  @Test("a refusal echoes the request that caused it", arguments: workingRequests)
  func aRefusalEchoesTheRequestThatCausedIt(request: HelperRequest) {
    let reply = Self.router.refused(request, because: .denylisted, mismatch: nil)
    #expect(reply.kind == .refused)
    #expect(reply.correlationID == request.correlationID)
  }

  @Test("a launch item change echoes the request, planned and direct alike")
  func aLaunchItemChangeEchoesTheRequest() {
    for request in [
      HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem),
      HelperFixture.directLaunchItemChange(HelperFixture.systemLaunchItem),
    ] {
      let reply = Self.router.changed(request, to: Self.change)
      #expect(reply.kind == .launchItemChanged)
      #expect(reply.correlationID == request.correlationID)
    }
  }

  @Test("a handshake completes as an acceptance naming the version in force")
  func aHandshakeCompletesAsAnAcceptance() {
    let reply = Self.router.completed(HelperFixture.handshake(), bytesReclaimed: 0)
    #expect(reply == .handshakeAccepted(contractVersion: HelperContract.version))
  }

  @Test("no reply to a handshake claims work was done")
  func noReplyToAHandshakeClaimsWorkWasDone() {
    let handshake = HelperFixture.handshake()
    #expect(Self.router.failed(handshake, because: "anything").kind == .refused)
    #expect(Self.router.changed(handshake, to: Self.change).kind == .refused)
  }

  @Test("a change is never answered to a request that did not ask for one")
  func aChangeIsNeverAnsweredToARequestThatDidNotAskForOne() {
    for request in [
      HelperFixture.remove(HelperFixture.systemAllowedTarget),
      HelperFixture.runMaintenance(),
    ] {
      let reply = Self.router.changed(request, to: Self.change)
      #expect(reply.kind == .refused)
      #expect(reply.correlationID == request.correlationID)
    }
  }

  @Test("a version disagreement is the one refusal that names numbers")
  func aVersionDisagreementNamesNumbers() throws {
    let mismatch = HelperVersionMismatch(helperContractVersion: 2, clientContractVersion: 1)
    let reply = Self.router.refused(
      HelperFixture.handshake(version: 1), because: .versionMismatch, mismatch: mismatch)
    let versions = try #require(reply.refusedVersions)
    #expect(versions.helperVersion == 2)
    #expect(versions.clientVersion == 1)
  }

  @Test("a handshake refused on identity names no version at all")
  func aHandshakeRefusedOnIdentityNamesNoVersion() {
    let reply = Self.router.refused(
      HelperFixture.handshake(), because: .identityRejected, mismatch: nil)
    #expect(reply.kind == .refused)
    #expect(reply.refusedVersions == nil)
  }

  @Test("a working request is never answered with a version, whatever it was refused for")
  func aWorkingRequestIsNeverAnsweredWithAVersion() {
    let mismatch = HelperVersionMismatch(helperContractVersion: 2, clientContractVersion: 1)
    for request in Self.workingRequests {
      let reply = Self.router.refused(
        request, because: .versionMismatch, mismatch: mismatch)
      #expect(reply.refusedVersions == nil)
      #expect(reply.correlationID == request.correlationID)
    }
  }
}
