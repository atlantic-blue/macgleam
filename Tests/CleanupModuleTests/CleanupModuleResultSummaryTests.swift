import CleanupModule
import Foundation
import GleamCore
import Testing

@MainActor
@Suite("Cleanup module result summary")
struct CleanupModuleResultSummaryTests {

  @Test(
    "the result names every outcome: completed, failed and denylist skipped, in plan and category order"
  )
  func theResultNamesEveryOutcome() async throws {
    let harness = makeCleanupHarness()
    let cache = ModuleFixture.cacheFinding()
    let log = ModuleFixture.logFinding()
    let run = try #require(await reachExecuting(harness, findings: [cache, log]))
    let operations = run.plan.operations
    #expect(operations.count == 3)

    let failureSentence = "The cache file is locked; nothing was removed."
    run.send(
      .operationStarted(operationID: operations[0].id),
      .operationFinished(operationID: operations[0].id, result: .completed(bytesReclaimed: 600)),
      .operationStarted(operationID: operations[1].id),
      .operationFinished(operationID: operations[1].id, result: .failed(reason: failureSentence)),
      .operationStarted(operationID: operations[2].id),
      .operationFinished(operationID: operations[2].id, result: .skippedDenylisted)
    )
    run.send(
      .planCompleted(
        makeReport(
          planID: run.plan.id,
          results: [
            (operations[0].id, .completed(bytesReclaimed: 600)),
            (operations[1].id, .failed(reason: failureSentence)),
            (operations[2].id, .skippedDenylisted),
          ],
          bytesReclaimed: 600
        )))
    run.finish()
    await expectEventually("the result arrives") { currentSummary(harness.model) != nil }

    let summary = try #require(currentSummary(harness.model))
    #expect(summary.bytesReclaimed == 600)
    #expect(summary.failures.count == 1)
    #expect(summary.failures.first?.contains("locked") == true)
    #expect(summary.skippedDenylistedNames == ["session.log"])
    #expect(summary.categoryOutcomes.map(\.category) == [.userCache, .log])
    let cacheOutcome = try #require(summary.categoryOutcomes.first)
    #expect(cacheOutcome.completedCount == 1)
    #expect(cacheOutcome.failedCount == 1)
    #expect(cacheOutcome.skippedCount == 0)
    #expect(cacheOutcome.notStartedCount == 0)
    #expect(cacheOutcome.bytesReclaimed == 600)
    let logOutcome = try #require(summary.categoryOutcomes.last)
    #expect(logOutcome.skippedCount == 1)
    #expect(logOutcome.completedCount == 0)
    #expect(logOutcome.failedCount == 0)
    #expect(harness.model.hubEstimateBytes == 600)
  }

  @Test("an execution refusal surfaces as a failure sentence in the result, never a silent drop")
  func anExecutionRefusalSurfacesAsAFailureSentence() async throws {
    let harness = makeCleanupHarness()
    let cache = ModuleFixture.cacheFinding()
    let run = try #require(await reachExecuting(harness, findings: [cache]))
    let operations = run.plan.operations

    run.send(.refused(.helperUnavailable(reason: "The helper is not installed.")))
    run.send(
      .planCompleted(
        makeReport(
          planID: run.plan.id,
          results: operations.map { ($0.id, .notStarted) },
          bytesReclaimed: 0
        )))
    run.finish()

    await expectEventually("the refusal lands as a result") {
      currentSummary(harness.model) != nil
    }
    let summary = try #require(currentSummary(harness.model))
    #expect(summary.bytesReclaimed == 0)
    #expect(!summary.failures.isEmpty)
    #expect(summary.failures.allSatisfy { !$0.isEmpty })
    let outcome = try #require(summary.categoryOutcomes.first)
    #expect(outcome.notStartedCount == 2)
    #expect(outcome.completedCount == 0)
  }
}
