import CleanupModule
import Foundation
import GleamCore
import Testing

@MainActor
@Suite("Cleanup module cancellation")
struct CleanupModuleCancellationTests {

  @Test("cancelling a scan discards the partial findings and returns to idle")
  func cancellingAScanReturnsToIdle() async {
    let harness = makeCleanupHarness()
    let feed = await beginScan(harness)
    feed.send(
      .phase(.indeterminate),
      .finding(ModuleFixture.cacheFinding()),
      .progress(makeCounters(10, 1_000, 1))
    )
    await expectEventually("the model is scanning with a finding") {
      scanProgress(harness.model)?.counters.findingCount == 1
    }

    harness.model.cancelScan()
    await expectEventually("the model returns to idle") {
      harness.model.state == .idle
    }
  }

  @Test("events from a cancelled scan never resurface")
  func eventsFromACancelledScanNeverResurface() async {
    let harness = makeCleanupHarness()
    let feed = await beginScan(harness)
    feed.send(.phase(.indeterminate), .progress(makeCounters(10, 500, 1)))
    await expectEventually("the model is scanning") {
      scanProgress(harness.model) != nil
    }
    harness.model.cancelScan()
    await expectEventually("the model returns to idle") {
      harness.model.state == .idle
    }

    feed.send(
      .finding(ModuleFixture.cacheFinding()),
      .progress(makeCounters(50, 9_000, 2)),
      .phase(.settling)
    )
    feed.finish()
    await settleBriefly()
    #expect(harness.model.state == .idle)
  }

  @Test("a scan after a cancellation runs on a fresh session")
  func aScanAfterACancellationRunsOnAFreshSession() async {
    let harness = makeCleanupHarness()
    let feed = await beginScan(harness)
    feed.send(.phase(.indeterminate))
    await expectEventually("the model is scanning") {
      scanProgress(harness.model) != nil
    }
    harness.model.cancelScan()
    await expectEventually("the model returns to idle") {
      harness.model.state == .idle
    }

    let secondFeed = await beginScan(harness)
    #expect(secondFeed.context.sessionID == ModuleFixture.sessionB)
    #expect(harness.sessions.minted == [ModuleFixture.sessionA, ModuleFixture.sessionB])
  }

  @Test("cancelling execution keeps the state executing until the executor's report arrives")
  func cancellingExecutionWaitsForTheReport() async throws {
    let harness = makeCleanupHarness()
    let cache = ModuleFixture.cacheFinding()
    let log = ModuleFixture.logFinding()
    let run = try #require(await reachExecuting(harness, findings: [cache, log]))
    let operations = run.plan.operations
    #expect(operations.count == 3)

    run.send(.operationStarted(operationID: operations[0].id))
    run.send(
      .operationFinished(operationID: operations[0].id, result: .completed(bytesReclaimed: 600)))
    await expectEventually("one operation finished") {
      executionProgress(harness.model)?.finishedOperations == 1
    }

    harness.model.cancelExecution()
    await settleBriefly()
    #expect(executionProgress(harness.model) != nil, "the state stays executing until the report")

    run.send(
      .planCompleted(
        makeReport(
          planID: run.plan.id,
          results: [
            (operations[0].id, .completed(bytesReclaimed: 600)),
            (operations[1].id, .notStarted),
            (operations[2].id, .notStarted),
          ],
          bytesReclaimed: 600
        )))
    run.finish()
    await expectEventually("the partial result arrives") {
      currentSummary(harness.model) != nil
    }
  }

  @Test("a cancelled run's result names the completed and untouched operations exactly")
  func aCancelledRunNamesCompletedAndUntouched() async throws {
    let harness = makeCleanupHarness()
    let cache = ModuleFixture.cacheFinding()
    let log = ModuleFixture.logFinding()
    let run = try #require(await reachExecuting(harness, findings: [cache, log]))
    let operations = run.plan.operations

    run.send(.operationStarted(operationID: operations[0].id))
    run.send(
      .operationFinished(operationID: operations[0].id, result: .completed(bytesReclaimed: 600)))
    await expectEventually("one operation finished") {
      executionProgress(harness.model)?.finishedOperations == 1
    }
    harness.model.cancelExecution()
    run.send(
      .planCompleted(
        makeReport(
          planID: run.plan.id,
          results: [
            (operations[0].id, .completed(bytesReclaimed: 600)),
            (operations[1].id, .notStarted),
            (operations[2].id, .notStarted),
          ],
          bytesReclaimed: 600
        )))
    run.finish()
    await expectEventually("the partial result arrives") {
      currentSummary(harness.model) != nil
    }

    let summary = try #require(currentSummary(harness.model))
    #expect(summary.bytesReclaimed == 600)
    #expect(summary.failures.isEmpty, "untouched operations are not failures")
    #expect(summary.categoryOutcomes.map(\.category) == [.userCache, .log])
    let cacheOutcome = try #require(summary.categoryOutcomes.first)
    #expect(cacheOutcome.completedCount == 1)
    #expect(cacheOutcome.notStartedCount == 1)
    #expect(cacheOutcome.failedCount == 0)
    #expect(cacheOutcome.skippedCount == 0)
    #expect(cacheOutcome.bytesReclaimed == 600)
    let logOutcome = try #require(summary.categoryOutcomes.last)
    #expect(logOutcome.notStartedCount == 1)
    #expect(logOutcome.completedCount == 0)
    #expect(logOutcome.bytesReclaimed == 0)
    #expect(harness.model.hubEstimateBytes == 600)
  }
}
