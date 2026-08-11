import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// C31's guarantees are stated in evaluation order: identity, handshake,
/// domain, denylist. Each test here builds a request that would fail at two
/// stages at once and pins the earlier one as the answer, so the sequence is
/// fixed rather than each check merely existing. A refusal naming a later
/// stage would tell an attacker what the helper knows about a target it never
/// should have looked at.
@Suite("Helper policy evaluation order")
struct HelperPolicyEvaluationOrderTests {

  /// A connection that never completed a handshake, so the handshake stage
  /// would refuse anything the identity stage let through.
  private func unhandshakenPolicy(denylist: Denylist) -> HelperConnectionPolicy {
    makeHelperPolicy(denylist: denylist, contractVersion: 7)
  }

  /// A connection whose handshake claimed a version the helper does not
  /// speak, so the handshake stage refuses everything after it.
  private func mismatchedPolicy(denylist: Denylist) throws -> HelperConnectionPolicy {
    let policy = makeHelperPolicy(denylist: denylist, contractVersion: 7)
    try #require(
      policy.admit(HelperFixture.handshake(version: 3), from: HelperFixture.trustedClient)
        == .refused(.versionMismatch))
    return policy
  }

  private var intruder: ClientIdentity {
    HelperFixture.client(bundleIdentifier: "com.example.intruder")
  }

  // MARK: Identity before everything after it

  @Test("identity is checked before the handshake: an intruder's bad version refuses on identity")
  func identityIsCheckedBeforeTheHandshake() async throws {
    let policy = unhandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(HelperFixture.handshake(version: 3), from: intruder)
    #expect(admission == .refused(.identityRejected))
  }

  @Test(
    "identity is checked before the domain: an intruder's user domain target refuses on identity"
  )
  func identityIsCheckedBeforeTheDomain() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.userAllowedTarget), from: intruder)
    #expect(admission == .refused(.identityRejected))
  }

  @Test("identity is checked before the denylist: an intruder's blocked target refuses on identity")
  func identityIsCheckedBeforeTheDenylist() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.systemDenylistedTarget), from: intruder)
    #expect(admission == .refused(.identityRejected))
  }

  // MARK: Handshake before everything after it

  @Test("the handshake is checked before the domain: a stale app's user target refuses on version")
  func handshakeIsCheckedBeforeTheDomain() async throws {
    let policy = try mismatchedPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.userAllowedTarget), from: HelperFixture.trustedClient)
    #expect(admission == .refused(.versionMismatch))
  }

  @Test(
    "the handshake is checked before the denylist: a stale app's blocked target refuses on version"
  )
  func handshakeIsCheckedBeforeTheDenylist() async throws {
    let policy = try mismatchedPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.systemDenylistedTarget),
      from: HelperFixture.trustedClient)
    #expect(admission == .refused(.versionMismatch))
  }

  // MARK: Domain before the denylist

  @Test("the domain is checked before the denylist: a blocked user target refuses notSystemDomain")
  func domainIsCheckedBeforeTheDenylist() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.userDenylistedTarget), from: HelperFixture.trustedClient)
    #expect(admission == .refused(.notSystemDomain))
  }

  @Test("the domain is checked before the denylist for launch items too")
  func domainIsCheckedBeforeTheDenylistForLaunchItems() async throws {
    let blockedUserItem = LaunchItemID(value: "com.example.blocked|user")
    let table = HelperLaunchItemTable(locations: [
      blockedUserItem: HelperFixture.userDenylistedTarget
    ])
    let policy = try makeHandshakenPolicy(
      denylist: try await HelperFixture.verifiedDenylist(), launchItems: table)
    let admission = policy.admit(
      HelperFixture.setLaunchItemEnabled(blockedUserItem), from: HelperFixture.trustedClient)
    #expect(admission == .refused(.notSystemDomain))
  }

  // MARK: Resolution, inside the domain stage

  @Test(
    """
    an item the helper cannot resolve refuses malformedRequest even under a \
    denylist that blocks the whole tree it lives in
    """
  )
  func unresolvableLaunchItemRefusesBeforeTheDenylist() async throws {
    let policy = try makeHandshakenPolicy(
      denylist: try await HelperFixture.verifiedDenylist(blocking: ["/Library"]),
      launchItems: HelperLaunchItemTable(locations: [:]))
    let admission = policy.admit(
      HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem),
      from: HelperFixture.trustedClient)
    #expect(
      admission == .refused(.malformedRequest),
      """
      the helper cannot verify least privilege for something it cannot find, \
      and it refuses rather than guessing
      """)
  }

  @Test("resolution is inside the domain stage, so the handshake still answers before it")
  func resolutionIsInsideTheDomainStage() async throws {
    let policy = try mismatchedPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.setLaunchItemEnabled(HelperFixture.unresolvableLaunchItem),
      from: HelperFixture.trustedClient)
    #expect(admission == .refused(.versionMismatch))
  }

  // MARK: Every stage failing at once

  @Test("a request failing every stage at once refuses on identity, the first one")
  func requestFailingEveryStageRefusesOnIdentity() async throws {
    let policy = unhandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    _ = policy.admit(HelperFixture.handshake(version: 3), from: intruder)
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.userDenylistedTarget), from: intruder)
    #expect(admission == .refused(.identityRejected))
  }

  @Test("with identity satisfied, a request failing the rest refuses on the handshake")
  func withIdentitySatisfiedTheHandshakeAnswersNext() async throws {
    let policy = try mismatchedPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.userDenylistedTarget), from: HelperFixture.trustedClient)
    #expect(admission == .refused(.versionMismatch))
  }

  @Test("with identity and handshake satisfied, a request failing the rest refuses on the domain")
  func withIdentityAndHandshakeSatisfiedTheDomainAnswersNext() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.userDenylistedTarget), from: HelperFixture.trustedClient)
    #expect(admission == .refused(.notSystemDomain))
  }

  @Test("with the first three satisfied, the denylist answers last")
  func withTheFirstThreeSatisfiedTheDenylistAnswersLast() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.systemDenylistedTarget),
      from: HelperFixture.trustedClient)
    #expect(admission == .refused(.denylisted))
  }

  @Test("only a request that passes all four stages is admitted")
  func onlyARequestPassingAllFourStagesIsAdmitted() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.systemAllowedTarget), from: HelperFixture.trustedClient)
    #expect(admission == .admitted)
  }
}
