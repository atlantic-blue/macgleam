import CleanupModule
import Foundation
import GleamCore
import Testing

/// C38 after the s2e amendment: a category is a group of findings, so its byte
/// total and path count are sums across the group, selection stays per finding
/// identifier, and a category toggle is all or nothing over the whole group.
@MainActor
@Suite("Cleanup module category totals")
struct CleanupModuleCategoryTotalsTests {

  /// Three user cache findings, 1,700 bytes over four paths, of which the
  /// 200 byte spare arrives unselected. One log finding, 300 bytes, one path.
  static func batchedFindings() -> [Finding] {
    [
      ModuleFixture.cacheFinding(),
      ModuleFixture.spareCacheFinding(),
      ModuleFixture.extraCacheFinding(),
      ModuleFixture.logFinding(),
    ]
  }

  static func userCacheOnly() -> [Finding] {
    [
      ModuleFixture.cacheFinding(),
      ModuleFixture.spareCacheFinding(),
      ModuleFixture.extraCacheFinding(),
    ]
  }

  @Test("a category's byte total sums across every finding of that category")
  func categoryByteTotalSumsAcrossItsFindings() async throws {
    let harness = makeCleanupHarness()
    let review = try #require(await reachReviewing(harness, findings: Self.batchedFindings()))

    let userCache = try #require(review.categories.first { $0.category == .userCache })
    #expect(userCache.findings.count == 3)
    #expect(userCache.byteTotal == 1_700)

    let log = try #require(review.categories.first { $0.category == .log })
    #expect(log.byteTotal == 300)
  }

  @Test("a category's path count sums across every finding of that category")
  func categoryPathCountSumsAcrossItsFindings() async throws {
    let harness = makeCleanupHarness()
    let review = try #require(await reachReviewing(harness, findings: Self.batchedFindings()))

    let userCache = try #require(review.categories.first { $0.category == .userCache })
    #expect(userCache.pathCount == 4)

    let log = try #require(review.categories.first { $0.category == .log })
    #expect(log.pathCount == 1)
  }

  @Test("a category appears exactly once however many findings it spans")
  func aCategoryAppearsExactlyOnce() async throws {
    let harness = makeCleanupHarness()
    let review = try #require(await reachReviewing(harness, findings: Self.batchedFindings()))

    #expect(review.categories.map(\.category) == [.userCache, .log])
  }

  @Test("a partly selected category is an ordinary state")
  func aPartlySelectedCategoryIsAnOrdinaryState() async throws {
    let harness = makeCleanupHarness()
    let review = try #require(await reachReviewing(harness, findings: Self.userCacheOnly()))

    let userCache = try #require(review.categories.first)
    #expect(userCache.findings.count == 3)
    #expect(
      review.selectedFindingIDs == [
        ModuleFixture.cacheFinding().id, ModuleFixture.extraCacheFinding().id,
      ])
  }

  @Test("the selected totals count only the selected findings of a partly selected category")
  func selectedTotalsCountOnlyTheSelectedFindings() async throws {
    let harness = makeCleanupHarness()
    let review = try #require(await reachReviewing(harness, findings: Self.userCacheOnly()))

    #expect(review.selectedByteTotal == 1_500)
    #expect(review.selectedFileCount == 3)
    #expect(try #require(review.categories.first).byteTotal == 1_700)
  }

  @Test("toggling a partly selected category selects every finding in the group")
  func togglingAPartlySelectedCategorySelectsEveryFinding() async throws {
    let harness = makeCleanupHarness()
    _ = try #require(await reachReviewing(harness, findings: Self.userCacheOnly()))

    harness.model.toggleCategory(.userCache)
    let review = try #require(currentReview(harness.model))
    #expect(review.selectedFindingIDs.count == 3)
    #expect(review.selectedByteTotal == 1_700)
    #expect(review.selectedFileCount == 4)
    #expect(harness.model.hubEstimateBytes == 1_700)
  }

  @Test("toggling a wholly selected category deselects every finding in the group")
  func togglingAWhollySelectedCategoryDeselectsEveryFinding() async throws {
    let harness = makeCleanupHarness()
    _ = try #require(await reachReviewing(harness, findings: Self.userCacheOnly()))

    harness.model.toggleCategory(.userCache)
    harness.model.toggleCategory(.userCache)
    let review = try #require(currentReview(harness.model))
    #expect(review.selectedFindingIDs.isEmpty)
    #expect(review.selectedByteTotal == 0)
    #expect(review.selectedFileCount == 0)
    #expect(harness.model.hubEstimateBytes == 0)
  }

  @Test("a category toggle moves the selected total by the category's whole byte total")
  func aCategoryToggleMovesTheTotalByTheWholeCategory() async throws {
    let harness = makeCleanupHarness()
    let review = try #require(await reachReviewing(harness, findings: Self.batchedFindings()))
    let userCache = try #require(review.categories.first { $0.category == .userCache })
    let before = review.selectedByteTotal

    harness.model.toggleCategory(.userCache)
    let selectedAll = try #require(currentReview(harness.model))
    #expect(selectedAll.selectedByteTotal == before + 200)

    harness.model.toggleCategory(.userCache)
    let selectedNone = try #require(currentReview(harness.model))
    #expect(selectedNone.selectedByteTotal == selectedAll.selectedByteTotal - userCache.byteTotal)
  }
}
