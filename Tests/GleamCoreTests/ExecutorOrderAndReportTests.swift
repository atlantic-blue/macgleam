import Foundation
import GleamCore
import Testing

@Suite("Executor order and report")
struct ExecutorOrderAndReportTests {
  @Test(
    "executes a trash plan in plan order, emitting started and finished per operation and one final report"
  )
  func executesInPlanOrderWithFullEventSequence() async throws {
    let fileSystem = InMemoryFileSystem()
    let first = ExecutorFixture.path("/Users/julian/Caches/one.log")
    let second = ExecutorFixture.path("/Users/julian/Caches/two.log")
    let third = ExecutorFixture.path("/Users/julian/Logs/three.log")
    await fileSystem.seedFile(at: first, contents: Data(repeating: 0xA1, count: 10))
    await fileSystem.seedFile(at: second, contents: Data(repeating: 0xA2, count: 20))
    await fileSystem.seedFile(at: third, contents: Data(repeating: 0xA3, count: 30))
    let plan = ExecutorFixture.plan(
      operations: [
        ExecutorFixture.trashOperation(target: first),
        ExecutorFixture.trashOperation(target: second),
        ExecutorFixture.trashOperation(target: third),
      ],
      totalBytes: 60
    )
    let executor = executorMake(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist())

    let events = await executorCollect(executor, executing: plan)

    let expectedReport = ExecutionReport(
      planID: plan.id,
      results: [
        (operationID: plan.operations[0].id, result: OperationResult.completed(bytesReclaimed: 10)),
        (operationID: plan.operations[1].id, result: OperationResult.completed(bytesReclaimed: 20)),
        (operationID: plan.operations[2].id, result: OperationResult.completed(bytesReclaimed: 30)),
      ],
      bytesReclaimed: 60,
      startedAt: ExecutorFixture.executionInstant,
      finishedAt: ExecutorFixture.executionInstant
    )
    let expectedEvents: [ExecutionEvent] = [
      .operationStarted(operationID: plan.operations[0].id),
      .operationFinished(
        operationID: plan.operations[0].id, result: .completed(bytesReclaimed: 10)),
      .operationStarted(operationID: plan.operations[1].id),
      .operationFinished(
        operationID: plan.operations[1].id, result: .completed(bytesReclaimed: 20)),
      .operationStarted(operationID: plan.operations[2].id),
      .operationFinished(
        operationID: plan.operations[2].id, result: .completed(bytesReclaimed: 30)),
      .planCompleted(expectedReport),
    ]
    #expect(events == expectedEvents)
  }

  @Test(
    "moves every target fully: sources are gone and the trash holds exactly the moved payloads, bytes intact"
  )
  func movesEveryTargetFullyIntoTheTrash() async throws {
    let fileSystem = InMemoryFileSystem()
    let first = ExecutorFixture.path("/Users/julian/Caches/one.log")
    let second = ExecutorFixture.path("/Users/julian/Caches/two.log")
    let firstPayload = Data(repeating: 0xB1, count: 10)
    let secondPayload = Data(repeating: 0xB2, count: 20)
    await fileSystem.seedFile(at: first, contents: firstPayload)
    await fileSystem.seedFile(at: second, contents: secondPayload)
    let plan = ExecutorFixture.plan(
      operations: [
        ExecutorFixture.trashOperation(target: first),
        ExecutorFixture.trashOperation(target: second),
      ],
      totalBytes: 30
    )
    let executor = executorMake(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist())

    _ = await executorCollect(executor, executing: plan)

    #expect(await fileSystem.exists(first) == false)
    #expect(await fileSystem.exists(second) == false)
    let trashed = try await fileSystem.children(of: ExecutorFixture.path("/.Trash"))
    #expect(Set(trashed.map(\.path.value)) == ["/.Trash/one.log", "/.Trash/two.log"])
    #expect(
      try await fileSystem.readData(at: ExecutorFixture.path("/.Trash/one.log"), maxBytes: 100)
        == firstPayload)
    #expect(
      try await fileSystem.readData(at: ExecutorFixture.path("/.Trash/two.log"), maxBytes: 100)
        == secondPayload)
  }

  @Test("a failing operation adds nothing to the trash while its neighbours' moves stand")
  func failingOperationAddsNothingToTheTrash() async throws {
    let fileSystem = InMemoryFileSystem()
    let first = ExecutorFixture.path("/Users/julian/Caches/one.log")
    let third = ExecutorFixture.path("/Users/julian/Logs/three.log")
    await fileSystem.seedFile(at: first, contents: Data(repeating: 0xC1, count: 10))
    await fileSystem.seedFile(at: third, contents: Data(repeating: 0xC3, count: 30))
    let plan = ExecutorFixture.plan(
      operations: [
        ExecutorFixture.trashOperation(target: first),
        ExecutorFixture.trashOperation(
          target: ExecutorFixture.path("/Users/julian/never-seeded.log")),
        ExecutorFixture.trashOperation(target: third),
      ],
      totalBytes: 40
    )
    let executor = executorMake(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist())

    _ = await executorCollect(executor, executing: plan)

    let trashed = try await fileSystem.children(of: ExecutorFixture.path("/.Trash"))
    #expect(Set(trashed.map(\.path.value)) == ["/.Trash/one.log", "/.Trash/three.log"])
  }

  @Test("the report carries the plan identifier, the injected instants and the reclaimed byte sum")
  func reportCarriesPlanIdentifierInstantsAndByteSum() async throws {
    let fileSystem = InMemoryFileSystem()
    let target = ExecutorFixture.path("/Users/julian/Caches/only.log")
    await fileSystem.seedFile(at: target, contents: Data(repeating: 0xD1, count: 25))
    let plan = ExecutorFixture.plan(
      operations: [ExecutorFixture.trashOperation(target: target)],
      totalBytes: 25
    )
    let executor = executorMake(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist())

    let events = await executorCollect(executor, executing: plan)

    let report = try #require(executorFinalReport(in: events))
    #expect(report.planID == plan.id)
    #expect(report.results.map(\.operationID) == plan.operations.map(\.id))
    #expect(report.bytesReclaimed == 25)
    #expect(report.startedAt == ExecutorFixture.executionInstant)
    #expect(report.finishedAt == ExecutorFixture.executionInstant)
  }

  @Test("an empty plan still terminates with one well formed report holding zero results")
  func emptyPlanStillProducesAReport() async throws {
    let fileSystem = InMemoryFileSystem()
    let plan = ExecutorFixture.plan(operations: [], totalBytes: 0)
    let executor = executorMake(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist())

    let executing: any PlanExecuting = executor
    var events: [ExecutionEvent] = []
    for await event in executing.execute(plan) {
      events.append(event)
    }

    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.isEmpty)
    #expect(report.bytesReclaimed == 0)
    #expect(executorStartedOperationIDs(in: events).isEmpty)
  }
}
