import Foundation
import GleamCore
import ProtectionModule
import Testing
import os

/// The Protection module's lifecycle, and the two rules that separate it from
/// every other module: what arrives ticked, and what cannot run without a
/// confirmation naming its exact counts.
@MainActor
@Suite("Protection module")
struct ProtectionModuleTests {

  // MARK: - The scan

  @Test("a scan with nothing found lands on all clear, saying what was checked")
  func aScanWithNothingFoundLandsOnAllClear() async throws {
    let harness = makeProtectionHarness(findings: [])

    harness.model.startScan()
    await settle(harness)

    guard case .allClear(let filesChecked) = harness.model.state else {
      Issue.record("an empty result is a reward state, never a blank list")
      return
    }
    #expect(filesChecked == ProtectionModuleFixture.filesSeen)
  }

  @Test("threats arrive ticked and traces never do")
  func threatsArriveTickedAndTracesNeverDo() async throws {
    let harness = makeProtectionHarness(
      findings: [
        ProtectionModuleFixture.malware(),
        ProtectionModuleFixture.adware(),
        ProtectionModuleFixture.history(),
      ])

    harness.model.startScan()
    await settle(harness)

    let review = try #require(reviewing(harness.model))
    #expect(review.threats.count == 2)
    #expect(review.traces.count == 1)
    #expect(review.selectedFindingIDs == Set(review.threats.map(\.id)))
  }

  @Test("a scan that fails says so and leaves the module idle")
  func aScanThatFailsSaysSo() async throws {
    let harness = makeProtectionHarness(findings: [], failsWith: ProtectionModuleFixture.Failure())

    harness.model.startScan()
    await settleToIdle(harness)

    #expect(harness.model.state == .idle)
    #expect(harness.model.failureNotice != nil)
  }

  @Test("a degraded notice from the engine reaches the banner once")
  func aDegradedNoticeReachesTheBannerOnce() async throws {
    let harness = makeProtectionHarness(
      findings: [ProtectionModuleFixture.adware()],
      degraded: ["Signatures were not checked.", "Signatures were not checked."])

    harness.model.startScan()
    await settle(harness)

    #expect(harness.model.degradedNotices == ["Signatures were not checked."])
  }

  // MARK: - The selection

  @Test("ticking a trace and running it without a confirmation refuses, naming the scope")
  func runningATraceWithoutAConfirmationRefuses() async throws {
    let harness = makeProtectionHarness(
      findings: [ProtectionModuleFixture.adware(), ProtectionModuleFixture.history()])
    harness.model.startScan()
    await settle(harness)
    let review = try #require(reviewing(harness.model))
    let trace = try #require(review.traces.first)
    harness.model.toggleFinding(trace.id)

    let refusal = harness.model.executeSelection(clearingConfirmation: nil)

    guard case .tracesUnconfirmed(let scope) = refusal else {
      Issue.record("clearing is permanent, so it needs the counts agreed first")
      return
    }
    #expect(scope.fileCount == UInt32(trace.paths.count))
    #expect(scope.byteTotal == trace.byteSize)
    #expect(reviewing(harness.model) != nil, "a refusal changes nothing")
    #expect(harness.executor.executed.isEmpty)
  }

  @Test("a confirmation whose numbers do not match is refused")
  func aConfirmationWhoseNumbersDoNotMatchIsRefused() async throws {
    let harness = makeProtectionHarness(
      findings: [ProtectionModuleFixture.history()])
    harness.model.startScan()
    await settle(harness)
    let review = try #require(reviewing(harness.model))
    harness.model.toggleFinding(try #require(review.traces.first).id)

    let refusal = harness.model.executeSelection(
      clearingConfirmation: PermanentDeletionConfirmation(
        fileCount: 99, byteTotal: 99, confirmedAt: ProtectionModuleFixture.instant))

    guard case .confirmationMismatch = refusal else {
      Issue.record("a confirmation that names other numbers is evidence of nothing")
      return
    }
    #expect(harness.executor.executed.isEmpty)
  }

  @Test("threats alone need no confirmation, because containment is reversible")
  func threatsAloneNeedNoConfirmation() async throws {
    let harness = makeProtectionHarness(findings: [ProtectionModuleFixture.adware()])
    harness.model.startScan()
    await settle(harness)

    #expect(harness.model.executeSelection(clearingConfirmation: nil) == nil)
    await settle(harness)
    #expect(harness.executor.executed.count == 1)
  }

  @Test("an empty selection is refused rather than run as nothing")
  func anEmptySelectionIsRefused() async throws {
    let harness = makeProtectionHarness(findings: [ProtectionModuleFixture.adware()])
    harness.model.startScan()
    await settle(harness)
    let review = try #require(reviewing(harness.model))
    for finding in review.threats {
      harness.model.toggleFinding(finding.id)
    }

    #expect(harness.model.executeSelection(clearingConfirmation: nil) == .emptySelection)
    #expect(harness.executor.executed.isEmpty)
  }

  @Test("an unknown identifier changes nothing")
  func anUnknownIdentifierChangesNothing() async throws {
    let harness = makeProtectionHarness(findings: [ProtectionModuleFixture.adware()])
    harness.model.startScan()
    await settle(harness)
    let before = reviewing(harness.model)

    harness.model.toggleFinding(UUID())

    #expect(reviewing(harness.model) == before)
  }

  // MARK: - The result

  @Test("the result counts what was contained apart from what was cleared")
  func theResultCountsContainedApartFromCleared() async throws {
    let harness = makeProtectionHarness(
      findings: [ProtectionModuleFixture.adware(), ProtectionModuleFixture.history()])
    harness.model.startScan()
    await settle(harness)
    let review = try #require(reviewing(harness.model))
    let trace = try #require(review.traces.first)
    harness.model.toggleFinding(trace.id)

    #expect(
      harness.model.executeSelection(
        clearingConfirmation: PermanentDeletionConfirmation(
          fileCount: UInt32(trace.paths.count),
          byteTotal: trace.byteSize,
          confirmedAt: ProtectionModuleFixture.instant)) == nil)
    await settle(harness)

    guard case .result(let summary) = harness.model.state else {
      Issue.record("a run ends on a result")
      return
    }
    #expect(summary.containedCount == 1)
    #expect(
      summary.clearedCount == 1,
      "one of these is reversible and the other is not, so they are counted apart")
  }

  @Test("acknowledging a result returns the module to idle")
  func acknowledgingAResultReturnsToIdle() async throws {
    let harness = makeProtectionHarness(findings: [ProtectionModuleFixture.adware()])
    harness.model.startScan()
    await settle(harness)
    _ = harness.model.executeSelection(clearingConfirmation: nil)
    await settle(harness)

    harness.model.acknowledgeResult()

    #expect(harness.model.state == .idle)
  }

  @Test("a denylisted skip is named in the result rather than reported as a failure")
  func aDenylistedSkipIsNamedInTheResult() async throws {
    let harness = makeProtectionHarness(
      findings: [ProtectionModuleFixture.adware()], skipsEverything: true)
    harness.model.startScan()
    await settle(harness)
    _ = harness.model.executeSelection(clearingConfirmation: nil)
    await settle(harness)

    guard case .result(let summary) = harness.model.state else {
      Issue.record("a run ends on a result")
      return
    }
    #expect(summary.containedCount == 0)
    #expect(summary.failures.isEmpty, "the safety system working is not a failure")
    #expect(summary.skippedDenylistedNames.count == 1)
  }

  // MARK: - The lifecycle

  @Test("a scan cannot start while one is running")
  func aScanCannotStartWhileOneIsRunning() async throws {
    let harness = makeProtectionHarness(findings: [ProtectionModuleFixture.adware()])
    harness.model.startScan()
    harness.model.startScan()
    await settle(harness)

    #expect(harness.engine.scanCount == 1)
  }

  @Test("cancelling a scan returns to idle and keeps nothing")
  func cancellingAScanReturnsToIdle() async throws {
    let harness = makeProtectionHarness(
      findings: [ProtectionModuleFixture.adware()], holdsOpen: true)
    harness.model.startScan()
    await expectEventually("the scan starts") { scanning(harness.model) }

    harness.model.cancelScan()

    #expect(harness.model.state == .idle)
  }
}
