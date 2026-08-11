import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// What a destination refusal says, and what it must not say.
///
/// C30 gives the destination stage a refusal of its own so the store can tell
/// a path it may not write to from a target it may not touch, and so the app's
/// report reconciles. The same contract says a refusal names no version,
/// because a client the helper could not verify is told nothing about the
/// helper. This file holds both ends of that: the refusal is specific enough
/// to act on, and it is the same answer whatever the destination was, for
/// anybody the helper has not verified.
@Suite("Helper policy destination refusal")
struct HelperPolicyDestinationRefusalTests {

  /// One destination of each kind the stage refuses, so a disclosure test
  /// sweeps the whole shape of the check rather than one string.
  static let destinations: [AbsolutePath] = [
    ArchiveFixture.legitimatePayload,
    ArchiveFixture.path("/Library/LaunchDaemons/\(ArchiveFixture.itemID.uuidString)"),
    ArchiveFixture.path(
      "/Users/julianne/Library/Application Support/MacGleam/SafetyNet/payloads/"
        + ArchiveFixture.itemID.uuidString),
    ArchiveFixture.path("/Users/julian/Blocked/payloads/\(ArchiveFixture.itemID.uuidString)"),
    ArchiveFixture.payloadsDirectory,
  ]

  static let refusedDestination = ArchiveFixture.path(
    "/Library/LaunchDaemons/\(ArchiveFixture.itemID.uuidString)")

  static let everyOtherRefusal: [HelperRefusal] = [
    .denylisted, .notSystemDomain, .versionMismatch, .identityRejected, .malformedRequest,
  ]

  private func handshakenPolicy() async throws -> HelperConnectionPolicy {
    try makeHandshakenArchivePolicy(denylist: try await HelperFixture.verifiedDenylist())
  }

  // MARK: The refusal names which refusal it is

  @Test("a refused destination is refused destinationRejected and not something else")
  func aRefusedDestinationIsRefusedDestinationRejected() async throws {
    let admission = try await handshakenPolicy().admit(
      ArchiveFixture.archive(to: Self.refusedDestination), from: HelperFixture.trustedClient)
    #expect(admission == .refused(.destinationRejected))
    for other in Self.everyOtherRefusal {
      #expect(
        admission != .refused(other),
        """
        the store reads this to tell a path it may not write to from a target \
        it may not touch, so a destination refusal wearing another stage's \
        name is a wrong answer even though it refuses
        """)
    }
  }

  @Test("the destination refusal carries its own name on the wire")
  func theDestinationRefusalCarriesItsOwnNameOnTheWire() {
    #expect(HelperRefusal.destinationRejected.rawValue == "destinationRejected")
    for other in Self.everyOtherRefusal {
      #expect(HelperRefusal.destinationRejected.rawValue != other.rawValue)
    }
  }

  @Test("a destination refusal survives the wire naming the item it refused")
  func aDestinationRefusalSurvivesTheWireNamingTheItem() throws {
    let codec = HelperWireCodec()
    let reply = HelperResponse.refused(
      correlationID: ArchiveFixture.itemID, reason: .destinationRejected)
    let decoded = try codec.decodeResponse(from: codec.encode(reply))
    #expect(
      decoded == reply,
      """
      the archive family's correlation identifier is the item's (C30), so a \
      store whose archive was refused knows which of its items it was
      """)
  }

  // MARK: And tells an unverified client nothing else

  @Test("an unverified client gets the same answer whatever destination it names")
  func anUnverifiedClientGetsTheSameAnswerWhateverDestination() async throws {
    let policy = try await handshakenPolicy()
    let intruder = HelperFixture.client(bundleIdentifier: "com.example.intruder")
    let answers = Self.destinations.map { destination in
      policy.admit(ArchiveFixture.archive(to: destination), from: intruder)
    }
    #expect(
      answers.allSatisfy { $0 == .refused(.identityRejected) },
      """
      an answer that varied with the destination is an oracle: it would let an \
      unverified caller find the connecting user's home, and the store inside \
      it, one guess at a time
      """)
  }

  @Test("an unverified client gets the same answer across the whole archive family")
  func anUnverifiedClientGetsTheSameAnswerAcrossTheFamily() async throws {
    let policy = try await handshakenPolicy()
    let intruder = HelperFixture.client(bundleIdentifier: "com.example.intruder")
    for destination in Self.destinations {
      for request in ArchiveFixture.wholeFamily(naming: destination) {
        #expect(policy.admit(request, from: intruder) == .refused(.identityRejected))
      }
    }
  }

  @Test("an unverified client's destination probing leaves no version to report")
  func anUnverifiedClientsProbingLeavesNoVersionToReport() async throws {
    let policy = makeArchivePolicy(
      denylist: try await HelperFixture.verifiedDenylist(), contractVersion: 7)
    let intruder = HelperFixture.client(bundleIdentifier: "com.example.intruder")
    for destination in Self.destinations {
      _ = policy.admit(ArchiveFixture.archive(to: destination), from: intruder)
    }
    #expect(
      policy.versionMismatch == nil,
      "the helper never looked past identity, so it has nothing to tell an unverified client")
  }

  @Test("a client before the handshake gets the same answer whatever destination it names")
  func aClientBeforeTheHandshakeGetsTheSameAnswer() async throws {
    let policy = makeArchivePolicy(
      denylist: try await HelperFixture.verifiedDenylist(), contractVersion: 7)
    let answers = Self.destinations.map { destination in
      policy.admit(ArchiveFixture.archive(to: destination), from: HelperFixture.trustedClient)
    }
    #expect(answers.allSatisfy { $0 == .refused(.versionMismatch) })
  }

  // MARK: The reply itself carries no path and no version

  @Test("the destination refusal reply carries no path at all")
  func theDestinationRefusalReplyCarriesNoPath() throws {
    let encoded = try HelperWireCodec().encode(
      .refused(correlationID: ArchiveFixture.itemID, reason: .destinationRejected))
    let text = String(decoding: encoded, as: UTF8.self)
    for fragment in ["/Users", "julian", "SafetyNet", "payloads", "Library", "LaunchDaemons"] {
      #expect(
        text.contains(fragment) == false,
        """
        the refusal says the destination was rejected and never where the \
        helper would or would not have written, so it is not a map of the \
        machine for whoever asked
        """)
    }
  }

  @Test("the destination refusal reply names no version")
  func theDestinationRefusalReplyNamesNoVersion() throws {
    let encoded = try HelperWireCodec().encode(
      .refused(correlationID: ArchiveFixture.itemID, reason: .destinationRejected))
    let body = try helperWireBody(of: encoded)
    #expect(body["helperContractVersion"] == nil)
    #expect(body["clientContractVersion"] == nil)
    #expect(body["contractVersion"] == nil)
    #expect(
      Set(body.keys) == ["correlationID", "reason"],
      "the refusal carries what it refused and why, and nothing else")
  }
}
