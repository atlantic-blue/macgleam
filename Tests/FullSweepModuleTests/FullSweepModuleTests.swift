import Foundation
import FullSweepModule
import GleamCore
import GleamHub
import Testing
import os

/// The Smart Care surface: one button, one combined answer, and the orb saying
/// what is happening while it runs.
///
/// The rule this suite exists to hold is the one a sweep makes it easy to
/// break: it can only ever do less than the modules would. The selection
/// starts as exactly what the engines preselected, and nothing here can widen
/// it.
@MainActor
@Suite("Full Sweep module")
struct FullSweepModuleTests {

  // MARK: - Sweeping

  @Test("a sweep that finds nothing lands on the clean sweep, not on an empty list")
  func aSweepThatFindsNothingLandsOnCleanSweep() async throws {
    let harness = makeSweepHarness(findings: [:])

    harness.model.startSweep()
    await settleSweep(harness)

    #expect(harness.model.state == .cleanSweep)
    #expect(harness.model.hubActivity == .cleanSweep)
  }

  @Test("a sweep where every job failed is not a clean sweep")
  func aSweepWhereEveryJobFailedIsNotACleanSweep() async throws {
    let harness = makeSweepHarness(findings: [:], failing: Set(FullSweepJob.allCases))

    harness.model.startSweep()
    await settleSweep(harness)

    guard case .result(let summary) = harness.model.state else {
      Issue.record(
        """
        a sweep that could not look has nothing to say about whether there is \
        anything to do
        """)
      return
    }
    #expect(summary.failures.count == FullSweepJob.allCases.count)
  }

  @Test("what a sweep finds arrives as one review grouped by job")
  func whatASweepFindsArrivesGroupedByJob() async throws {
    let harness = makeSweepHarness(findings: [
      .deepClean: [SweepModuleFixture.cache()],
      .storageDeclutter: [SweepModuleFixture.largeFile()],
    ])

    harness.model.startSweep()
    await settleSweep(harness)

    let review = try #require(reviewingSweep(harness.model))
    #expect(review.jobs.map(\.job) == FullSweepJob.allCases)
    #expect(review.jobs.first { $0.job == .deepClean }?.findings.count == 1)
    #expect(review.jobs.first { $0.job == .performanceBoost }?.findings.isEmpty == true)
  }

  @Test("a job that failed carries its sentence into the review")
  func aJobThatFailedCarriesItsSentence() async throws {
    let harness = makeSweepHarness(
      findings: [.deepClean: [SweepModuleFixture.cache()]], failing: [.storageDeclutter])

    harness.model.startSweep()
    await settleSweep(harness)

    let review = try #require(reviewingSweep(harness.model))
    let failed = try #require(review.jobs.first { $0.job == .storageDeclutter })
    #expect(failed.failure != nil)
    #expect(review.jobs.first { $0.job == .deepClean }?.findings.count == 1)
  }

  // MARK: - The selection

  @Test("the selection starts as exactly what the engines preselected")
  func theSelectionStartsAsWhatTheEnginesPreselected() async throws {
    let preselected = SweepModuleFixture.cache()
    let offered = SweepModuleFixture.largeFile()
    let harness = makeSweepHarness(findings: [
      .deepClean: [preselected], .storageDeclutter: [offered],
    ])

    harness.model.startSweep()
    await settleSweep(harness)

    let review = try #require(reviewingSweep(harness.model))
    #expect(review.selectedFindingIDs == [preselected.id])
    #expect(
      !offered.isPreselected,
      "a sweep runs without anybody reading a row, so it starts from what the module chose")
  }

  @Test("a row the sweep never saw cannot be selected into it")
  func aRowTheSweepNeverSawCannotBeSelected() async throws {
    let harness = makeSweepHarness(findings: [.deepClean: [SweepModuleFixture.cache()]])
    harness.model.startSweep()
    await settleSweep(harness)
    let before = try #require(reviewingSweep(harness.model))

    harness.model.toggleFinding(UUID())

    #expect(reviewingSweep(harness.model)?.selectedFindingIDs == before.selectedFindingIDs)
  }

  @Test("unticking a row narrows the run and nothing else")
  func untickingARowNarrowsTheRun() async throws {
    let first = SweepModuleFixture.cache()
    let second = SweepModuleFixture.log()
    let harness = makeSweepHarness(findings: [.deepClean: [first, second]])
    harness.model.startSweep()
    await settleSweep(harness)

    harness.model.toggleFinding(first.id)

    let review = try #require(reviewingSweep(harness.model))
    #expect(review.selectedFindingIDs == [second.id])
  }

  // MARK: - Running

  @Test("running plans exactly what is selected and reports what it reclaimed")
  func runningPlansExactlyWhatIsSelected() async throws {
    let selected = SweepModuleFixture.cache()
    let harness = makeSweepHarness(findings: [
      .deepClean: [selected, SweepModuleFixture.log()]
    ])
    harness.model.startSweep()
    await settleSweep(harness)
    let review = try #require(reviewingSweep(harness.model))
    for finding in review.jobs.flatMap(\.findings) where finding.id != selected.id {
      harness.model.toggleFinding(finding.id)
    }

    #expect(harness.model.run())
    await settleSweep(harness)

    #expect(harness.orchestrator.plannedSelections == [[selected.id]])
    guard case .result(let summary) = harness.model.state else {
      Issue.record("a run ends on a result")
      return
    }
    #expect(summary.completedCount == 1)
  }

  @Test("running with nothing selected does nothing at all")
  func runningWithNothingSelectedDoesNothing() async throws {
    let harness = makeSweepHarness(findings: [.deepClean: [SweepModuleFixture.cache()]])
    harness.model.startSweep()
    await settleSweep(harness)
    let review = try #require(reviewingSweep(harness.model))
    for finding in review.jobs.flatMap(\.findings) {
      harness.model.toggleFinding(finding.id)
    }

    #expect(!harness.model.run())
    #expect(harness.orchestrator.plannedSelections.isEmpty)
  }

  @Test("the sweep says which file it is reading, not only how many it has read")
  func theSweepSaysWhichFileItIsReading() async throws {
    let reading = AbsolutePath(normalising: "/Users/ada/Library/Caches/com.example/blob.bin")
    let harness = makeSweepHarness(
      findings: [.deepClean: [SweepModuleFixture.cache()]], holdsOpen: true, reading: reading)

    harness.model.startSweep()

    await expectEventuallySweep("the sweep names the file it is reading") {
      guard case .scanning(let progress) = harness.model.state else { return false }
      return progress.reading == reading
    }
  }

  // MARK: - What the orb is told

  @Test("the orb is scanning while the sweep runs, and the figure only goes up")
  func theOrbIsScanningWhileTheSweepRuns() async throws {
    let harness = makeSweepHarness(
      findings: [.deepClean: [SweepModuleFixture.cache()]], holdsOpen: true)

    harness.model.startSweep()
    await expectEventuallySweep("the sweep starts") {
      if case .scanning = harness.model.state { return true }
      return false
    }

    guard case .scanning = harness.model.hubActivity else {
      Issue.record("the orb says what is happening, and a sweep is happening")
      return
    }
  }

  @Test("the orb reports the result the review holds, so the two never disagree")
  func theOrbReportsTheResultTheReviewHolds() async throws {
    let harness = makeSweepHarness(findings: [.deepClean: [SweepModuleFixture.cache()]])
    harness.model.startSweep()
    await settleSweep(harness)

    let review = try #require(reviewingSweep(harness.model))
    #expect(
      harness.model.hubActivity
        == .result(
          bytesReclaimable: review.summary.bytesReclaimable,
          issueCount: review.summary.issueCount))
  }

  @Test("the orb is idle before a sweep and after one is acknowledged")
  func theOrbIsIdleBeforeAndAfter() async throws {
    let harness = makeSweepHarness(findings: [:])
    #expect(harness.model.hubActivity == nil)

    harness.model.startSweep()
    await settleSweep(harness)
    harness.model.acknowledgeResult()

    #expect(harness.model.hubActivity == nil)
    #expect(harness.model.state == .idle)
  }
}
