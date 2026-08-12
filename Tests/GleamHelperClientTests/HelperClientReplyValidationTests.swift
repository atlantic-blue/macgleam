import Foundation
import GleamCore
import GleamHelperClient
import GleamHelperCore
import Testing

/// C17: "helper replies are validated against C30 before being trusted; a
/// malformed reply fails that operation, never the process."
///
/// The helper is the more privileged process, so the app cannot verify it the
/// way the helper verifies the app. What the app can do is refuse to act on a
/// reply that does not answer the question it asked. Every test here sends one
/// operation and answers it with something the app must not take at face
/// value: a reply about a different operation, a reply of the wrong kind,
/// bytes that are not a message at all.
@Suite("The helper client does not trust what comes back")
struct HelperClientReplyValidationTests {

  // MARK: Replies the app can act on

  @Test("a success naming the operation completes it with the bytes the helper reclaimed")
  func successNamingTheOperationCompletesIt() async throws {
    let operation = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let transport = RecordingHelperTransport(
      script: [.message(.success(correlationID: operation.id, bytesReclaimed: 4096))])
    let client = makeApprovedHelperClient(transport: transport)

    let result = await client.perform(operation, planID: UUID())

    #expect(result == .completed(bytesReclaimed: 4096))
  }

  @Test("a launch item change naming the operation completes it, reclaiming nothing")
  func launchItemChangeNamingTheOperationCompletesIt() async throws {
    let operation = HelperClientFixture.launchItem()
    let change = LaunchItemChange(
      item: HelperClientFixture.systemLaunchItem,
      previousEnabled: true,
      newEnabled: false,
      changedAt: HelperClientFixture.executionInstant
    )
    let transport = RecordingHelperTransport(
      script: [.message(.launchItemChanged(correlationID: operation.id, change: change))])
    let client = makeApprovedHelperClient(transport: transport)

    let result = await client.perform(operation, planID: UUID())

    #expect(result == .completed(bytesReclaimed: 0))
  }

  @Test("a refusal on the denylist is reported as skipped by the denylist, not as a failure")
  func denylistRefusalIsReportedAsSkipped() async throws {
    let operation = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let transport = RecordingHelperTransport(
      script: [.message(.refused(correlationID: operation.id, reason: .denylisted))])
    let client = makeApprovedHelperClient(transport: transport)

    let result = await client.perform(operation, planID: UUID())

    #expect(
      result == .skippedDenylisted,
      "the safety system working is not the run failing, whichever process enforced it")
  }

  @Test("a failure reply is reported with a sentence of its own")
  func failureReplyIsReportedPlainly() async throws {
    let operation = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let transport = RecordingHelperTransport(
      script: [
        .message(
          .failed(
            correlationID: operation.id,
            reason: "The file is on a read only volume, so nothing was removed."))
      ])
    let client = makeApprovedHelperClient(transport: transport)

    let result = await client.perform(operation, planID: UUID())

    try expectPlainSentence(failureReason(result))
  }

  // MARK: Replies the app must not act on

  @Test("a reply naming a different operation fails the operation that was asked about")
  func replyNamingADifferentOperationFailsThatOperation() async throws {
    let operation = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let transport = RecordingHelperTransport(
      script: [.message(.success(correlationID: UUID(), bytesReclaimed: 999))])
    let client = makeApprovedHelperClient(transport: transport)

    let result = await client.perform(operation, planID: UUID())

    try expectPlainSentence(failureReason(result))
    #expect(
      result != .completed(bytesReclaimed: 999),
      "an answer to a different question is not an answer")
  }

  @Test("a refusal naming a different operation is not trusted either")
  func refusalNamingADifferentOperationIsNotTrusted() async throws {
    let operation = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let transport = RecordingHelperTransport(
      script: [.message(.refused(correlationID: UUID(), reason: .denylisted))])
    let client = makeApprovedHelperClient(transport: transport)

    let result = await client.perform(operation, planID: UUID())

    #expect(result != .skippedDenylisted)
    try expectPlainSentence(failureReason(result))
  }

  @Test("a refusal naming no operation at all fails the operation")
  func refusalNamingNoOperationFailsTheOperation() async throws {
    let operation = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let transport = RecordingHelperTransport(
      script: [.message(.refused(correlationID: nil, reason: .malformedRequest))])
    let client = makeApprovedHelperClient(transport: transport)

    let result = await client.perform(operation, planID: UUID())

    try expectPlainSentence(failureReason(result))
  }

  @Test(
    "a refusal that is not the denylist fails the operation in a plain sentence",
    arguments: [
      HelperRefusal.notSystemDomain,
      HelperRefusal.versionMismatch,
      HelperRefusal.identityRejected,
      HelperRefusal.malformedRequest,
    ]
  )
  func otherRefusalsFailTheOperation(reason: HelperRefusal) async throws {
    let operation = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let transport = RecordingHelperTransport(
      script: [.message(.refused(correlationID: operation.id, reason: reason))])
    let client = makeApprovedHelperClient(transport: transport)

    let result = await client.perform(operation, planID: UUID())

    try expectPlainSentence(failureReason(result))
    #expect(result != .skippedDenylisted)
  }

  @Test("a handshake reply answering a removal is the wrong kind of reply and fails it")
  func handshakeReplyAnsweringARemovalFailsIt() async throws {
    let operation = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let transport = RecordingHelperTransport(
      script: [.message(.handshakeAccepted(contractVersion: HelperContract.version))])
    let client = makeApprovedHelperClient(transport: transport)

    let result = await client.perform(operation, planID: UUID())

    try expectPlainSentence(failureReason(result))
  }

  @Test("a launch item reply answering a removal is the wrong kind of reply and fails it")
  func launchItemReplyAnsweringARemovalFailsIt() async throws {
    let operation = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let change = LaunchItemChange(
      item: HelperClientFixture.systemLaunchItem,
      previousEnabled: true,
      newEnabled: false,
      changedAt: HelperClientFixture.executionInstant
    )
    let transport = RecordingHelperTransport(
      script: [.message(.launchItemChanged(correlationID: operation.id, change: change))])
    let client = makeApprovedHelperClient(transport: transport)

    let result = await client.perform(operation, planID: UUID())

    try expectPlainSentence(failureReason(result))
  }

  @Test("a success answering a launch item change is the wrong kind of reply and fails it")
  func successAnsweringALaunchItemChangeFailsIt() async throws {
    let operation = HelperClientFixture.launchItem()
    let transport = RecordingHelperTransport(
      script: [.message(.success(correlationID: operation.id, bytesReclaimed: 0))])
    let client = makeApprovedHelperClient(transport: transport)

    let result = await client.perform(operation, planID: UUID())

    try expectPlainSentence(failureReason(result))
  }

  @Test("bytes that are not a message at all fail the operation rather than the process")
  func undecodablePayloadFailsTheOperation() async throws {
    let operation = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let transport = RecordingHelperTransport(
      script: [.rawPayload(Data([0xFF, 0x00, 0xFE, 0x01, 0x02]))])
    let client = makeApprovedHelperClient(transport: transport)

    let result = await client.perform(operation, planID: UUID())

    try expectPlainSentence(failureReason(result))
  }

  @Test("valid text that is not a contract message fails the operation")
  func validJsonThatIsNotAContractMessageFailsTheOperation() async throws {
    let operation = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let transport = RecordingHelperTransport(
      script: [
        .rawPayload(Data(#"{"deleteEverything":{"operationID":"whatever"}}"#.utf8))
      ])
    let client = makeApprovedHelperClient(transport: transport)

    let result = await client.perform(operation, planID: UUID())

    try expectPlainSentence(failureReason(result))
  }

  @Test("a truncated message fails the operation")
  func truncatedMessageFailsTheOperation() async throws {
    let operation = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let transport = RecordingHelperTransport(script: [.rawPayload(Data(#"{"success":{"#.utf8))])
    let client = makeApprovedHelperClient(transport: transport)

    let result = await client.perform(operation, planID: UUID())

    try expectPlainSentence(failureReason(result))
  }

  @Test("an empty reply fails the operation")
  func emptyReplyFailsTheOperation() async throws {
    let operation = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let transport = RecordingHelperTransport(script: [.rawPayload(Data())])
    let client = makeApprovedHelperClient(transport: transport)

    let result = await client.perform(operation, planID: UUID())

    try expectPlainSentence(failureReason(result))
  }

  @Test("a connection that fails mid request fails the operation in a plain sentence")
  func transportFailureFailsTheOperation() async throws {
    let operation = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let transport = RecordingHelperTransport(script: [.transportFailure])
    let client = makeApprovedHelperClient(transport: transport)

    let result = await client.perform(operation, planID: UUID())

    try expectPlainSentence(failureReason(result))
  }

  // MARK: One bad reply is not a broken client

  @Test("the client keeps serving after a malformed reply")
  func clientKeepsServingAfterAMalformedReply() async throws {
    let doomed = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let next = HelperClientFixture.trash(HelperClientFixture.otherSystemTarget)
    let transport = RecordingHelperTransport(
      script: [
        .rawPayload(Data([0xFF, 0xFF])),
        .message(.success(correlationID: next.id, bytesReclaimed: 512)),
      ])
    let client = makeApprovedHelperClient(transport: transport)

    let first = await client.perform(doomed, planID: UUID())
    let second = await client.perform(next, planID: UUID())

    try expectPlainSentence(failureReason(first))
    #expect(second == .completed(bytesReclaimed: 512))
    #expect(transport.overranScript == false)
  }

  // MARK: Which side is behind

  @Test("a helper that agrees on the version is recorded as agreed")
  func agreedVersionIsRecorded() async throws {
    let operation = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let transport = RecordingHelperTransport(succeedingWith: 0)
    let client = makeApprovedHelperClient(transport: transport)

    _ = await client.perform(operation, planID: UUID())

    #expect(await client.versionVerdict == .agreed(version: HelperContract.version))
  }

  @Test("a helper behind the app is named as the side that is behind")
  func helperBehindTheAppIsNamed() async throws {
    let transport = RecordingHelperTransport(
      handshake: .handshakeRefused(helperContractVersion: 3, clientContractVersion: 7))
    let client = makeApprovedHelperClient(transport: transport, contractVersion: 7)

    _ = await client.perform(
      HelperClientFixture.trash(HelperClientFixture.systemTarget), planID: UUID())

    #expect(await client.versionVerdict == .helperIsBehind(helperVersion: 3, appVersion: 7))
  }

  @Test("an app behind the helper is named as the side that is behind")
  func appBehindTheHelperIsNamed() async throws {
    let transport = RecordingHelperTransport(
      handshake: .handshakeRefused(helperContractVersion: 7, clientContractVersion: 3))
    let client = makeApprovedHelperClient(transport: transport, contractVersion: 3)

    _ = await client.perform(
      HelperClientFixture.trash(HelperClientFixture.systemTarget), planID: UUID())

    #expect(await client.versionVerdict == .appIsBehind(helperVersion: 7, appVersion: 3))
  }

  @Test("an operation is never transmitted to a helper that refused the handshake")
  func operationIsNeverTransmittedAfterARefusedHandshake() async throws {
    let transport = RecordingHelperTransport(
      handshake: .handshakeRefused(helperContractVersion: 3, clientContractVersion: 7))
    let client = makeApprovedHelperClient(transport: transport, contractVersion: 7)

    let result = await client.perform(
      HelperClientFixture.trash(HelperClientFixture.systemTarget), planID: UUID())

    try expectPlainSentence(failureReason(result))
    #expect(try transport.sentOperationRequests().isEmpty)
  }

  @Test("a helper that refused the handshake is not asked again on the same connection")
  func refusedHandshakeIsNotRetried() async throws {
    let transport = RecordingHelperTransport(
      handshake: .handshakeRefused(helperContractVersion: 3, clientContractVersion: 7))
    let client = makeApprovedHelperClient(transport: transport, contractVersion: 7)

    _ = await client.perform(
      HelperClientFixture.trash(HelperClientFixture.systemTarget), planID: UUID())
    _ = await client.perform(
      HelperClientFixture.trash(HelperClientFixture.otherSystemTarget), planID: UUID())

    #expect(
      transport.handshakeCount == 1, "a stale app must not retry its way into a refused connection")
    #expect(try transport.sentOperationRequests().isEmpty)
  }
}
