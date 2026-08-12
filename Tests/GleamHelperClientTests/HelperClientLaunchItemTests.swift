import Foundation
import GleamCore
import GleamHelperClient
import GleamHelperCore
import Testing

/// The app's privileged launch item path: C24's `PrivilegedLaunchItemChanging`
/// carried over C30 version two.
///
/// Before version two there was no way to send a change somebody made in the
/// interface, because the request could only name a plan. These cover the path
/// that exists now, including the part that matters most: what crosses is the
/// attribution the caller gave, and what comes back is checked against it
/// before a word of it is believed.
@Suite("Helper client launch item changes")
struct HelperClientLaunchItemTests {

  private static let item = HelperClientFixture.systemLaunchItem
  private static let changeID = UUID()
  private static let direct = ChangeAttribution.directChange(changeID: changeID)

  private func changed(
    _ correlationID: UUID,
    enabled: Bool = false
  ) -> ScriptedHelperReply {
    .message(
      .launchItemChanged(
        correlationID: correlationID,
        change: LaunchItemChange(
          item: Self.item,
          previousEnabled: !enabled,
          newEnabled: enabled,
          changedAt: HelperClientFixture.executionInstant
        )
      )
    )
  }

  @Test("a change made in the interface crosses carrying its own identifier")
  func aDirectChangeCrossesCarryingItsOwnIdentifier() async throws {
    let transport = RecordingHelperTransport(script: [changed(Self.changeID)])
    let client = makeApprovedHelperClient(transport: transport)

    _ = try await client.setLaunchItemEnabled(false, item: Self.item, attribution: Self.direct)

    let request = try #require(try transport.sentOperationRequests().first)
    #expect(
      request
        == .setLaunchItemEnabled(item: Self.item, enabled: false, attribution: Self.direct))
    #expect(request.planID == nil)
    #expect(request.correlationID == Self.changeID)
  }

  @Test("a planned change crosses naming its plan and its operation")
  func aPlannedChangeCrossesNamingItsPlanAndOperation() async throws {
    let planID = UUID()
    let operationID = UUID()
    let attribution = ChangeAttribution.operation(planID: planID, operationID: operationID)
    let transport = RecordingHelperTransport(script: [changed(operationID)])
    let client = makeApprovedHelperClient(transport: transport)

    _ = try await client.setLaunchItemEnabled(true, item: Self.item, attribution: attribution)

    let request = try #require(try transport.sentOperationRequests().first)
    #expect(request.planID == planID)
    #expect(request.correlationID == operationID)
  }

  @Test("the change the helper reported is the change that comes back")
  func theChangeTheHelperReportedComesBack() async throws {
    let transport = RecordingHelperTransport(script: [changed(Self.changeID, enabled: true)])
    let client = makeApprovedHelperClient(transport: transport)

    let change = try await client.setLaunchItemEnabled(
      true, item: Self.item, attribution: Self.direct)

    #expect(change.item == Self.item)
    #expect(change.newEnabled)
    #expect(change.changedAt == HelperClientFixture.executionInstant)
  }

  @Test("a reply about another change is refused rather than believed")
  func aReplyAboutAnotherChangeIsRefused() async throws {
    let transport = RecordingHelperTransport(script: [changed(UUID())])
    let client = makeApprovedHelperClient(transport: transport)

    await #expect(throws: PrivilegedLaunchItemFailure.self) {
      _ = try await client.setLaunchItemEnabled(
        false, item: Self.item, attribution: Self.direct)
    }
  }

  @Test("a reply of the wrong kind is refused rather than read as a change")
  func aReplyOfTheWrongKindIsRefused() async throws {
    let transport = RecordingHelperTransport(
      script: [.message(.success(correlationID: Self.changeID, bytesReclaimed: 0))])
    let client = makeApprovedHelperClient(transport: transport)

    await #expect(throws: PrivilegedLaunchItemFailure.self) {
      _ = try await client.setLaunchItemEnabled(
        false, item: Self.item, attribution: Self.direct)
    }
  }

  @Test("an item the helper cannot resolve is reported as the item being gone")
  func anUnresolvableItemIsReportedAsGone() async throws {
    let transport = RecordingHelperTransport(
      script: [.message(.refused(correlationID: Self.changeID, reason: .malformedRequest))])
    let client = makeApprovedHelperClient(transport: transport)

    await #expect(throws: PrivilegedLaunchItemFailure.itemUnresolvable) {
      _ = try await client.setLaunchItemEnabled(
        false, item: Self.item, attribution: Self.direct)
    }
  }

  @Test("a refusal that is not the item being gone arrives as a plain sentence")
  func aRefusalArrivesAsAPlainSentence() async throws {
    let transport = RecordingHelperTransport(
      script: [.message(.refused(correlationID: Self.changeID, reason: .denylisted))])
    let client = makeApprovedHelperClient(transport: transport)

    do {
      _ = try await client.setLaunchItemEnabled(
        false, item: Self.item, attribution: Self.direct)
      Issue.record("a denylisted item must not report a change")
    } catch let failure as PrivilegedLaunchItemFailure {
      guard case .refused(let reason) = failure else {
        Issue.record("a denylist refusal is not the item being gone")
        return
      }
      try expectPlainSentence(reason)
    }
  }

  @Test("the handshake goes first, so no change reaches an unagreed connection")
  func theHandshakeGoesFirst() async throws {
    let transport = RecordingHelperTransport(
      handshake: .handshakeRefused(helperContractVersion: 3, clientContractVersion: 2),
      script: [changed(Self.changeID)])
    let client = makeApprovedHelperClient(transport: transport)

    await #expect(throws: PrivilegedLaunchItemFailure.self) {
      _ = try await client.setLaunchItemEnabled(
        false, item: Self.item, attribution: Self.direct)
    }
    #expect(try transport.sentOperationRequests().isEmpty)
  }
}
