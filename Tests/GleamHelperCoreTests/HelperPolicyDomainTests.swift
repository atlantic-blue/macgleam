import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// C31 stage three: the helper exists only for what genuinely needs root. A
/// user domain target is refused notSystemDomain, because the user process
/// could have done that work itself.
@Suite("Helper policy path domain")
struct HelperPolicyDomainTests {

  static let userDomainTargets = [
    "/Users/julian/Library/Caches/com.example.helper",
    "/Users/julian",
    "/Users/julian/.Trash/something.log",
    "/Volumes/External/Scratch/build",
    "/tmp/gleam-scratch",
  ]

  static let systemDomainTargets = [
    "/Library/Caches/com.example.helper",
    "/Library",
    "/Applications/Example.app",
  ]

  @Test("a system domain remove passes the domain check", arguments: systemDomainTargets)
  func systemDomainRemovePassesTheDomainCheck(target: String) async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.path(target)), from: HelperFixture.trustedClient)
    #expect(admission == .admitted)
  }

  @Test("a user domain remove is refused notSystemDomain", arguments: userDomainTargets)
  func userDomainRemoveIsRefused(target: String) async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.path(target)), from: HelperFixture.trustedClient)
    #expect(admission == .refused(.notSystemDomain))
  }

  @Test("a system scope launch item change passes the domain check")
  func systemScopeLaunchItemPassesTheDomainCheck() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem),
      from: HelperFixture.trustedClient)
    #expect(admission == .admitted)
  }

  @Test("a user scope launch item change is refused notSystemDomain")
  func userScopeLaunchItemIsRefused() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.setLaunchItemEnabled(HelperFixture.userLaunchItem),
      from: HelperFixture.trustedClient)
    #expect(admission == .refused(.notSystemDomain))
  }

  @Test("a launch item the helper cannot resolve for itself is refused malformedRequest")
  func unresolvableLaunchItemIsRefused() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let admission = policy.admit(
      HelperFixture.setLaunchItemEnabled(HelperFixture.unresolvableLaunchItem),
      from: HelperFixture.trustedClient)
    #expect(admission == .refused(.malformedRequest))
  }

  @Test("every maintenance task is admitted, having no target to place in a domain")
  func everyMaintenanceTaskIsAdmitted() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    for task in MaintenanceTask.allCases {
      #expect(
        policy.admit(HelperFixture.runMaintenance(task), from: HelperFixture.trustedClient)
          == .admitted)
    }
  }

  @Test("the removal destination does not change the domain answer")
  func removalDestinationDoesNotChangeTheDomainAnswer() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let destinations: [HelperRemovalDestination] = [
      .permanent,
      .userTrash(userHome: HelperFixture.userHome),
    ]
    for destination in destinations {
      #expect(
        policy.admit(
          HelperFixture.remove(HelperFixture.systemAllowedTarget, destination: destination),
          from: HelperFixture.trustedClient) == .admitted)
      #expect(
        policy.admit(
          HelperFixture.remove(HelperFixture.userAllowedTarget, destination: destination),
          from: HelperFixture.trustedClient) == .refused(.notSystemDomain))
    }
  }

  @Test("the domain answer comes from the helper's own ownership policy, not from the request")
  func domainAnswerComesFromTheHelpersOwnPolicy() async throws {
    let policy = try makeHandshakenPolicy(
      denylist: try await HelperFixture.verifiedDenylist(),
      ownership: HelperEverythingUserDomainPolicy())
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.systemAllowedTarget), from: HelperFixture.trustedClient)
    #expect(admission == .refused(.notSystemDomain))
  }
}

/// An ownership policy that places every path in the user domain, so a test
/// can prove the helper asks its own policy rather than inferring a domain
/// from the shape of the path in the request.
struct HelperEverythingUserDomainPolicy: PathOwnershipPolicy {
  func ownership(of path: AbsolutePath, environment: OwnershipEnvironment) -> PathOwnership {
    .userDomain
  }
}
