import Foundation
import GleamCore
import Testing

@Suite("Operation")
struct OperationTests {

  static let target = Fixture.path("/Users/test/Library/Caches/example")

  static let allKinds: [Operation.Kind] = [
    .moveToTrash(target: target),
    .deletePermanently(target: target),
    .quarantine(target: target),
    .archive(target: target, groupID: Fixture.groupID),
    .setLaunchItemEnabled(item: LaunchItemID(value: "com.example.agent.user"), enabled: false),
    .setLaunchItemEnabled(item: LaunchItemID(value: "com.example.agent.user"), enabled: true),
    .runMaintenance(task: .flushDomainNameSystemCache),
  ]

  @Test("every operation kind round trips losslessly", arguments: allKinds)
  func everyKindRoundTrips(kind: Operation.Kind) throws {
    try expectLosslessRoundTrip(makeOperation(kind: kind))
  }

  @Test("privileges use their contract raw values")
  func privilegesUseContractRawValues() {
    #expect(Operation.Privilege.user.rawValue == "user")
    #expect(Operation.Privilege.root.rawValue == "root")
  }

  @Test("an operation keeps the finding it came from through coding")
  func operationKeepsFindingThroughCoding() throws {
    let operation = makeOperation()
    let encoded = try JSONEncoder().encode(operation)
    let decoded = try JSONDecoder().decode(Operation.self, from: encoded)
    #expect(decoded.findingID == Fixture.findingID)
  }
}

@Suite("OperationResult")
struct OperationResultTests {

  static let allResults: [OperationResult] = [
    .completed(bytesReclaimed: 0),
    .completed(bytesReclaimed: UInt64.max),
    .failed(reason: "The file moved before the operation ran, nothing was changed."),
    .skippedDenylisted,
    .notStarted,
  ]

  @Test("every result round trips losslessly", arguments: allResults)
  func everyResultRoundTrips(result: OperationResult) throws {
    try expectLosslessRoundTrip(result)
  }

  @Test("a denylist skip is distinct from a failure")
  func denylistSkipIsDistinctFromFailure() {
    #expect(OperationResult.skippedDenylisted != .failed(reason: "denylisted"))
    #expect(OperationResult.skippedDenylisted != .notStarted)
  }
}

@Suite("MaintenanceTask")
struct MaintenanceTaskTests {

  @Test("exactly five maintenance tasks exist")
  func exactlyFiveTasksExist() {
    #expect(MaintenanceTask.allCases.count == 5)
  }

  @Test("only the Domain Name System cache flush clears user visible data")
  func onlyDomainNameSystemFlushClearsUserVisibleData() {
    for task in MaintenanceTask.allCases {
      #expect(task.clearsUserVisibleData == (task == .flushDomainNameSystemCache))
    }
  }

  @Test("every task round trips losslessly", arguments: MaintenanceTask.allCases)
  func everyTaskRoundTrips(task: MaintenanceTask) throws {
    try expectLosslessRoundTrip(task)
  }
}

@Suite("OperationPlan and confirmation matching")
struct OperationPlanTests {

  static func trashOperations() -> [Operation] {
    [
      makeOperation(
        id: Fixture.uuid(0x11),
        kind: .moveToTrash(target: Fixture.path("/Users/test/Library/Caches/a"))
      ),
      makeOperation(
        id: Fixture.uuid(0x12),
        kind: .moveToTrash(target: Fixture.path("/Users/test/Library/Caches/b"))
      ),
    ]
  }

  static func permanentOperations() -> [Operation] {
    [
      makeOperation(
        id: Fixture.uuid(0x13),
        kind: .deletePermanently(target: Fixture.path("/Users/test/.Trash/a"))
      ),
      makeOperation(
        id: Fixture.uuid(0x14),
        kind: .deletePermanently(target: Fixture.path("/Users/test/.Trash/b"))
      ),
      makeOperation(
        id: Fixture.uuid(0x15),
        kind: .deletePermanently(target: Fixture.path("/Users/test/.Trash/c"))
      ),
    ]
  }

  static func isPermanent(_ operation: Operation) -> Bool {
    if case .deletePermanently = operation.kind { return true }
    return false
  }

  @Test("a plan without permanent deletion carries no confirmation")
  func planWithoutPermanentDeletionCarriesNoConfirmation() throws {
    let plan = makeOperationPlan(operations: Self.trashOperations(), totalBytes: 2048)
    #expect(!plan.operations.contains(where: Self.isPermanent))
    #expect(plan.permanentDeletionConfirmation == nil)
    try expectLosslessRoundTrip(plan)
  }

  @Test("a permanent plan's confirmation counts the permanent operations exactly")
  func permanentPlanConfirmationCountsPermanentOperations() throws {
    let operations = Self.trashOperations() + Self.permanentOperations()
    let confirmation = PermanentDeletionConfirmation(
      fileCount: 3,
      byteTotal: 9216,
      confirmedAt: Fixture.referenceDate
    )
    let plan = makeOperationPlan(
      operations: operations,
      totalBytes: 11264,
      confirmation: confirmation
    )
    let permanentCount = plan.operations.filter(Self.isPermanent).count
    let confirmed = try #require(plan.permanentDeletionConfirmation)
    #expect(UInt32(permanentCount) == confirmed.fileCount)
    try expectLosslessRoundTrip(plan)
  }

  @Test("a plan preserves operation order through coding")
  func planPreservesOperationOrderThroughCoding() throws {
    let operations = Self.permanentOperations() + Self.trashOperations()
    let plan = makeOperationPlan(
      operations: operations,
      totalBytes: 11264,
      confirmation: PermanentDeletionConfirmation(
        fileCount: 3,
        byteTotal: 9216,
        confirmedAt: Fixture.referenceDate
      )
    )
    let encoded = try JSONEncoder().encode(plan)
    let decoded = try JSONDecoder().decode(OperationPlan.self, from: encoded)
    #expect(decoded.operations.map(\.id) == operations.map(\.id))
  }

  @Test("an empty plan round trips losslessly")
  func emptyPlanRoundTrips() throws {
    try expectLosslessRoundTrip(makeOperationPlan(operations: [], totalBytes: 0))
  }

  @Test("a confirmation round trips losslessly at the extremes")
  func confirmationRoundTripsAtExtremes() throws {
    try expectLosslessRoundTrip(
      PermanentDeletionConfirmation(
        fileCount: UInt32.max,
        byteTotal: UInt64.max,
        confirmedAt: Fixture.farFutureDate
      )
    )
  }
}

@Suite("ExecutionReport")
struct ExecutionReportTests {

  @Test("a report carries one result per operation in plan order")
  func reportCarriesOneResultPerOperationInPlanOrder() {
    let operations = OperationPlanTests.trashOperations()
    let report = ExecutionReport(
      planID: Fixture.planID,
      results: [
        (operationID: operations[0].id, result: .completed(bytesReclaimed: 1024)),
        (operationID: operations[1].id, result: .notStarted),
      ],
      bytesReclaimed: 1024,
      startedAt: Fixture.referenceDate,
      finishedAt: Fixture.laterDate
    )
    #expect(report.results.count == operations.count)
    #expect(report.results.map(\.operationID) == operations.map(\.id))
  }

  @Test("a report round trips losslessly, mixed results included")
  func reportRoundTripsLosslessly() throws {
    let report = ExecutionReport(
      planID: Fixture.planID,
      results: [
        (operationID: Fixture.uuid(0x11), result: .completed(bytesReclaimed: 1024)),
        (operationID: Fixture.uuid(0x12), result: .skippedDenylisted),
        (operationID: Fixture.uuid(0x13), result: .failed(reason: "The volume was unmounted.")),
        (operationID: Fixture.uuid(0x14), result: .notStarted),
      ],
      bytesReclaimed: 1024,
      startedAt: Fixture.referenceDate,
      finishedAt: Fixture.laterDate
    )
    try expectLosslessRoundTrip(report)
  }
}
