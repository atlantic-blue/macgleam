import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// Where the destination stage sits in C31's evaluation order. The contract
/// states the stages in sequence: identity, handshake, domain, denylist,
/// destination, provenance, and only then the operation. This file pins the
/// position of the new one the way the existing suite pins the others, by
/// building a request that would fail at several stages at once and asserting
/// the first refusal in the contract's order is the one that comes back.
///
/// The order is not decoration. A refusal naming a later stage tells whoever
/// holds the connection what the helper knows about something it should never
/// have looked at, and a destination stage running before the denylist would
/// answer questions about a user's home to a caller whose target was blocked
/// outright.
@Suite("Helper policy destination in the evaluation order")
struct HelperPolicyDestinationOrderTests {

  /// A destination the stage refuses on its own: a launch daemon directory,
  /// outside the connecting user's home and not on any denylist.
  static let rejectedDestination = ArchiveFixture.path(
    "/Library/LaunchDaemons/\(ArchiveFixture.itemID.uuidString)")

  private var intruder: ClientIdentity {
    HelperFixture.client(bundleIdentifier: "com.example.intruder")
  }

  /// A connection that never completed a handshake, so the handshake stage
  /// refuses anything the identity stage lets through.
  private func unhandshakenPolicy() async throws -> HelperConnectionPolicy {
    makeArchivePolicy(denylist: try await HelperFixture.verifiedDenylist(), contractVersion: 7)
  }

  /// A connection whose handshake claimed a version the helper does not speak.
  private func mismatchedPolicy() async throws -> HelperConnectionPolicy {
    let policy = makeArchivePolicy(
      denylist: try await HelperFixture.verifiedDenylist(), contractVersion: 7)
    try #require(
      policy.admit(HelperFixture.handshake(version: 3), from: HelperFixture.trustedClient)
        == .refused(.versionMismatch))
    return policy
  }

  private func handshakenPolicy() async throws -> HelperConnectionPolicy {
    try makeHandshakenArchivePolicy(denylist: try await HelperFixture.verifiedDenylist())
  }

  // MARK: Identity, first of all

  @Test(
    "identity is checked before the destination: an intruder's bad destination refuses on identity")
  func identityIsCheckedBeforeTheDestination() async throws {
    let admission = try await handshakenPolicy().admit(
      ArchiveFixture.archive(to: Self.rejectedDestination), from: intruder)
    #expect(admission == .refused(.identityRejected))
  }

  // MARK: The handshake, before everything after it

  @Test("the handshake is checked before the destination: a silent client refuses on version")
  func handshakeIsCheckedBeforeTheDestination() async throws {
    let admission = try await unhandshakenPolicy().admit(
      ArchiveFixture.archive(to: Self.rejectedDestination), from: HelperFixture.trustedClient)
    #expect(
      admission == .refused(.versionMismatch),
      "no version has been agreed, so the helper does not reach the request's contents at all")
  }

  @Test("a stale app's bad destination refuses on version rather than on the destination")
  func staleAppsBadDestinationRefusesOnVersion() async throws {
    let admission = try await mismatchedPolicy().admit(
      ArchiveFixture.archive(to: Self.rejectedDestination), from: HelperFixture.trustedClient)
    #expect(admission == .refused(.versionMismatch))
  }

  // MARK: The denylist, before the destination

  @Test("the denylist is checked before the destination: a blocked target refuses denylisted")
  func denylistIsCheckedBeforeTheDestination() async throws {
    let admission = try await handshakenPolicy().admit(
      ArchiveFixture.archive(
        target: HelperFixture.systemDenylistedTarget, to: Self.rejectedDestination),
      from: HelperFixture.trustedClient)
    #expect(
      admission == .refused(.denylisted),
      """
      the target is blocked outright, so the helper answers about the target \
      and never about a destination it had no business examining
      """)
  }

  @Test("a blocked target refuses denylisted even when the destination is the legitimate one")
  func blockedTargetRefusesEvenWithALegitimateDestination() async throws {
    let admission = try await handshakenPolicy().admit(
      ArchiveFixture.archive(
        target: HelperFixture.systemDenylistedTarget, to: ArchiveFixture.legitimatePayload),
      from: HelperFixture.trustedClient)
    #expect(
      admission == .refused(.denylisted),
      "a well formed destination is not a way past the denylist on the target")
  }

  // MARK: The ladder, one stage at a time

  @Test("a request failing every stage at once refuses on identity, the first one")
  func requestFailingEveryStageRefusesOnIdentity() async throws {
    let policy = try await unhandshakenPolicy()
    _ = policy.admit(HelperFixture.handshake(version: 3), from: intruder)
    let admission = policy.admit(
      ArchiveFixture.archive(
        target: HelperFixture.systemDenylistedTarget, to: Self.rejectedDestination),
      from: intruder)
    #expect(admission == .refused(.identityRejected))
  }

  @Test("with identity satisfied, a request failing the rest refuses on the handshake")
  func withIdentitySatisfiedTheHandshakeAnswersNext() async throws {
    let admission = try await mismatchedPolicy().admit(
      ArchiveFixture.archive(
        target: HelperFixture.systemDenylistedTarget, to: Self.rejectedDestination),
      from: HelperFixture.trustedClient)
    #expect(admission == .refused(.versionMismatch))
  }

  @Test("with identity and the handshake satisfied, the denylist answers next")
  func withIdentityAndHandshakeSatisfiedTheDenylistAnswersNext() async throws {
    let admission = try await handshakenPolicy().admit(
      ArchiveFixture.archive(
        target: HelperFixture.systemDenylistedTarget, to: Self.rejectedDestination),
      from: HelperFixture.trustedClient)
    #expect(admission == .refused(.denylisted))
  }

  @Test("with the target beyond reproach, the destination answers last")
  func withTheTargetBeyondReproachTheDestinationAnswersLast() async throws {
    let admission = try await handshakenPolicy().admit(
      ArchiveFixture.archive(
        target: HelperFixture.systemAllowedTarget, to: Self.rejectedDestination),
      from: HelperFixture.trustedClient)
    #expect(admission == .refused(.destinationRejected))
  }

  @Test("only a request that satisfies the destination stage too is admitted")
  func onlyARequestSatisfyingTheDestinationStageIsAdmitted() async throws {
    let admission = try await handshakenPolicy().admit(
      ArchiveFixture.archive(
        target: HelperFixture.systemAllowedTarget, to: ArchiveFixture.legitimatePayload),
      from: HelperFixture.trustedClient)
    #expect(admission == .admitted)
  }

  // MARK: The whole family climbs the same ladder

  @Test("every request in the archive family answers the same stage first")
  func everyRequestInTheFamilyAnswersTheSameStageFirst() async throws {
    let handshaken = try await handshakenPolicy()
    for request in ArchiveFixture.wholeFamily(naming: Self.rejectedDestination) {
      #expect(handshaken.admit(request, from: intruder) == .refused(.identityRejected))
    }
    let unhandshaken = try await unhandshakenPolicy()
    for request in ArchiveFixture.wholeFamily(naming: Self.rejectedDestination) {
      #expect(
        unhandshaken.admit(request, from: HelperFixture.trustedClient)
          == .refused(.versionMismatch))
    }
  }
}
