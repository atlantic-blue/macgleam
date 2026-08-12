import Foundation
import GleamCore
import GleamHelperClient
import GleamHelperCore
import Testing

/// The app's side of the SafetyNet archive family.
///
/// The store calls this, never the executor, and it is the store that chose
/// the payload path and minted the item identifier. So what these check is
/// that the request carries exactly what it was given, and that nothing that
/// comes back is believed until it names this item and is the kind of answer
/// this request has.
@Suite("Helper client SafetyNet archive")
struct HelperClientArchiveTests {

  private static let itemID = UUID()
  private static let origin = HelperClientFixture.systemTarget
  private static let storedPath = HelperClientFixture.path(
    "/Users/julian/Library/Application Support/MacGleam/SafetyNet/payloads/"
      + itemID.uuidString)

  private static let report = PrivilegedArchiveReport(
    originPath: origin,
    metadata: FileMetadataSnapshot(
      posixPermissions: 0o755,
      extendedAttributes: ["com.apple.quarantine": Data([0x09])],
      created: HelperClientFixture.executionInstant,
      modified: HelperClientFixture.executionInstant),
    allocatedBytes: 12_345)

  private func archived() -> ScriptedHelperReply {
    .message(.archived(correlationID: Self.itemID, report: Self.report))
  }

  // MARK: - What crosses

  @Test("an archive names the target, the payload path and the item, and nothing else")
  func anArchiveNamesTheTargetThePayloadPathAndTheItem() async throws {
    let transport = RecordingHelperTransport(script: [archived()])
    let client = makeApprovedHelperClient(transport: transport)

    _ = try await client.archive(Self.origin, to: Self.storedPath, itemID: Self.itemID)

    let request = try #require(try transport.sentOperationRequests().first)
    #expect(
      request
        == .archiveIntoSafetyNet(
          target: Self.origin, storedPath: Self.storedPath, itemID: Self.itemID))
  }

  @Test("the archive family belongs to no plan and echoes the item")
  func theArchiveFamilyBelongsToNoPlan() async throws {
    let transport = RecordingHelperTransport(script: [archived()])
    let client = makeApprovedHelperClient(transport: transport)

    _ = try await client.archive(Self.origin, to: Self.storedPath, itemID: Self.itemID)

    let request = try #require(try transport.sentOperationRequests().first)
    #expect(request.planID == nil)
    #expect(request.correlationID == Self.itemID)
  }

  @Test("a restore carries no origin and no metadata, because the request is the chosen part")
  func aRestoreCarriesNoOriginAndNoMetadata() async throws {
    let transport = RecordingHelperTransport(
      script: [.message(.restoredArchive(correlationID: Self.itemID, originPath: Self.origin))])
    let client = makeApprovedHelperClient(transport: transport)

    _ = try await client.restoreArchived(at: Self.storedPath, itemID: Self.itemID)

    let request = try #require(try transport.sentOperationRequests().first)
    #expect(request == .restoreArchived(storedPath: Self.storedPath, itemID: Self.itemID))
    #expect(!transport.transmitted(text: "posixPermissions"))
    #expect(!transport.transmitted(text: Self.origin.value))
  }

  @Test("a discard names the payload and the item")
  func aDiscardNamesThePayloadAndTheItem() async throws {
    let transport = RecordingHelperTransport(
      script: [.message(.discardedArchive(correlationID: Self.itemID))])
    let client = makeApprovedHelperClient(transport: transport)

    try await client.discardArchived(at: Self.storedPath, itemID: Self.itemID)

    let request = try #require(try transport.sentOperationRequests().first)
    #expect(request == .discardArchived(storedPath: Self.storedPath, itemID: Self.itemID))
  }

  // MARK: - What comes back

  @Test("the report is the one the helper sent, attribute for attribute")
  func theReportIsTheOneTheHelperSent() async throws {
    let transport = RecordingHelperTransport(script: [archived()])
    let client = makeApprovedHelperClient(transport: transport)

    let report = try await client.archive(
      Self.origin, to: Self.storedPath, itemID: Self.itemID)

    #expect(report == Self.report)
  }

  @Test("a description answers with the same report the archive did")
  func aDescriptionAnswersWithTheSameReport() async throws {
    let transport = RecordingHelperTransport(script: [archived(), archived()])
    let client = makeApprovedHelperClient(transport: transport)

    let made = try await client.archive(Self.origin, to: Self.storedPath, itemID: Self.itemID)
    let described = try await client.describeArchived(
      at: Self.storedPath, itemID: Self.itemID)

    #expect(made == described)
  }

  @Test("a restore answers with where the payload actually went")
  func aRestoreAnswersWithWhereThePayloadWent() async throws {
    let transport = RecordingHelperTransport(
      script: [.message(.restoredArchive(correlationID: Self.itemID, originPath: Self.origin))])
    let client = makeApprovedHelperClient(transport: transport)

    let landed = try await client.restoreArchived(at: Self.storedPath, itemID: Self.itemID)

    #expect(landed == Self.origin)
  }

  @Test("a reply about another item is refused rather than recorded")
  func aReplyAboutAnotherItemIsRefused() async throws {
    let transport = RecordingHelperTransport(
      script: [.message(.archived(correlationID: UUID(), report: Self.report))])
    let client = makeApprovedHelperClient(transport: transport)

    await #expect(throws: (any Error).self) {
      _ = try await client.archive(Self.origin, to: Self.storedPath, itemID: Self.itemID)
    }
  }

  @Test("a reply of the wrong kind is refused rather than read as an archive")
  func aReplyOfTheWrongKindIsRefused() async throws {
    let transport = RecordingHelperTransport(
      script: [.message(.success(correlationID: Self.itemID, bytesReclaimed: 10))])
    let client = makeApprovedHelperClient(transport: transport)

    await #expect(throws: (any Error).self) {
      _ = try await client.archive(Self.origin, to: Self.storedPath, itemID: Self.itemID)
    }
  }

  @Test("a refused destination throws rather than reporting an archive")
  func aRefusedDestinationThrows() async throws {
    let transport = RecordingHelperTransport(
      script: [.message(.refused(correlationID: Self.itemID, reason: .destinationRejected))])
    let client = makeApprovedHelperClient(transport: transport)

    await #expect(throws: (any Error).self) {
      _ = try await client.archive(Self.origin, to: Self.storedPath, itemID: Self.itemID)
    }
  }

  @Test("a discard the helper failed is a failure, not a silent success")
  func aDiscardTheHelperFailedIsAFailure() async throws {
    let transport = RecordingHelperTransport(
      script: [
        .message(.failed(correlationID: Self.itemID, reason: "The payload is not ours."))
      ])
    let client = makeApprovedHelperClient(transport: transport)

    await #expect(throws: (any Error).self) {
      try await client.discardArchived(at: Self.storedPath, itemID: Self.itemID)
    }
  }

  @Test("the handshake goes first, so no archive reaches an unagreed connection")
  func theHandshakeGoesFirst() async throws {
    let transport = RecordingHelperTransport(
      handshake: .handshakeRefused(
        helperContractVersion: HelperContract.version + 1,
        clientContractVersion: HelperContract.version),
      script: [archived()])
    let client = makeApprovedHelperClient(transport: transport)

    await #expect(throws: (any Error).self) {
      _ = try await client.archive(Self.origin, to: Self.storedPath, itemID: Self.itemID)
    }
    #expect(try transport.sentOperationRequests().isEmpty)
  }
}
