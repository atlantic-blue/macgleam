import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// C31 stage four and C10's denylist supremacy. The helper checks the target
/// against its own effective denylist, built from a catalogue it verified
/// itself. The app's opinion is not consulted, so a compromised app process
/// cannot make the helper cross the denylist.
@Suite("Helper policy denylist supremacy")
struct HelperPolicyDenylistTests {

  static let blockedTargets = [
    "/Library/Blocked",
    "/Library/Blocked/com.example.agent.plist",
    "/Library/Blocked/nested/deeper/precious.db",
    "/System",
    "/System/Library/CoreServices/Finder.app",
  ]

  @Test("a denylisted system target is refused denylisted", arguments: blockedTargets)
  func denylistedSystemTargetIsRefused(target: String) async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.path(target)), from: HelperFixture.trustedClient)
    #expect(admission == .refused(.denylisted))
  }

  @Test("the refusal does not change with what the request claims about the target")
  func refusalDoesNotChangeWithWhatTheRequestClaims() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let variations: [HelperRequest] = [
      HelperFixture.remove(HelperFixture.systemDenylistedTarget, destination: .permanent),
      HelperFixture.remove(
        HelperFixture.systemDenylistedTarget,
        destination: .userTrash(userHome: HelperFixture.userHome)),
      HelperFixture.remove(
        HelperFixture.systemDenylistedTarget,
        planID: HelperFixture.otherPlanID,
        operationID: HelperFixture.otherOperationID),
    ]
    for request in variations {
      #expect(policy.admit(request, from: HelperFixture.trustedClient) == .refused(.denylisted))
    }
  }

  @Test("a launch item resolving onto a denylisted path is refused denylisted")
  func launchItemOnADenylistedPathIsRefused() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.setLaunchItemEnabled(HelperFixture.denylistedLaunchItem, enabled: true),
      from: HelperFixture.trustedClient)
    #expect(admission == .refused(.denylisted))
  }

  @Test("a sibling directory whose name only shares a prefix is not blocked")
  func siblingSharingAPrefixIsNotBlocked() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.path("/Library/BlockedNot/file.log")),
      from: HelperFixture.trustedClient)
    #expect(admission == .admitted)
  }

  @Test("the helper enforces the denylist it holds, not the one the app holds")
  func helperEnforcesItsOwnDenylist() async throws {
    let appBelievesNothingIsBlocked = try await HelperFixture.verifiedDenylist(blocking: [])
    let helperKnowsBetter = try await HelperFixture.verifiedDenylist()
    #expect(appBelievesNothingIsBlocked.blocks(HelperFixture.systemDenylistedTarget) == false)
    let policy = try makeHandshakenPolicy(denylist: helperKnowsBetter)
    #expect(
      policy.admit(
        HelperFixture.remove(HelperFixture.systemDenylistedTarget),
        from: HelperFixture.trustedClient) == .refused(.denylisted))
  }

  @Test("a catalogue the helper cannot verify never becomes the denylist it enforces")
  func unverifiableCatalogueNeverBecomesTheEnforcedDenylist() async throws {
    let store = try HelperFixture.catalogStore()
    var tampered = try HelperFixture.signedCatalog(version: 2, blocking: [])
    tampered = RuleCatalog(
      version: tampered.version,
      signature: Data(repeating: 0x00, count: tampered.signature.count),
      cleanupRules: tampered.cleanupRules,
      adwareRules: tampered.adwareRules,
      denylist: tampered.denylist
    )
    await #expect(throws: RuleCatalogError.signatureInvalid) {
      _ = try await store.apply(tampered)
    }
    let policy = try makeHandshakenPolicy(denylist: await store.effectiveDenylist)
    #expect(
      policy.admit(
        HelperFixture.remove(HelperFixture.systemDenylistedTarget),
        from: HelperFixture.trustedClient) == .refused(.denylisted))
  }

  @Test("no request in the contract can carry a rule catalogue for the helper to adopt")
  func noRequestCanCarryARuleCatalogue() throws {
    let codec = HelperWireCodec()
    let smuggled = try helperWirePayload(
      json: #"{"remove":{"denylist":{"patterns":[]},"catalog":{"version":{"value":99}}}}"#)
    #expect(throws: (any Error).self) {
      try codec.decodeRequest(from: smuggled)
    }
  }
}
