import Foundation
import GleamCore
import Testing

@Suite("Executor cancellation between items")
struct ExecutorCancellationTests {
  @Test(
    "cancellation after item two completes leaves one and two done, three and four untouched, and the report says which is which"
  )
  func cancellationBetweenItemsSplitsCompletedFromNotStarted() async throws {
    let base = InMemoryFileSystem()
    let first = ExecutorFixture.path("/Users/julian/Caches/cancel-one.log")
    let second = ExecutorFixture.path("/Users/julian/Caches/cancel-two.log")
    let third = ExecutorFixture.path("/Users/julian/Caches/cancel-three.log")
    let fourth = ExecutorFixture.path("/Users/julian/Caches/cancel-four.log")
    let thirdPayload = Data(repeating: 0x43, count: 30)
    await base.seedFile(at: first, contents: Data(repeating: 0x41, count: 10))
    await base.seedFile(at: second, contents: Data(repeating: 0x42, count: 20))
    await base.seedFile(at: third, contents: thirdPayload)
    await base.seedFile(at: fourth, contents: Data(repeating: 0x44, count: 40))
    let trigger = ExecutorCancellationTrigger()
    let fileSystem = ExecutorTrippingFileSystem(
      base: base, tripAfterMutating: second, trigger: trigger)
    let plan = ExecutorFixture.plan(
      operations: [
        ExecutorFixture.trashOperation(target: first),
        ExecutorFixture.trashOperation(target: second),
        ExecutorFixture.trashOperation(target: third),
        ExecutorFixture.trashOperation(target: fourth),
      ],
      totalBytes: 100
    )
    let executor = executorMake(
      fileSystem: fileSystem,
      denylist: try await ExecutorFixture.emptyDenylist(),
      isCancelled: { trigger.isTripped }
    )

    let events = await executorCollect(executor, executing: plan)

    let report = try #require(executorFinalReport(in: events))
    #expect(
      report.results.map(\.result) == [
        .completed(bytesReclaimed: 10),
        .completed(bytesReclaimed: 20),
        .notStarted,
        .notStarted,
      ])
    #expect(report.results.map(\.operationID) == plan.operations.map(\.id))
    #expect(report.bytesReclaimed == 30)
    #expect(await base.exists(first) == false)
    #expect(await base.exists(second) == false)
    #expect(await base.exists(ExecutorFixture.path("/.Trash/cancel-one.log")))
    #expect(await base.exists(ExecutorFixture.path("/.Trash/cancel-two.log")))
    #expect(await base.exists(third))
    #expect(try await base.readData(at: third, maxBytes: 100) == thirdPayload)
    #expect(await base.exists(fourth))
    #expect(await base.exists(ExecutorFixture.path("/.Trash/cancel-three.log")) == false)
    #expect(await base.exists(ExecutorFixture.path("/.Trash/cancel-four.log")) == false)
  }

  @Test("no operation after the cancellation point is ever started")
  func noOperationStartsAfterCancellation() async throws {
    let base = InMemoryFileSystem()
    let first = ExecutorFixture.path("/Users/julian/Caches/halt-one.log")
    let second = ExecutorFixture.path("/Users/julian/Caches/halt-two.log")
    await base.seedFile(at: first, contents: Data(repeating: 0x51, count: 10))
    await base.seedFile(at: second, contents: Data(repeating: 0x52, count: 20))
    let trigger = ExecutorCancellationTrigger()
    let fileSystem = ExecutorTrippingFileSystem(
      base: base, tripAfterMutating: first, trigger: trigger)
    let plan = ExecutorFixture.plan(
      operations: [
        ExecutorFixture.trashOperation(target: first),
        ExecutorFixture.trashOperation(target: second),
      ],
      totalBytes: 30
    )
    let executor = executorMake(
      fileSystem: fileSystem,
      denylist: try await ExecutorFixture.emptyDenylist(),
      isCancelled: { trigger.isTripped }
    )

    let events = await executorCollect(executor, executing: plan)

    #expect(executorStartedOperationIDs(in: events) == [plan.operations[0].id])
    let report = try #require(executorFinalReport(in: events))
    #expect(
      report.results.map(\.result) == [
        .completed(bytesReclaimed: 10),
        .notStarted,
      ])
    #expect(await base.exists(second))
  }
}
