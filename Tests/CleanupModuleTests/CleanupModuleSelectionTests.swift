import CleanupModule
import Foundation
import GleamCore
import Testing

@MainActor
@Suite("Cleanup module review and selection")
struct CleanupModuleSelectionTests {

  @Test("review preselects only safe findings, never a risky one whatever it claims")
  func reviewPreselectsOnlySafeFindings() async throws {
    let harness = makeCleanupHarness()
    let review = try #require(
      await reachReviewing(
        harness,
        findings: [
          ModuleFixture.cacheFinding(),
          ModuleFixture.spareCacheFinding(),
          ModuleFixture.riskyPreselectedFinding(),
          ModuleFixture.dangerousPreselectedFinding(),
        ]))
    #expect(review.selectedFindingIDs == [ModuleFixture.cacheFinding().id])
  }

  @Test("the review groups findings by category in the order the first of each streamed")
  func reviewGroupsCategoriesInFirstStreamedOrder() async throws {
    let harness = makeCleanupHarness()
    let cache = ModuleFixture.cacheFinding()
    let log = ModuleFixture.logFinding()
    let spare = ModuleFixture.spareCacheFinding()
    let review = try #require(
      await reachReviewing(harness, findings: [cache, log, spare]))
    #expect(review.categories.map(\.category) == [.userCache, .log])
    #expect(review.categories.first?.findings == [cache, spare])
    #expect(review.categories.last?.findings == [log])
  }

  @Test("every reviewed finding belongs to the scan session")
  func everyReviewedFindingBelongsToTheSession() async throws {
    let harness = makeCleanupHarness()
    let review = try #require(
      await reachReviewing(
        harness,
        findings: [ModuleFixture.cacheFinding(), ModuleFixture.logFinding()]))
    #expect(review.sessionID == ModuleFixture.sessionA)
    for category in review.categories {
      for finding in category.findings {
        #expect(finding.sessionID == review.sessionID)
      }
    }
  }

  @Test("toggling an unknown finding identifier changes nothing")
  func togglingAnUnknownFindingChangesNothing() async throws {
    let harness = makeCleanupHarness()
    _ = try #require(
      await reachReviewing(harness, findings: [ModuleFixture.cacheFinding()]))
    let before = snapshot(harness.model)
    harness.model.toggleFinding(ModuleFixture.uuid(0xEE))
    await settleBriefly()
    #expect(snapshot(harness.model) == before)
  }

  @Test("toggling an unselected finding selects it and the totals and hub estimate follow")
  func togglingAnUnselectedFindingSelectsIt() async throws {
    let harness = makeCleanupHarness()
    let cache = ModuleFixture.cacheFinding()
    let spare = ModuleFixture.spareCacheFinding()
    _ = try #require(await reachReviewing(harness, findings: [cache, spare]))

    harness.model.toggleFinding(spare.id)
    let review = try #require(currentReview(harness.model))
    #expect(review.selectedFindingIDs == [cache.id, spare.id])
    #expect(review.selectedByteTotal == 1_200)
    #expect(review.selectedFileCount == 3)
    #expect(harness.model.hubEstimateBytes == 1_200)
  }

  @Test(
    "toggling a category selects every member when one is unselected, then deselects every member")
  func togglingACategorySelectsAllThenDeselectsAll() async throws {
    let harness = makeCleanupHarness()
    let cache = ModuleFixture.cacheFinding()
    let spare = ModuleFixture.spareCacheFinding()
    _ = try #require(await reachReviewing(harness, findings: [cache, spare]))
    #expect(currentReview(harness.model)?.selectedFindingIDs == [cache.id])

    harness.model.toggleCategory(.userCache)
    #expect(currentReview(harness.model)?.selectedFindingIDs == [cache.id, spare.id])
    #expect(harness.model.hubEstimateBytes == 1_200)

    harness.model.toggleCategory(.userCache)
    let emptied = try #require(currentReview(harness.model))
    #expect(emptied.selectedFindingIDs.isEmpty)
    #expect(emptied.selectedByteTotal == 0)
    #expect(emptied.selectedFileCount == 0)
    #expect(harness.model.hubEstimateBytes == 0)
  }

  @Test("executing an empty selection refuses and touches neither the engine nor the executor")
  func executingAnEmptySelectionRefuses() async throws {
    let harness = makeCleanupHarness()
    let cache = ModuleFixture.cacheFinding()
    _ = try #require(await reachReviewing(harness, findings: [cache]))
    harness.model.toggleFinding(cache.id)
    let before = snapshot(harness.model)

    let refusal = harness.model.executeSelection(permanentConfirmation: nil)
    #expect(refusal == .emptySelection)
    await settleBriefly()
    #expect(snapshot(harness.model) == before)
    #expect(harness.engine.planCallCount == 0)
    #expect(harness.executor.executeCallCount == 0)
  }
}
