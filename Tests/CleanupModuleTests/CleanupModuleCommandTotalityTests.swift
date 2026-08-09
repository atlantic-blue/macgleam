import CleanupModule
import Foundation
import GleamCore
import Testing

/// C38: every command in every state either performs its named transition or
/// leaves the state identical. These suites walk the whole matrix, one state
/// per test, foreign commands asserted as the identity.
@MainActor
@Suite("Cleanup module command totality")
struct CleanupModuleCommandTotalityTests {

  @Test("every command outside its table is the identity in idle")
  func foreignCommandsAreTheIdentityInIdle() async {
    let harness = makeCleanupHarness()
    #expect(harness.model.permanentDeletionScope() == nil)
    await expectCommandsAreIdentity(
      [
        .toggleUnknownFinding, .toggleCategory, .executeSelection,
        .cancelScan, .cancelExecution, .acknowledgeResult,
      ],
      on: harness)
  }

  @Test(
    "every command outside its table is the identity while scanning, including another startScan")
  func foreignCommandsAreTheIdentityWhileScanning() async {
    let harness = makeCleanupHarness()
    let feed = await beginScan(harness)
    feed.send(.phase(.indeterminate), .progress(makeCounters(10, 500, 1)))
    await expectEventually("the model is scanning with counters") {
      scanProgress(harness.model)?.counters.bytesReclaimable == 500
    }
    #expect(harness.model.permanentDeletionScope() == nil)
    await expectCommandsAreIdentity(
      [
        .startScan, .toggleUnknownFinding, .toggleCategory,
        .executeSelection, .cancelExecution, .acknowledgeResult,
      ],
      on: harness)
    #expect(harness.sessions.minted.count == 1)
  }

  @Test("every command outside its table is the identity while reviewing")
  func foreignCommandsAreTheIdentityWhileReviewing() async throws {
    let harness = makeCleanupHarness()
    _ = try #require(
      await reachReviewing(harness, findings: [ModuleFixture.cacheFinding()]))
    await expectCommandsAreIdentity(
      [.toggleUnknownFinding, .cancelScan, .cancelExecution, .acknowledgeResult],
      on: harness)
  }

  @Test("every command outside its table is the identity while executing")
  func foreignCommandsAreTheIdentityWhileExecuting() async throws {
    let harness = makeCleanupHarness()
    _ = try #require(
      await reachExecuting(harness, findings: [ModuleFixture.cacheFinding()]))
    #expect(harness.model.permanentDeletionScope() == nil)
    await expectCommandsAreIdentity(
      [
        .startScan, .toggleUnknownFinding, .toggleCategory,
        .executeSelection, .cancelScan, .acknowledgeResult,
      ],
      on: harness)
    #expect(harness.sessions.minted.count == 1)
  }

  @Test("every command outside its table is the identity in the result")
  func foreignCommandsAreTheIdentityInTheResult() async throws {
    let harness = makeCleanupHarness()
    _ = try #require(await reachResult(harness))
    #expect(harness.model.permanentDeletionScope() == nil)
    await expectCommandsAreIdentity(
      [
        .toggleUnknownFinding, .toggleCategory, .executeSelection,
        .cancelScan, .cancelExecution,
      ],
      on: harness)
  }

  @Test("every command outside its table is the identity in the clean sweep")
  func foreignCommandsAreTheIdentityInTheCleanSweep() async {
    let harness = makeCleanupHarness()
    await reachCleanSweep(harness)
    #expect(harness.model.permanentDeletionScope() == nil)
    await expectCommandsAreIdentity(
      [
        .toggleUnknownFinding, .toggleCategory, .executeSelection,
        .cancelScan, .cancelExecution,
      ],
      on: harness)
  }

  @Test("startScan from reviewing discards the findings and selection and mints a fresh session")
  func startScanFromReviewingBeginsAFreshSession() async throws {
    let harness = makeCleanupHarness()
    _ = try #require(
      await reachReviewing(
        harness,
        findings: [ModuleFixture.cacheFinding(), ModuleFixture.logFinding()]))

    let secondFinding = ModuleFixture.logFinding(sessionID: ModuleFixture.sessionB)
    harness.model.startScan()
    let feed = await harness.engine.nextScanFeed()
    #expect(feed.context.sessionID == ModuleFixture.sessionB)
    feed.send(
      .phase(.indeterminate),
      .finding(secondFinding),
      .progress(makeCounters(10, 300, 1)),
      .phase(.settling)
    )
    feed.finish()

    await expectEventually("the second review arrives") {
      currentReview(harness.model)?.sessionID == ModuleFixture.sessionB
    }
    let review = try #require(currentReview(harness.model))
    #expect(review.categories.map(\.category) == [.log])
    #expect(review.categories.first?.findings == [secondFinding])
    #expect(harness.sessions.minted == [ModuleFixture.sessionA, ModuleFixture.sessionB])
  }

  @Test("startScan from the result begins a new scan")
  func startScanFromTheResultBeginsANewScan() async throws {
    let harness = makeCleanupHarness()
    _ = try #require(await reachResult(harness))
    let feed = await beginScan(harness)
    #expect(feed.context.sessionID == ModuleFixture.sessionB)
    await expectEventually("the model is scanning again") {
      scanProgress(harness.model)?.sessionID == ModuleFixture.sessionB
    }
  }

  @Test("startScan from the clean sweep begins a new scan")
  func startScanFromTheCleanSweepBeginsANewScan() async {
    let harness = makeCleanupHarness()
    await reachCleanSweep(harness)
    let feed = await beginScan(harness)
    #expect(feed.context.sessionID == ModuleFixture.sessionB)
    await expectEventually("the model is scanning again") {
      scanProgress(harness.model)?.sessionID == ModuleFixture.sessionB
    }
  }
}
