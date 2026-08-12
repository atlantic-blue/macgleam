import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// Where a removal is allowed to put what it removed.
///
/// `HelperRemovalDestination.userTrash(userHome:)` carries a home directory the
/// REQUEST supplies, and until this slice no stage compared it against the home
/// of the connecting user. So a client past the identity check could name any
/// home at all and have root move a system file into a trash directory it
/// created there. The archive family gained a destination stage; the trash did
/// not, because that amendment moved the archive out of `remove` and left
/// `remove` as it was.
@Suite("Helper policy trash destination")
struct HelperPolicyTrashDestinationTests {

  /// Homes that are not the connecting user's. The last two are the trap: a
  /// containment check made on characters rather than on path components
  /// admits both, and both belong to somebody else.
  static let otherHomes: [String] = [
    "/",
    "/Users",
    "/Users/someone",
    "/var/root",
    "/Library",
    "/Users/julian2",
    "/Users/julianne",
  ]

  private func handshakenPolicy() async throws -> HelperConnectionPolicy {
    try makeHandshakenArchivePolicy(denylist: try await HelperFixture.verifiedDenylist())
  }

  @Test("the connecting user's own home is admitted, so the check is not vacuous")
  func theConnectingUsersOwnHomeIsAdmitted() async throws {
    let admission = try await handshakenPolicy().admit(
      HelperFixture.remove(
        HelperFixture.systemAllowedTarget,
        destination: .userTrash(userHome: HelperFixture.userHome)),
      from: HelperFixture.trustedClient)
    #expect(admission == .admitted)
  }

  @Test("a trash home that is not the connecting user's is refused", arguments: otherHomes)
  func aTrashHomeThatIsNotTheConnectingUsersIsRefused(home: String) async throws {
    let admission = try await handshakenPolicy().admit(
      HelperFixture.remove(
        HelperFixture.systemAllowedTarget,
        destination: .userTrash(userHome: AbsolutePath(normalising: home))),
      from: HelperFixture.trustedClient)
    #expect(
      admission == .refused(.destinationRejected),
      """
      \(home) is not the home of the client on this connection, so a removal \
      naming it is asking root to create a trash directory somewhere it \
      chose and move a system file into it
      """)
  }

  @Test("a home whose name merely extends the connecting user's is refused")
  func aHomeWhoseNameMerelyExtendsTheConnectingUsersIsRefused() async throws {
    let policy = try await handshakenPolicy()
    for home in ["/Users/julian2", "/Users/julianne", "/Users/julian.old"] {
      #expect(
        policy.admit(
          HelperFixture.remove(
            HelperFixture.systemAllowedTarget,
            destination: .userTrash(userHome: AbsolutePath(normalising: home))),
          from: HelperFixture.trustedClient) == .refused(.destinationRejected),
        """
        containment is a check on path components, never on characters: \
        "\(home)" begins with the connecting user's home and is somebody else's
        """)
    }
  }

  @Test("a permanent deletion has no destination to check and is still admitted")
  func aPermanentDeletionIsStillAdmitted() async throws {
    let admission = try await handshakenPolicy().admit(
      HelperFixture.remove(HelperFixture.systemAllowedTarget, destination: .permanent),
      from: HelperFixture.trustedClient)
    #expect(admission == .admitted)
  }

  // MARK: The refusal sits where the contract puts it

  @Test("identity is checked before the trash home")
  func identityIsCheckedBeforeTheTrashHome() async throws {
    let admission = try await handshakenPolicy().admit(
      HelperFixture.remove(
        HelperFixture.systemAllowedTarget,
        destination: .userTrash(userHome: AbsolutePath(normalising: "/var/root"))),
      from: HelperFixture.client(bundleIdentifier: "com.example.intruder"))
    #expect(admission == .refused(.identityRejected))
  }

  @Test("the handshake is checked before the trash home")
  func theHandshakeIsCheckedBeforeTheTrashHome() async throws {
    let policy = makeArchivePolicy(
      denylist: try await HelperFixture.verifiedDenylist(), contractVersion: 7)
    let admission = policy.admit(
      HelperFixture.remove(
        HelperFixture.systemAllowedTarget,
        destination: .userTrash(userHome: AbsolutePath(normalising: "/var/root"))),
      from: HelperFixture.trustedClient)
    #expect(admission == .refused(.versionMismatch))
  }

  @Test("the denylist is checked before the trash home")
  func theDenylistIsCheckedBeforeTheTrashHome() async throws {
    let admission = try await handshakenPolicy().admit(
      HelperFixture.remove(
        HelperFixture.systemDenylistedTarget,
        destination: .userTrash(userHome: AbsolutePath(normalising: "/var/root"))),
      from: HelperFixture.trustedClient)
    #expect(
      admission == .refused(.denylisted),
      "the target is blocked outright, so the helper answers about the target")
  }

  @Test("a user domain target is refused on the domain before the trash home")
  func aUserDomainTargetIsRefusedOnTheDomain() async throws {
    let admission = try await handshakenPolicy().admit(
      HelperFixture.remove(
        HelperFixture.userAllowedTarget,
        destination: .userTrash(userHome: AbsolutePath(normalising: "/var/root"))),
      from: HelperFixture.trustedClient)
    #expect(admission == .refused(.notSystemDomain))
  }
}
