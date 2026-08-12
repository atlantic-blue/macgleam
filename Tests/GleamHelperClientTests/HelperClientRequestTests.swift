import Foundation
import GleamCore
import GleamHelperClient
import GleamHelperCore
import Testing

/// What the app sends across the privileged boundary. C30 is a closed set, and
/// the app names the destination itself, so these pin the translation from an
/// operation the user reviewed to the one request that carries it.
@Suite("What the helper client transmits")
struct HelperClientRequestTests {

  @Test(
    "the first message on a connection is the handshake naming the version both processes compile against"
  )
  func firstMessageIsTheHandshake() async throws {
    let transport = RecordingHelperTransport(succeedingWith: 0)
    let client = makeApprovedHelperClient(transport: transport)

    _ = await client.perform(
      HelperClientFixture.trash(HelperClientFixture.systemTarget), planID: UUID())

    let requests = try transport.sentRequests()
    #expect(requests.first == .handshake(contractVersion: HelperContract.version))
  }

  @Test("a second operation reuses the handshake already agreed on that connection")
  func secondOperationReusesTheHandshake() async throws {
    let transport = RecordingHelperTransport(succeedingWith: 0)
    let client = makeApprovedHelperClient(transport: transport)
    let planID = UUID()

    _ = await client.perform(
      HelperClientFixture.trash(HelperClientFixture.systemTarget), planID: planID)
    _ = await client.perform(
      HelperClientFixture.trash(HelperClientFixture.otherSystemTarget), planID: planID)

    #expect(transport.handshakeCount == 1)
    #expect(try transport.sentOperationRequests().count == 2)
  }

  @Test("a system domain trash operation is transmitted as a removal into the user's own trash")
  func trashOperationBecomesARemovalIntoTheUserTrash() async throws {
    let transport = RecordingHelperTransport(succeedingWith: 4096)
    let client = makeApprovedHelperClient(transport: transport)
    let operation = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let planID = UUID()

    _ = await client.perform(operation, planID: planID)

    let request = try #require(try transport.sentOperationRequests().first)
    #expect(
      request
        == .remove(
          target: HelperClientFixture.systemTarget,
          destination: .userTrash(userHome: HelperClientFixture.userHome),
          planID: planID,
          operationID: operation.id))
  }

  @Test("a permanent delete is transmitted as a removal with nowhere to go back to")
  func permanentDeleteBecomesAPermanentRemoval() async throws {
    let transport = RecordingHelperTransport(succeedingWith: 10)
    let client = makeApprovedHelperClient(transport: transport)
    let operation = HelperClientFixture.permanent(HelperClientFixture.systemTarget)

    _ = await client.perform(operation, planID: UUID())

    let request = try #require(try transport.sentOperationRequests().first)
    #expect(request.removalDestination == .permanent)
    #expect(request.removalTarget == HelperClientFixture.systemTarget)
  }

  @Test("quarantine and archive are transmitted as a removal into the store the app named")
  func quarantineAndArchiveNameTheSafetyNetStore() async throws {
    for operation in [
      HelperClientFixture.quarantine(HelperClientFixture.systemTarget),
      HelperClientFixture.archive(HelperClientFixture.systemTarget),
    ] {
      let transport = RecordingHelperTransport(succeedingWith: 10)
      let client = makeApprovedHelperClient(transport: transport)

      _ = await client.perform(operation, planID: UUID())

      let request = try #require(try transport.sentOperationRequests().first)
      #expect(
        request.removalDestination
          == .safetyNetStore(storeDirectory: HelperClientFixture.safetyNetStore),
        "the helper never chooses where a file goes")
    }
  }

  @Test("a launch item change is transmitted naming the item, never a path")
  func launchItemChangeNamesTheItem() async throws {
    let transport = RecordingHelperTransport(succeedingWith: 0)
    let client = makeApprovedHelperClient(transport: transport)
    let operation = HelperClientFixture.launchItem(
      HelperClientFixture.systemLaunchItem, enabled: false)
    let planID = UUID()

    _ = await client.perform(operation, planID: planID)

    let request = try #require(try transport.sentOperationRequests().first)
    #expect(
      request
        == .setLaunchItemEnabled(
          item: HelperClientFixture.systemLaunchItem,
          enabled: false,
          attribution: .operation(planID: planID, operationID: operation.id)))
  }

  @Test("a maintenance task is transmitted as the task it is", arguments: MaintenanceTask.allCases)
  func maintenanceTaskIsTransmittedAsItself(task: MaintenanceTask) async throws {
    let transport = RecordingHelperTransport(succeedingWith: 0)
    let client = makeApprovedHelperClient(transport: transport)
    let operation = HelperClientFixture.maintenance(task)
    let planID = UUID()

    _ = await client.perform(operation, planID: planID)

    #expect(
      try transport.sentOperationRequests()
        == [.runMaintenance(task: task, planID: planID, operationID: operation.id)])
  }

  @Test("every transmitted request names the plan and the operation it belongs to")
  func everyRequestNamesItsPlanAndOperation() async throws {
    let transport = RecordingHelperTransport(succeedingWith: 0)
    let client = makeApprovedHelperClient(transport: transport)
    let planID = UUID()
    let operations = [
      HelperClientFixture.trash(HelperClientFixture.systemTarget),
      HelperClientFixture.launchItem(),
      HelperClientFixture.maintenance(),
    ]

    for operation in operations {
      _ = await client.perform(operation, planID: planID)
    }

    let requests = try transport.sentOperationRequests()
    #expect(requests.map(\.replyOperationID) == operations.map { $0.id })
    #expect(
      requests.map(\.requestPlanID) == Array(repeating: planID, count: operations.count),
      "the helper's log and the app's report reconcile one to one only if every request names both")
  }
}
