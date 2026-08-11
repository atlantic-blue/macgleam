import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// C31 stage two, and C30's version handshake. The app sends the handshake
/// first. A helper whose contract version differs refuses all further
/// requests with versionMismatch, and neither process assumes the other is
/// current.
@Suite("Helper policy handshake and version")
struct HelperPolicyHandshakeTests {

  static let mismatchedVersions: [UInt16] = [0, 1, UInt16.max]

  @Test("a handshake at the helper's own contract version is admitted")
  func matchingHandshakeIsAdmitted() async throws {
    let policy = makeHelperPolicy(denylist: try await HelperFixture.verifiedDenylist())
    #expect(
      policy.admit(
        HelperFixture.handshake(version: HelperContract.version),
        from: HelperFixture.trustedClient) == .admitted)
  }

  @Test("a matching handshake records no version mismatch")
  func matchingHandshakeRecordsNoMismatch() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    #expect(policy.versionMismatch == nil)
  }

  @Test(
    "a handshake at any other version is refused versionMismatch",
    arguments: mismatchedVersions
  )
  func mismatchedHandshakeIsRefused(version: UInt16) async throws {
    let policy = makeHelperPolicy(
      denylist: try await HelperFixture.verifiedDenylist(), contractVersion: 7)
    #expect(
      policy.admit(HelperFixture.handshake(version: version), from: HelperFixture.trustedClient)
        == .refused(.versionMismatch))
  }

  @Test("the recorded mismatch names the helper's version and the client's")
  func recordedMismatchNamesBothVersions() async throws {
    let policy = makeHelperPolicy(
      denylist: try await HelperFixture.verifiedDenylist(), contractVersion: 7)
    _ = policy.admit(HelperFixture.handshake(version: 3), from: HelperFixture.trustedClient)
    let mismatch = try #require(policy.versionMismatch)
    #expect(mismatch.helperContractVersion == 7)
    #expect(mismatch.clientContractVersion == 3)
  }

  @Test("a client claiming the maximum version is named in the mismatch as it claimed")
  func maximumClaimedVersionIsNamedInTheMismatch() async throws {
    let policy = makeHelperPolicy(
      denylist: try await HelperFixture.verifiedDenylist(), contractVersion: 7)
    _ = policy.admit(
      HelperFixture.handshake(version: UInt16.max), from: HelperFixture.trustedClient)
    let mismatch = try #require(policy.versionMismatch)
    #expect(mismatch.helperContractVersion == 7)
    #expect(mismatch.clientContractVersion == UInt16.max)
  }

  @Test("after a mismatched handshake a remove is refused versionMismatch")
  func removeAfterMismatchedHandshakeIsRefused() async throws {
    let policy = try mismatchedPolicy()
    #expect(
      policy.admit(
        HelperFixture.remove(HelperFixture.systemAllowedTarget),
        from: HelperFixture.trustedClient) == .refused(.versionMismatch))
  }

  @Test("after a mismatched handshake a launch item change is refused versionMismatch")
  func launchItemChangeAfterMismatchedHandshakeIsRefused() async throws {
    let policy = try mismatchedPolicy()
    #expect(
      policy.admit(
        HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem),
        from: HelperFixture.trustedClient) == .refused(.versionMismatch))
  }

  @Test("after a mismatched handshake a maintenance run is refused versionMismatch")
  func maintenanceAfterMismatchedHandshakeIsRefused() async throws {
    let policy = try mismatchedPolicy()
    #expect(
      policy.admit(HelperFixture.runMaintenance(), from: HelperFixture.trustedClient)
        == .refused(.versionMismatch))
  }

  @Test("the recorded mismatch never names two equal versions", arguments: mismatchedVersions)
  func recordedMismatchNeverNamesTwoEqualVersions(version: UInt16) async throws {
    let policy = makeHelperPolicy(
      denylist: try await HelperFixture.verifiedDenylist(), contractVersion: 7)
    _ = policy.admit(HelperFixture.handshake(version: version), from: HelperFixture.trustedClient)
    let mismatch = try #require(policy.versionMismatch)
    #expect(mismatch.helperContractVersion != mismatch.clientContractVersion)
  }

  @Test("a corrected handshake on a refused connection is still refused versionMismatch")
  func correctedHandshakeOnARefusedConnectionIsStillRefused() async throws {
    let policy = try mismatchedPolicy()
    #expect(
      policy.admit(HelperFixture.handshake(version: 7), from: HelperFixture.trustedClient)
        == .refused(.versionMismatch),
      "a stale app must not be able to retry its way into a refused connection")
  }

  @Test("a corrected handshake does not unlock the requests that follow it")
  func correctedHandshakeDoesNotUnlockTheRequestsAfterIt() async throws {
    let policy = try mismatchedPolicy()
    _ = policy.admit(HelperFixture.handshake(version: 7), from: HelperFixture.trustedClient)
    #expect(
      policy.admit(
        HelperFixture.remove(HelperFixture.systemAllowedTarget),
        from: HelperFixture.trustedClient) == .refused(.versionMismatch))
  }

  @Test("a mutating request before any handshake is refused versionMismatch")
  func mutatingRequestBeforeAnyHandshakeIsRefused() async throws {
    let policy = makeHelperPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.systemAllowedTarget), from: HelperFixture.trustedClient)
    #expect(
      admission == .refused(.versionMismatch),
      "no version has been agreed, so the helper treats no agreement as it treats disagreement")
  }

  @Test("a launch item change before any handshake is refused versionMismatch")
  func launchItemChangeBeforeAnyHandshakeIsRefused() async throws {
    let policy = makeHelperPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem),
      from: HelperFixture.trustedClient)
    #expect(admission == .refused(.versionMismatch))
  }

  @Test("a maintenance run before any handshake is refused versionMismatch")
  func maintenanceBeforeAnyHandshakeIsRefused() async throws {
    let policy = makeHelperPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(HelperFixture.runMaintenance(), from: HelperFixture.trustedClient)
    #expect(admission == .refused(.versionMismatch))
  }

  @Test("a request refused before any handshake records no version disagreement")
  func requestBeforeAnyHandshakeRecordsNoDisagreement() async throws {
    let policy = makeHelperPolicy(denylist: try await HelperFixture.verifiedDenylist())
    _ = policy.admit(
      HelperFixture.remove(HelperFixture.systemAllowedTarget), from: HelperFixture.trustedClient)
    #expect(
      policy.versionMismatch == nil,
      "the client claimed no version, so there is no pair of numbers to report")
  }

  @Test("the helper's contract version is the one both processes compile against")
  func helperContractVersionIsShared() {
    #expect(HelperContract.version >= 1)
  }

  /// A connection whose handshake claimed a version the helper does not
  /// speak. Version 7 is the helper here, version 3 the app.
  private func mismatchedPolicy() throws -> HelperConnectionPolicy {
    let denylist = Denylist(
      patterns: HelperFixture.denylistedRoots.map { PathPattern(pattern: $0) })
    let policy = makeHelperPolicy(denylist: denylist, contractVersion: 7)
    try #require(
      policy.admit(HelperFixture.handshake(version: 3), from: HelperFixture.trustedClient)
        == .refused(.versionMismatch))
    return policy
  }
}
