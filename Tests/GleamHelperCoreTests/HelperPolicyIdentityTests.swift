import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// C31 stage one: the connection's audit token must satisfy the code signing
/// requirement, exact team identifier and exact bundle identifier. Anything
/// else is refused identityRejected.
@Suite("Helper policy client identity")
struct HelperPolicyIdentityTests {

  static let wrongTeamIdentifiers = [
    "ZZ99YY88XX",
    "testteam01",
    "TESTTEAM0",
    "TESTTEAM011",
    " TESTTEAM01",
    "",
  ]

  static let wrongBundleIdentifiers = [
    "com.atlanticblue.macgleam.evil",
    "com.atlanticblue.macglea",
    "COM.ATLANTICBLUE.MACGLEAM",
    "com.example.macgleam",
    "",
  ]

  @Test("the exact expected identity is admitted")
  func exactExpectedIdentityIsAdmitted() async throws {
    let policy = makeHelperPolicy(denylist: try await HelperFixture.verifiedDenylist())
    #expect(policy.admit(HelperFixture.handshake(), from: HelperFixture.trustedClient) == .admitted)
  }

  @Test("a different team identifier is refused", arguments: wrongTeamIdentifiers)
  func differentTeamIdentifierIsRefused(teamIdentifier: String) async throws {
    let policy = makeHelperPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let client = HelperFixture.client(teamIdentifier: teamIdentifier)
    #expect(policy.admit(HelperFixture.handshake(), from: client) == .refused(.identityRejected))
  }

  @Test("a different bundle identifier is refused", arguments: wrongBundleIdentifiers)
  func differentBundleIdentifierIsRefused(bundleIdentifier: String) async throws {
    let policy = makeHelperPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let client = HelperFixture.client(bundleIdentifier: bundleIdentifier)
    #expect(policy.admit(HelperFixture.handshake(), from: client) == .refused(.identityRejected))
  }

  @Test("an identity whose code signature did not verify is refused")
  func identityWhoseCodeSignatureDidNotVerifyIsRefused() async throws {
    let policy = makeHelperPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let client = HelperFixture.client(codeSigningValid: false)
    #expect(policy.admit(HelperFixture.handshake(), from: client) == .refused(.identityRejected))
  }

  @Test("an absent identity is refused")
  func absentIdentityIsRefused() async throws {
    let policy = makeHelperPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let client = ClientIdentity(
      teamIdentifier: "", bundleIdentifier: "", codeSigningValid: false)
    #expect(policy.admit(HelperFixture.handshake(), from: client) == .refused(.identityRejected))
  }

  @Test("every request kind is refused to an untrusted identity")
  func everyRequestKindIsRefusedToAnUntrustedIdentity() async throws {
    let policy = try makeHandshakenPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let intruder = HelperFixture.client(bundleIdentifier: "com.example.intruder")
    let requests = [
      HelperFixture.handshake(),
      HelperFixture.remove(HelperFixture.systemAllowedTarget),
      HelperFixture.setLaunchItemEnabled(HelperFixture.systemLaunchItem),
      HelperFixture.runMaintenance(),
    ]
    for request in requests {
      #expect(policy.admit(request, from: intruder) == .refused(.identityRejected))
    }
  }

  @Test("an untrusted identity cannot complete the handshake for a later trusted request")
  func untrustedIdentityCannotCompleteTheHandshake() async throws {
    let policy = makeHelperPolicy(denylist: try await HelperFixture.verifiedDenylist())
    let intruder = HelperFixture.client(teamIdentifier: "ZZ99YY88XX")
    #expect(policy.admit(HelperFixture.handshake(), from: intruder) == .refused(.identityRejected))
    let admission = policy.admit(
      HelperFixture.remove(HelperFixture.systemAllowedTarget), from: HelperFixture.trustedClient)
    #expect(
      admission == .refused(.versionMismatch),
      "a handshake refused on identity must not leave the connection handshaken")
  }

  @Test("a handshake refused on identity records no version disagreement to report")
  func handshakeRefusedOnIdentityRecordsNoDisagreement() async throws {
    let policy = makeHelperPolicy(
      denylist: try await HelperFixture.verifiedDenylist(), contractVersion: 7)
    _ = policy.admit(HelperFixture.handshake(version: 3), from: HelperFixture.intruderClient)
    #expect(
      policy.versionMismatch == nil,
      "the helper never looked at the version, so it has nothing to tell an unverified client")
  }

  @Test("the expected identity is MacGleam.app's own bundle identifier")
  func expectedIdentityIsMacGleamsOwnBundleIdentifier() {
    #expect(ExpectedClientIdentity.macGleamApp.bundleIdentifier == "com.atlanticblue.macgleam")
    #expect(ExpectedClientIdentity.macGleamApp.teamIdentifier.isEmpty == false)
  }

  @Test("a policy built for the shipping identity refuses this file's test identity")
  func shippingIdentityRefusesTheTestIdentity() async throws {
    let policy = makeHelperPolicy(
      denylist: try await HelperFixture.verifiedDenylist(),
      expectedClient: .macGleamApp)
    #expect(
      policy.admit(HelperFixture.handshake(), from: HelperFixture.trustedClient)
        == .refused(.identityRejected))
  }
}
