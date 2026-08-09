import CleanupModule
import Foundation
import GleamCore
import Testing

@MainActor
@Suite("Cleanup module degraded notices")
struct CleanupModuleDegradedNoticesTests {

  @Test("the provider's unavailable sentences become the banner for the scan, in order")
  func providerSentencesBecomeTheBanner() async {
    let harness = makeCleanupHarness(degradedState: ModuleFixture.withoutFullDiskAccess)
    let feed = await beginScan(harness)
    #expect(feed.context.hasFullDiskAccess == false)
    await expectEventually("the banner carries the provider sentences") {
      harness.model.degradedNotices == [
        ModuleFixture.mailUnavailableSentence,
        ModuleFixture.trashUnavailableSentence,
      ]
    }
    #expect(harness.sessions.recordedScanRequests.first?.hasFullDiskAccess == false)
  }

  @Test("distinct degraded scan events append after the provider's sentences in arrival order")
  func distinctDegradedEventsAppendInArrivalOrder() async {
    let harness = makeCleanupHarness(degradedState: ModuleFixture.withoutFullDiskAccess)
    let feed = await beginScan(harness)
    feed.send(
      .degraded(unavailable: "Safari caches were skipped."),
      .degraded(unavailable: "Mail rules were skipped.")
    )
    await expectEventually("the banner carries all four sentences") {
      harness.model.degradedNotices == [
        ModuleFixture.mailUnavailableSentence,
        ModuleFixture.trashUnavailableSentence,
        "Safari caches were skipped.",
        "Mail rules were skipped.",
      ]
    }
  }

  @Test("a repeated degraded sentence appears in the banner once")
  func aRepeatedDegradedSentenceAppearsOnce() async {
    let harness = makeCleanupHarness(degradedState: ModuleFixture.withoutFullDiskAccess)
    let feed = await beginScan(harness)
    feed.send(
      .degraded(unavailable: ModuleFixture.mailUnavailableSentence),
      .degraded(unavailable: "Safari caches were skipped."),
      .degraded(unavailable: "Safari caches were skipped.")
    )
    await expectEventually("the new sentence arrives") {
      harness.model.degradedNotices.contains("Safari caches were skipped.")
    }
    await settleBriefly()
    #expect(
      harness.model.degradedNotices == [
        ModuleFixture.mailUnavailableSentence,
        ModuleFixture.trashUnavailableSentence,
        "Safari caches were skipped.",
      ])
  }

  @Test("an empty degraded sentence never reaches the banner")
  func anEmptyDegradedSentenceNeverReachesTheBanner() async {
    let harness = makeCleanupHarness(degradedState: ModuleFixture.withoutFullDiskAccess)
    let feed = await beginScan(harness)
    feed.send(.degraded(unavailable: ""), .degraded(unavailable: "Safari caches were skipped."))
    await expectEventually("the non empty sentence arrives") {
      harness.model.degradedNotices.contains("Safari caches were skipped.")
    }
    #expect(!harness.model.degradedNotices.contains(""))
    #expect(harness.model.degradedNotices.allSatisfy { !$0.isEmpty })
  }

  @Test("the next scan replaces the banner with the provider's current state")
  func theNextScanReplacesTheBanner() async {
    let harness = makeCleanupHarness(degradedState: ModuleFixture.withoutFullDiskAccess)
    let feed = await beginScan(harness)
    feed.send(.degraded(unavailable: "Safari caches were skipped."))
    await expectEventually("the first banner arrives") {
      !harness.model.degradedNotices.isEmpty
    }
    feed.send(.phase(.settling), .progress(makeCounters(50, 0, 0)))
    feed.finish()
    await expectEventually("the first scan lands") {
      harness.model.state == .cleanSweep(filesChecked: 50)
    }

    harness.degraded.set(ModuleFixture.fullAccess)
    let secondFeed = await beginScan(harness)
    #expect(secondFeed.context.hasFullDiskAccess)
    await expectEventually("the banner is replaced and emptied") {
      harness.model.degradedNotices.isEmpty && scanProgress(harness.model) != nil
    }
  }

  @Test("the banner is empty exactly when nothing was skipped")
  func theBannerIsEmptyWhenNothingWasSkipped() async throws {
    let harness = makeCleanupHarness(degradedState: ModuleFixture.fullAccess)
    _ = try #require(
      await reachReviewing(harness, findings: [ModuleFixture.cacheFinding()]))
    #expect(harness.model.degradedNotices.isEmpty)
  }
}
