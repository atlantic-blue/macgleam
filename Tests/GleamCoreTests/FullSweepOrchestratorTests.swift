import Foundation
import GleamCore
import Testing
import os

/// The Full Sweep: three jobs at once, one answer, and no policy of its own.
///
/// The property that matters most is the one about what it cannot do. A sweep
/// runs without anybody opening a row, so it must never select more than an
/// engine offered and never reach a maintenance task whose warning has to be
/// read. Both are asserted over the whole space rather than over one path.
@Suite("Full Sweep orchestrator")
struct FullSweepOrchestratorTests {

  private func orchestrator(
    _ engines: [FullSweepJob: any GleamEngine]
  ) -> FullSweepOrchestrator {
    FullSweepOrchestrator(engines: engines)
  }

  private func everyJobWorking() -> [FullSweepJob: any GleamEngine] {
    [
      .deepClean: SweepFixture.engine(
        module: .cleanup, findings: [SweepFixture.cache(), SweepFixture.log()]),
      .storageDeclutter: SweepFixture.engine(
        module: .leftovers, findings: [SweepFixture.largeFile()]),
      .performanceBoost: SweepFixture.engine(
        module: .performance, findings: [SweepFixture.maintenance()]),
    ]
  }

  private func collect(
    _ orchestrator: FullSweepOrchestrator
  ) async throws -> SweepOutcome {
    var outcome = SweepOutcome()
    for try await event in orchestrator.scan(SweepFixture.scanContext()) {
      switch event {
      case .job(let job, let event):
        outcome.tagged.append((job, event))
        if case .finding(let finding) = event { outcome.findings.append((job, finding)) }
      case .jobFailed(let job, let reason):
        outcome.failures.append((job, reason))
      case .summary(let summary):
        outcome.summaries.append(summary)
      }
    }
    return outcome
  }

  // MARK: - Running

  @Test("every job runs, and no job runs that has no case in the enum")
  func everyJobRuns() async throws {
    let outcome = try await collect(orchestrator(everyJobWorking()))

    #expect(Set(outcome.tagged.map(\.0)) == Set(FullSweepJob.allCases))
    #expect(outcome.tagged.allSatisfy { FullSweepJob.allCases.contains($0.0) })
  }

  @Test("every event carries the job it came from")
  func everyEventCarriesItsJob() async throws {
    let outcome = try await collect(orchestrator(everyJobWorking()))

    for (job, finding) in outcome.findings {
      #expect(
        FullSweepOrchestrator.job(of: finding.category) == job,
        "a row tagged with another job's name is a row nobody can act on")
    }
  }

  @Test("the jobs run at once rather than one after another")
  func theJobsRunAtOnce() async throws {
    // Each engine waits for the other two to have started before it yields
    // anything. A sweep that ran them in sequence never gets past the first,
    // so this fails by hanging rather than by an assertion, and the timeout
    // is the failure.
    let gate = StartGate(expected: FullSweepJob.allCases.count)
    let engines: [FullSweepJob: any GleamEngine] = [
      .deepClean: SweepFixture.engine(
        module: .cleanup, findings: [SweepFixture.cache()], gate: gate),
      .storageDeclutter: SweepFixture.engine(
        module: .leftovers, findings: [SweepFixture.largeFile()], gate: gate),
      .performanceBoost: SweepFixture.engine(
        module: .performance, findings: [SweepFixture.maintenance()], gate: gate),
    ]

    let outcome = try await collect(orchestrator(engines))

    #expect(outcome.findings.count == 3)
  }

  // MARK: - The summary

  @Test("exactly one summary arrives, and it is the last event")
  func exactlyOneSummaryArrivesLast() async throws {
    var events: [FullSweepEvent] = []
    for try await event in orchestrator(everyJobWorking()).scan(SweepFixture.scanContext()) {
      events.append(event)
    }

    let summaries = events.filter {
      if case .summary = $0 { return true }
      return false
    }
    #expect(summaries.count == 1)
    guard case .summary = events.last else {
      Issue.record("the summary is the answer, so it comes after every job that fed it")
      return
    }
  }

  @Test("the summary's figures are the sum of what the jobs found")
  func theSummaryFiguresAreTheSumOfWhatWasFound() async throws {
    let outcome = try await collect(orchestrator(everyJobWorking()))
    let summary = try #require(outcome.summaries.first)

    #expect(summary.issueCount == 4)
    #expect(
      summary.bytesReclaimable
        == outcome.findings.reduce(UInt64(0)) { $0 + $1.1.byteSize })
  }

  @Test("the summary carries one outcome per job, in the enum's order")
  func theSummaryCarriesOneOutcomePerJob() async throws {
    let outcome = try await collect(orchestrator(everyJobWorking()))
    let summary = try #require(outcome.summaries.first)

    #expect(summary.perJob.map(\.job) == FullSweepJob.allCases)
  }

  // MARK: - One job failing

  @Test("one job failing leaves the others fully usable")
  func oneJobFailingLeavesTheOthersUsable() async throws {
    var engines = everyJobWorking()
    engines[.storageDeclutter] = SweepFixture.engine(
      module: .leftovers, findings: [], failsWith: SweepFixture.Failure())

    let outcome = try await collect(orchestrator(engines))

    #expect(outcome.failures.map(\.0) == [.storageDeclutter])
    #expect(outcome.findings.contains { $0.0 == .deepClean })
    #expect(outcome.findings.contains { $0.0 == .performanceBoost })
    let summary = try #require(outcome.summaries.first)
    #expect(summary.issueCount == 3, "the two jobs that worked are counted in full")
  }

  @Test("a failed job is named in the summary with a plain sentence")
  func aFailedJobIsNamedInTheSummary() async throws {
    var engines = everyJobWorking()
    engines[.deepClean] = SweepFixture.engine(
      module: .cleanup, findings: [], failsWith: SweepFixture.Failure())

    let summary = try #require(try await collect(orchestrator(engines)).summaries.first)
    let outcome = try #require(summary.perJob.first { $0.job == .deepClean })

    guard case .failed(let reason) = outcome.outcome else {
      Issue.record("a job that failed is reported as failed rather than as empty")
      return
    }
    #expect(!reason.isEmpty)
    #expect(reason.hasSuffix("."))
  }

  @Test("a job with no engine fails rather than shrinking the sweep silently")
  func aJobWithNoEngineFails() async throws {
    var engines = everyJobWorking()
    engines[.performanceBoost] = nil

    let outcome = try await collect(orchestrator(engines))

    #expect(outcome.failures.map(\.0) == [.performanceBoost])
    let summary = try #require(outcome.summaries.first)
    #expect(summary.perJob.count == FullSweepJob.allCases.count)
  }

  @Test("every job failing still produces one summary saying so")
  func everyJobFailingStillProducesASummary() async throws {
    let engines: [FullSweepJob: any GleamEngine] = Dictionary(
      uniqueKeysWithValues: FullSweepJob.allCases.map { job in
        (
          job,
          SweepFixture.engine(module: .cleanup, findings: [], failsWith: SweepFixture.Failure())
            as any GleamEngine
        )
      })

    let summary = try #require(try await collect(orchestrator(engines)).summaries.first)

    #expect(summary.issueCount == 0)
    #expect(summary.bytesReclaimable == 0)
    #expect(
      summary.perJob.allSatisfy {
        if case .failed = $0.outcome { return true }
        return false
      })
  }

  // MARK: - Planning

  @Test("the combined plan is each engine's own plan, and holds nothing else")
  func theCombinedPlanIsEachEnginesOwn() async throws {
    let engines = everyJobWorking()
    let selection = [SweepFixture.cache(), SweepFixture.largeFile()]

    let plan = try orchestrator(engines).plan(
      selection: selection, context: SweepFixture.planContext())

    #expect(plan.operations.count == selection.count)
    #expect(Set(plan.operations.map(\.findingID)) == Set(selection.map(\.id)))
  }

  @Test("a maintenance task that clears user visible data is unreachable from a sweep")
  func aTaskThatClearsUserVisibleDataIsUnreachable() throws {
    let engines = everyJobWorking()
    let clearing = MaintenanceTask.allCases.filter(\.clearsUserVisibleData)
    #expect(!clearing.isEmpty, "a sweep over no such tasks proves nothing")

    for task in clearing {
      let plan = try orchestrator(engines).plan(
        selection: [SweepFixture.maintenance(task: task)],
        context: SweepFixture.planContext())
      #expect(
        plan.operations.isEmpty,
        """
        \(task.rawValue) needs its warning read, and a Full Sweep runs without \
        anybody opening a row
        """)
    }
  }

  @Test("a maintenance task that clears nothing a person sees is still swept")
  func aTaskThatClearsNothingVisibleIsStillSwept() throws {
    let engines = everyJobWorking()
    let safe = try #require(MaintenanceTask.allCases.first { !$0.clearsUserVisibleData })

    let plan = try orchestrator(engines).plan(
      selection: [SweepFixture.maintenance(task: safe)], context: SweepFixture.planContext())

    #expect(plan.operations.count == 1)
  }

  @Test("a row no job owns contributes nothing")
  func aRowNoJobOwnsContributesNothing() throws {
    let plan = try orchestrator(everyJobWorking()).plan(
      selection: [SweepFixture.finding(category: .malware(signatureIdentifier: "X"))],
      context: SweepFixture.planContext())

    #expect(plan.operations.isEmpty)
  }

  @Test("an empty selection is refused rather than planned as nothing")
  func anEmptySelectionIsRefused() {
    #expect(throws: PlanningError.emptySelection) {
      _ = try orchestrator(everyJobWorking()).plan(
        selection: [], context: SweepFixture.planContext())
    }
  }

  @Test("a row from another session is refused, so a stale review plans nothing")
  func aRowFromAnotherSessionIsRefused() {
    #expect(throws: (any Error).self) {
      _ = try orchestrator(everyJobWorking()).plan(
        selection: [SweepFixture.cache(sessionID: UUID())],
        context: SweepFixture.planContext())
    }
  }

  @Test("the sweep adds no preselection of its own: what it plans is what was passed")
  func theSweepAddsNoPreselectionOfItsOwn() throws {
    // Every row the engines found, including the ones no engine preselected.
    // The orchestrator plans exactly what it is handed, so the review is the
    // only thing that decides and it can only ever narrow the set.
    let engines = everyJobWorking()
    let unselected = SweepFixture.largeFile()

    let plan = try orchestrator(engines).plan(
      selection: [unselected], context: SweepFixture.planContext())

    #expect(plan.operations.count == 1)
    #expect(!unselected.isPreselected, "the row was never preselected and is still planned")
  }
}

struct SweepOutcome {
  var tagged: [(FullSweepJob, ScanEvent)] = []
  var findings: [(FullSweepJob, Finding)] = []
  var failures: [(FullSweepJob, String)] = []
  var summaries: [FullSweepSummary] = []
}
