import CleanupModule
import Foundation
import GleamCore
import Testing

@MainActor
@Suite("Cleanup module first clean")
struct CleanupModuleHappyPathTests {

  @Test(
    "the first clean end to end: scan, review down to file paths, deselect, execute in trash mode, result, acknowledge"
  )
  func firstCleanEndToEnd() async throws {
    let harness = makeCleanupHarness()
    #expect(harness.model.state == .idle)
    #expect(harness.model.hubEstimateBytes == 0)
    #expect(harness.model.degradedNotices.isEmpty)
    #expect(harness.model.failureNotice == nil)

    let feed = await beginScan(harness)
    #expect(feed.context.sessionID == ModuleFixture.sessionA)
    #expect(feed.context.hasFullDiskAccess)
    #expect(feed.context.settings == ModuleFixture.settings())
    #expect(
      harness.sessions.recordedScanRequests == [
        ScanContextRequest(settings: ModuleFixture.settings(), hasFullDiskAccess: true)
      ])
    #expect(harness.degraded.currentCallCount == 1)

    await expectEventually("the model is scanning") { scanProgress(harness.model) != nil }
    let initial = try #require(scanProgress(harness.model))
    #expect(initial.sessionID == ModuleFixture.sessionA)
    #expect(initial.phase == .indeterminate)
    #expect(initial.counters == .zero)
    #expect(harness.model.hubEstimateBytes == 0)

    let cache = ModuleFixture.cacheFinding()
    let log = ModuleFixture.logFinding()

    feed.send(.phase(.indeterminate), .finding(cache), .progress(makeCounters(10, 500, 1)))
    await expectEventually("the counters reach 500 reclaimable bytes") {
      scanProgress(harness.model)?.counters.bytesReclaimable == 500
    }
    #expect(scanProgress(harness.model)?.counters == makeCounters(10, 500, 1))
    #expect(harness.model.hubEstimateBytes == 500)

    feed.send(
      .phase(.determinate(estimatedTotalFiles: 40)),
      .finding(log),
      .progress(makeCounters(30, 1_300, 2))
    )
    await expectEventually("the counters reach 1300 reclaimable bytes") {
      scanProgress(harness.model)?.counters.bytesReclaimable == 1_300
    }
    #expect(scanProgress(harness.model)?.phase == .determinate(estimatedTotalFiles: 40))
    #expect(harness.model.hubEstimateBytes == 1_300)

    feed.send(.phase(.settling), .progress(makeCounters(40, 1_300, 2)))
    feed.finish()

    await expectEventually("the model reaches reviewing") { currentReview(harness.model) != nil }
    let review = try #require(currentReview(harness.model))
    #expect(review.sessionID == ModuleFixture.sessionA)
    #expect(review.categories.map(\.category) == [.userCache, .log])
    #expect(review.categories.first?.findings == [cache])
    #expect(review.categories.last?.findings == [log])
    #expect(review.selectedFindingIDs == [cache.id, log.id])
    #expect(review.selectedByteTotal == 1_300)
    #expect(review.selectedFileCount == 3)
    #expect(harness.model.hubEstimateBytes == 1_300)

    harness.model.toggleFinding(log.id)
    let trimmed = try #require(currentReview(harness.model))
    #expect(trimmed.selectedFindingIDs == [cache.id])
    #expect(trimmed.selectedByteTotal == 1_000)
    #expect(trimmed.selectedFileCount == 2)
    #expect(harness.model.hubEstimateBytes == 1_000)
    #expect(harness.model.permanentDeletionScope() == nil)

    let refusal = harness.model.executeSelection(permanentConfirmation: nil)
    #expect(refusal == nil)
    let run = await harness.executor.nextExecutionFeed()
    await expectEventually("the model reaches executing") {
      executionProgress(harness.model) != nil
    }

    #expect(harness.engine.planCallCount == 1)
    #expect(harness.engine.lastPlanSelection == [cache])
    #expect(harness.engine.lastPlanContext?.sessionID == ModuleFixture.sessionA)
    #expect(
      harness.sessions.recordedPlanRequests == [
        PlanContextRequest(sessionID: ModuleFixture.sessionA, settings: ModuleFixture.settings())
      ])

    let plan = try #require(harness.engine.lastPlan)
    #expect(run.plan.operations == plan.operations)
    #expect(run.plan.permanentDeletionConfirmation == nil)
    #expect(run.plan.operations.map(\.kind) == cache.paths.map { .moveToTrash(target: $0) })

    let start = try #require(executionProgress(harness.model))
    #expect(start.planID == run.plan.id)
    #expect(start.totalOperations == 2)
    #expect(start.finishedOperations == 0)
    #expect(start.bytesReclaimed == 0)
    #expect(start.currentOperationID == nil)

    let firstOperation = run.plan.operations[0]
    let secondOperation = run.plan.operations[1]

    run.send(.operationStarted(operationID: firstOperation.id))
    await expectEventually("operation one is current") {
      executionProgress(harness.model)?.currentOperationID == firstOperation.id
    }

    run.send(
      .operationFinished(operationID: firstOperation.id, result: .completed(bytesReclaimed: 600)))
    await expectEventually("one operation is finished") {
      executionProgress(harness.model)?.finishedOperations == 1
    }
    #expect(executionProgress(harness.model)?.bytesReclaimed == 600)
    #expect(executionProgress(harness.model)?.currentOperationID == nil)
    #expect(harness.model.hubEstimateBytes == 600)

    run.send(.operationStarted(operationID: secondOperation.id))
    run.send(
      .operationFinished(operationID: secondOperation.id, result: .completed(bytesReclaimed: 400)))
    await expectEventually("both operations are finished") {
      executionProgress(harness.model)?.finishedOperations == 2
    }
    #expect(executionProgress(harness.model)?.bytesReclaimed == 1_000)
    #expect(harness.model.hubEstimateBytes == 1_000)

    run.send(
      .planCompleted(
        makeReport(
          planID: run.plan.id,
          results: [
            (firstOperation.id, .completed(bytesReclaimed: 600)),
            (secondOperation.id, .completed(bytesReclaimed: 400)),
          ],
          bytesReclaimed: 1_000
        )))
    run.finish()

    await expectEventually("the result arrives") { currentSummary(harness.model) != nil }
    let summary = try #require(currentSummary(harness.model))
    #expect(summary.bytesReclaimed == 1_000)
    #expect(summary.failures.isEmpty)
    #expect(summary.skippedDenylistedNames.isEmpty)
    #expect(summary.categoryOutcomes.count == 1)
    let outcome = try #require(summary.categoryOutcomes.first)
    #expect(outcome.category == .userCache)
    #expect(outcome.completedCount == 2)
    #expect(outcome.failedCount == 0)
    #expect(outcome.skippedCount == 0)
    #expect(outcome.notStartedCount == 0)
    #expect(outcome.bytesReclaimed == 1_000)
    #expect(harness.model.hubEstimateBytes == 1_000)

    harness.model.acknowledgeResult()
    #expect(harness.model.state == .idle)
    #expect(harness.model.hubEstimateBytes == 1_000)
    #expect(harness.sessions.fileSystem.violationCount == 0)
  }

  @Test("the next scan revises the hub estimate kept from the last result")
  func nextScanRevisesTheKeptEstimate() async {
    let harness = makeCleanupHarness()
    _ = await reachResult(harness, bytesReclaimed: 1_000)
    harness.model.acknowledgeResult()
    #expect(harness.model.hubEstimateBytes == 1_000)

    let feed = await beginScan(harness)
    feed.send(.phase(.indeterminate), .progress(makeCounters(5, 250, 1)))
    await expectEventually("the estimate follows the new scan") {
      harness.model.hubEstimateBytes == 250
    }
  }
}
