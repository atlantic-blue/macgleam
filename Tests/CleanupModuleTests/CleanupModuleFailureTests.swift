import CleanupModule
import Foundation
import GleamCore
import Testing

struct ScannerBroke: Error {}
struct PlannerBroke: Error {}

@MainActor
@Suite("Cleanup module failure notices")
struct CleanupModuleFailureTests {

  @Test("a failing scan stream lands idle with a plain sentence")
  func aFailingScanStreamLandsIdleWithAPlainSentence() async throws {
    let harness = makeCleanupHarness()
    let feed = await beginScan(harness)
    feed.send(.phase(.indeterminate), .progress(makeCounters(10, 500, 1)))
    await expectEventually("the model is scanning") {
      scanProgress(harness.model) != nil
    }

    feed.fail(ScannerBroke())
    await expectEventually("the model returns to idle with a notice") {
      harness.model.state == .idle && harness.model.failureNotice != nil
    }
    let notice = try #require(harness.model.failureNotice)
    #expect(!notice.isEmpty)
  }

  @Test("the next startScan clears the failure notice")
  func theNextStartScanClearsTheFailureNotice() async {
    let harness = makeCleanupHarness()
    let feed = await beginScan(harness)
    feed.fail(ScannerBroke())
    await expectEventually("the failure notice is set") {
      harness.model.failureNotice != nil
    }

    harness.model.startScan()
    _ = await harness.engine.nextScanFeed()
    await expectEventually("the notice is cleared by the new scan") {
      harness.model.failureNotice == nil
    }
  }

  @Test("a plan failure keeps the review and selection and sets a plain sentence")
  func aPlanFailureKeepsTheReviewAndSetsANotice() async throws {
    let harness = makeCleanupHarness()
    let review = try #require(
      await reachReviewing(harness, findings: [ModuleFixture.cacheFinding()]))
    harness.engine.failPlans(with: PlannerBroke())

    let refusal = harness.model.executeSelection(permanentConfirmation: nil)
    #expect(refusal == nil)
    await expectEventually("the failure notice is set") {
      harness.model.failureNotice != nil
    }
    let notice = try #require(harness.model.failureNotice)
    #expect(!notice.isEmpty)
    #expect(
      currentReview(harness.model) == review, "the review and selection survive a plan failure")
    #expect(harness.executor.executeCallCount == 0)
  }
}
