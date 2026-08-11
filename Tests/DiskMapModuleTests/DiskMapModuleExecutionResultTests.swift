import DiskMapModule
import Foundation
import GleamCore
import Testing

@MainActor
@Suite("Space lens module execution progress")
struct DiskMapModuleExecutionProgressTests {

  private func threeNodeRun(
    _ harness: DiskMapHarness
  ) async throws -> ExecutionFeed {
    try #require(
      await reachExecuting(
        harness,
        selecting: [
          LensModuleFixture.filmFile,
          LensModuleFixture.clipFile,
          LensModuleFixture.documentsDirectory,
        ]))
  }

  @Test("executing starts with zero finished operations and the plan's exact operation count")
  func executingStartsAtZero() async throws {
    let harness = makeDiskMapHarness()
    let run = try await threeNodeRun(harness)

    let progress = try #require(executionProgress(harness.model))
    #expect(progress.planID == run.plan.id)
    #expect(progress.totalOperations == 3)
    #expect(progress.finishedOperations == 0)
    #expect(progress.bytesReclaimed == 0)
    #expect(progress.currentOperationID == nil)
  }

  @Test("operationStarted names the running operation and operationFinished clears it")
  func startedAndFinishedDriveTheCurrentOperation() async throws {
    let harness = makeDiskMapHarness()
    let run = try await threeNodeRun(harness)
    let first = run.plan.operations[0]

    run.send(.operationStarted(operationID: first.id))
    await expectEventually("the running operation is named") {
      executionProgress(harness.model)?.currentOperationID == first.id
    }

    run.send(
      .operationFinished(operationID: first.id, result: .completed(bytesReclaimed: 1_000)))
    await expectEventually("the operation clears") {
      executionProgress(harness.model)?.currentOperationID == nil
    }
    let progress = try #require(executionProgress(harness.model))
    #expect(progress.finishedOperations == 1)
    #expect(progress.bytesReclaimed == 1_000)
  }

  @Test("finished operations and reclaimed bytes only ever tick up")
  func progressIsMonotone() async throws {
    let harness = makeDiskMapHarness()
    let run = try await threeNodeRun(harness)

    var lastFinished: UInt32 = 0
    var lastBytes: UInt64 = 0
    for (index, operation) in run.plan.operations.enumerated() {
      run.send(.operationStarted(operationID: operation.id))
      run.send(
        .operationFinished(
          operationID: operation.id, result: .completed(bytesReclaimed: 500)))
      await expectEventually("operation \(index) lands") {
        executionProgress(harness.model)?.finishedOperations == UInt32(index + 1)
      }
      let progress = try #require(executionProgress(harness.model))
      #expect(progress.finishedOperations >= lastFinished)
      #expect(progress.bytesReclaimed >= lastBytes)
      #expect(progress.finishedOperations <= progress.totalOperations)
      lastFinished = progress.finishedOperations
      lastBytes = progress.bytesReclaimed
    }
  }
}

@MainActor
@Suite("Space lens module result")
struct DiskMapModuleResultTests {

  @Test("the summary is consistent with the one report: totals, counts, sentences and skips")
  func theSummaryIsConsistentWithTheReport() async throws {
    let harness = makeDiskMapHarness()
    let run = try #require(
      await reachExecuting(
        harness,
        selecting: [
          LensModuleFixture.filmFile,
          LensModuleFixture.clipFile,
          LensModuleFixture.documentsDirectory,
        ]))
    let operations = run.plan.operations
    let failureSentence =
      "The file could not be moved because the volume became unavailable; nothing was removed."
    let results: [(UUID, OperationResult)] = [
      (operations[0].id, .completed(bytesReclaimed: 1_000)),
      (operations[1].id, .failed(reason: failureSentence)),
      (operations[2].id, .skippedDenylisted),
    ]
    for (operationID, result) in results {
      run.send(.operationStarted(operationID: operationID))
      run.send(.operationFinished(operationID: operationID, result: result))
    }
    run.send(
      .planCompleted(makeReport(planID: run.plan.id, results: results, bytesReclaimed: 1_000)))
    run.finish()

    await expectEventually("the result arrives") {
      currentSummary(harness.model) != nil
    }
    let summary = try #require(currentSummary(harness.model))
    #expect(summary.bytesReclaimed == 1_000)
    #expect(summary.completedCount == 1)
    #expect(summary.failedCount == 1)
    #expect(summary.notStartedCount == 0)
    #expect(summary.failures == [failureSentence])
    #expect(summary.skippedDenylistedNames == ["Documents"])
    let accounted =
      summary.completedCount + summary.failedCount + summary.notStartedCount
      + UInt32(summary.skippedDenylistedNames.count)
    #expect(accounted == UInt32(operations.count))
  }

  @Test(
    "cancelExecution stays executing until the report, then the partial result names the untouched")
  func cancellationYieldsAPartialResult() async throws {
    let harness = makeDiskMapHarness()
    let run = try #require(
      await reachExecuting(
        harness,
        selecting: [
          LensModuleFixture.filmFile,
          LensModuleFixture.clipFile,
          LensModuleFixture.documentsDirectory,
        ]))
    let operations = run.plan.operations
    run.send(.operationStarted(operationID: operations[0].id))
    run.send(
      .operationFinished(
        operationID: operations[0].id, result: .completed(bytesReclaimed: 700)))

    harness.model.cancelExecution()
    await settleBriefly()
    #expect(executionProgress(harness.model) != nil, "still executing until the report arrives")

    let results: [(UUID, OperationResult)] = [
      (operations[0].id, .completed(bytesReclaimed: 700)),
      (operations[1].id, .notStarted),
      (operations[2].id, .notStarted),
    ]
    run.send(
      .planCompleted(makeReport(planID: run.plan.id, results: results, bytesReclaimed: 700)))
    run.finish()

    await expectEventually("the partial result arrives") {
      currentSummary(harness.model) != nil
    }
    let summary = try #require(currentSummary(harness.model))
    #expect(summary.completedCount == 1)
    #expect(summary.notStartedCount == 2)
    #expect(summary.failedCount == 0)
    #expect(summary.bytesReclaimed == 700)
  }

  @Test("an execution refusal surfaces as a failure sentence in the summary, never a silent drop")
  func anExecutionRefusalSurfacesInTheSummary() async throws {
    let harness = makeDiskMapHarness()
    let run = try #require(await reachExecuting(harness))
    let operations = run.plan.operations

    run.send(.refused(.helperUnavailable(reason: "The helper is not available.")))
    run.send(
      .planCompleted(
        makeReport(
          planID: run.plan.id,
          results: operations.map { ($0.id, .notStarted) },
          bytesReclaimed: 0)))
    run.finish()

    await expectEventually("the result arrives") {
      currentSummary(harness.model) != nil
    }
    let summary = try #require(currentSummary(harness.model))
    #expect(!summary.failures.isEmpty)
    #expect(summary.bytesReclaimed == 0)
    #expect(summary.notStartedCount == UInt32(operations.count))
  }

  @Test("acknowledging the result lands on idle, never back on the old map")
  func acknowledgingTheResultLandsOnIdle() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachResult(harness))

    harness.model.acknowledgeResult()

    #expect(harness.model.state == .idle)
    #expect(browsingState(harness.model) == nil)
  }
}
