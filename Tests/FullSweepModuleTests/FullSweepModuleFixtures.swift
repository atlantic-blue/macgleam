import Foundation
import FullSweepModule
import GleamCore
import Testing
import os

/// Fixtures for the Smart Care surface. The orchestrator is a double: it is
/// proved in its own suite, and what this suite is about is what the surface
/// does with what it says.
enum SweepModuleFixture {
  static let sessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!
  static let instant = Date(timeIntervalSince1970: 1_726_000_000)

  static func path(_ value: String) -> AbsolutePath {
    AbsolutePath(normalising: value)
  }

  static func finding(
    category: FindingCategory,
    path value: String,
    bytes: UInt64,
    isPreselected: Bool
  ) -> Finding {
    Finding(
      id: UUID(),
      sessionID: sessionID,
      category: category,
      entries: [PathEntry(path: path(value), allocatedBytes: bytes)],
      risk: .safe,
      explanation: "A fixture row.",
      isPreselected: isPreselected)
  }

  static func cache() -> Finding {
    finding(
      category: .userCache, path: "/Users/gleam/Library/Caches/one", bytes: 1_024,
      isPreselected: true)
  }

  static func log() -> Finding {
    finding(
      category: .log, path: "/Users/gleam/Library/Logs/two", bytes: 2_048, isPreselected: true)
  }

  static func largeFile() -> Finding {
    finding(
      category: .largeFile, path: "/Users/gleam/Movies/film.mov", bytes: 8_192,
      isPreselected: false)
  }
}

/// An orchestrator that yields what the test scripted, tagged by job, and
/// records what it was asked to plan.
final class ScriptedOrchestrator: FullSweepOrchestrating, @unchecked Sendable {
  private let findings: [FullSweepJob: [Finding]]
  private let failing: Set<FullSweepJob>
  private let holdsOpen: Bool
  private let reading: AbsolutePath?
  private let recorded = OSAllocatedUnfairLock(initialState: [[UUID]]())

  init(
    findings: [FullSweepJob: [Finding]],
    failing: Set<FullSweepJob> = [],
    holdsOpen: Bool = false,
    reading: AbsolutePath? = nil
  ) {
    self.findings = findings
    self.failing = failing
    self.holdsOpen = holdsOpen
    self.reading = reading
  }

  var plannedSelections: [[UUID]] { recorded.withLock { $0 } }

  func scan(_ context: ScanContext) -> AsyncThrowingStream<FullSweepEvent, Error> {
    AsyncThrowingStream { continuation in
      let work = Task {
        emit(into: continuation, sessionID: context.sessionID)
      }
      continuation.onTermination = { _ in work.cancel() }
    }
  }

  private func emit(
    into continuation: AsyncThrowingStream<FullSweepEvent, Error>.Continuation,
    sessionID: UUID
  ) {
    var bytes: UInt64 = 0
    var issues: UInt32 = 0
    if let reading {
      continuation.yield(.job(.deepClean, .reading(reading)))
    }
    for job in FullSweepJob.allCases {
      if failing.contains(job) {
        continuation.yield(.jobFailed(job, reason: "\(job.title) could not be run."))
        continue
      }
      for finding in findings[job] ?? [] {
        bytes += finding.byteSize
        issues += 1
        continuation.yield(
          .job(
            job,
            .finding(
              Finding(
                id: finding.id,
                sessionID: sessionID,
                category: finding.category,
                entries: finding.entries,
                risk: finding.risk,
                explanation: finding.explanation,
                isPreselected: finding.isPreselected))))
      }
    }
    guard !holdsOpen else { return }
    continuation.yield(
      .summary(
        FullSweepSummary(
          bytesReclaimable: bytes,
          issueCount: issues,
          perJob: FullSweepJob.allCases.map { job in
            FullSweepJobOutcome(
              job: job,
              outcome: failing.contains(job)
                ? .failed(reason: "\(job.title) could not be run.")
                : .completed(
                  findingCount: UInt32((findings[job] ?? []).count),
                  bytes: (findings[job] ?? []).reduce(0) { $0 + $1.byteSize }))
          })))
    continuation.finish()
  }

  func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan {
    recorded.withLock { $0.append(selection.map(\.id)) }
    return OperationPlan(
      id: UUID(),
      sessionID: context.sessionID,
      operations: selection.compactMap { finding in
        guard let target = finding.paths.first else { return nil }
        return GleamCore.Operation(
          id: UUID(), findingID: finding.id, kind: .moveToTrash(target: target),
          privilege: .user)
      },
      totalBytes: selection.reduce(0) { $0 + $1.byteSize },
      permanentDeletionConfirmation: nil)
  }
}

final class SweepExecutor: PlanExecuting, @unchecked Sendable {
  func execute(_ plan: OperationPlan) -> AsyncStream<ExecutionEvent> {
    AsyncStream { continuation in
      var results: [(operationID: UUID, result: OperationResult)] = []
      for operation in plan.operations {
        continuation.yield(.operationStarted(operationID: operation.id))
        let result = OperationResult.completed(bytesReclaimed: 64)
        continuation.yield(.operationFinished(operationID: operation.id, result: result))
        results.append((operationID: operation.id, result: result))
      }
      continuation.yield(
        .planCompleted(
          ExecutionReport(
            planID: plan.id,
            results: results,
            bytesReclaimed: UInt64(plan.operations.count) * 64,
            startedAt: SweepModuleFixture.instant,
            finishedAt: SweepModuleFixture.instant)))
      continuation.finish()
    }
  }
}

struct SweepSessions: FullSweepSessionProviding {
  func makeScanContext(settings: Settings, hasFullDiskAccess: Bool) async -> ScanContext {
    ScanContext(
      sessionID: SweepModuleFixture.sessionID,
      fileSystem: InMemoryFileSystem(),
      rules: RuleCatalog(
        version: RuleCatalogVersion(value: 1),
        signature: Data(),
        cleanupRules: [],
        adwareRules: [],
        denylist: Denylist(patterns: [])),
      settings: settings,
      hasFullDiskAccess: hasFullDiskAccess)
  }

  func makePlanContext(sessionID: UUID, settings: Settings) async -> PlanContext {
    PlanContext(
      sessionID: sessionID,
      rules: RuleCatalog(
        version: RuleCatalogVersion(value: 1),
        signature: Data(),
        cleanupRules: [],
        adwareRules: [],
        denylist: Denylist(patterns: [])),
      settings: settings,
      ownership: HomeDirectoryOwnershipPolicy())
  }
}

actor SweepSettingsStore: SettingsStoring {
  private var settings = Settings.defaults
  func load() async -> Settings { settings }
  func save(_ updated: Settings) async throws { settings = updated }
  nonisolated func updates() -> AsyncStream<Settings> { AsyncStream { $0.finish() } }
}

@MainActor
struct SweepHarness {
  let orchestrator: ScriptedOrchestrator
  let model: FullSweepModuleModel
}

@MainActor
func makeSweepHarness(
  findings: [FullSweepJob: [Finding]],
  failing: Set<FullSweepJob> = [],
  holdsOpen: Bool = false,
  reading: AbsolutePath? = nil
) -> SweepHarness {
  let orchestrator = ScriptedOrchestrator(
    findings: findings, failing: failing, holdsOpen: holdsOpen, reading: reading)
  return SweepHarness(
    orchestrator: orchestrator,
    model: FullSweepModuleModel(
      orchestrator: orchestrator,
      executor: SweepExecutor(),
      settings: SweepSettingsStore(),
      sessions: SweepSessions()))
}

@MainActor
func reviewingSweep(_ model: FullSweepModuleModel) -> FullSweepReview? {
  guard case .reviewing(let review) = model.state else { return nil }
  return review
}

@MainActor
// A scan now runs at utility priority, below the interface, which is what
// keeps the machine usable while it reads. Under a loaded parallel test run a
// utility task can wait a while for a core, so these helpers wait in seconds
// rather than in fractions of one. Each returns the moment its condition
// holds, so waiting longer costs a fast machine nothing.
func settleSweep(_ harness: SweepHarness) async {
  // It waits for the state to CHANGE and then settle, never for a set of
  // states it might already be in. Both traps are real: idle is where a sweep
  // starts, and reviewing is where a run starts, so a wait that stops at
  // either can stop before the work it is waiting for began.
  let before = harness.model.state
  for _ in 0..<10_000 {
    await Task.yield()
    try? await Task.sleep(nanoseconds: 1_000_000)
    let now = harness.model.state
    guard now != before else { continue }
    switch now {
    case .idle, .reviewing, .result, .cleanSweep:
      return
    case .scanning, .executing:
      continue
    }
  }
}

@MainActor
func expectEventuallySweep(
  _ what: String,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ condition: @MainActor () -> Bool
) async {
  for _ in 0..<10_000 {
    if condition() { return }
    await Task.yield()
    try? await Task.sleep(nanoseconds: 1_000_000)
  }
  Issue.record("\(what) never happened", sourceLocation: sourceLocation)
}
