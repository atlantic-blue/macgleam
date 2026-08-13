import Foundation
import GleamCore
import GleamHub
import Observation

/// Mints the per session contexts for a sweep, the same shape every module
/// uses.
public protocol FullSweepSessionProviding: Sendable {
  func makeScanContext(settings: Settings, hasFullDiskAccess: Bool) async -> ScanContext
  func makePlanContext(sessionID: UUID, settings: Settings) async -> PlanContext
}

/// Where a sweep is.
public enum FullSweepModuleState: Sendable, Equatable {
  case idle
  case scanning(FullSweepProgress)
  case reviewing(FullSweepReview)
  case executing(finished: UInt32, total: UInt32)
  case result(FullSweepRunSummary)
  /// The sweep found nothing at all. The reward state, and the reason the
  /// hub has a mood for it: an empty answer here is the good one.
  case cleanSweep
}

/// What a sweep has found so far, per job, while it runs.
public struct FullSweepProgress: Sendable, Equatable {
  public let bytesReclaimable: UInt64
  public let issueCount: UInt32
  public let filesSeen: UInt64
  public let finishedJobs: Set<FullSweepJob>
  /// The file the sweep last reported reading. Nil before the first report,
  /// and it never goes back to nil once a sweep is under way.
  public let reading: AbsolutePath?

  public init(
    bytesReclaimable: UInt64,
    issueCount: UInt32,
    filesSeen: UInt64,
    finishedJobs: Set<FullSweepJob>,
    reading: AbsolutePath? = nil
  ) {
    self.bytesReclaimable = bytesReclaimable
    self.issueCount = issueCount
    self.filesSeen = filesSeen
    self.finishedJobs = finishedJobs
    self.reading = reading
  }
}

/// The combined review: every job's findings, grouped by job, with the
/// selection each engine chose. A sweep offers deselection only, which is why
/// there is no command here that adds to the selection beyond what arrived
/// preselected.
public struct FullSweepReview: Sendable, Equatable {
  public let sessionID: UUID
  public let jobs: [FullSweepJobFindings]
  public let selectedFindingIDs: Set<UUID>
  public let summary: FullSweepSummary

  public init(
    sessionID: UUID,
    jobs: [FullSweepJobFindings],
    selectedFindingIDs: Set<UUID>,
    summary: FullSweepSummary
  ) {
    self.sessionID = sessionID
    self.jobs = jobs
    let known = Set(jobs.flatMap { $0.findings.map(\.id) })
    self.selectedFindingIDs = selectedFindingIDs.intersection(known)
    self.summary = summary
  }

  public var selectedFindings: [Finding] {
    jobs.flatMap(\.findings).filter { selectedFindingIDs.contains($0.id) }
  }

  public var selectedByteTotal: UInt64 {
    selectedFindings.reduce(0) { $0 + $1.byteSize }
  }
}

public struct FullSweepJobFindings: Sendable, Equatable, Identifiable {
  public var id: FullSweepJob { job }
  public let job: FullSweepJob
  public let findings: [Finding]
  /// The sentence naming why this job has nothing, when it failed.
  public let failure: String?

  public init(job: FullSweepJob, findings: [Finding], failure: String?) {
    self.job = job
    self.findings = findings
    self.failure = failure
  }
}

public struct FullSweepRunSummary: Sendable, Equatable {
  public let bytesReclaimed: UInt64
  public let completedCount: UInt32
  public let failures: [String]

  public init(bytesReclaimed: UInt64, completedCount: UInt32, failures: [String]) {
    self.bytesReclaimed = bytesReclaimed
    self.completedCount = completedCount
    self.failures = failures
  }
}

/// The Full Sweep's view model, and the one thing that decides what the orb is
/// doing.
///
/// It adds no policy the orchestrator does not have. The selection starts as
/// exactly what the engines preselected and every command it offers narrows
/// it, so a sweep can only ever do less than the modules would.
@MainActor @Observable
public final class FullSweepModuleModel {
  public private(set) var state: FullSweepModuleState = .idle
  public private(set) var failureNotice: String?

  @ObservationIgnored private let orchestrator: any FullSweepOrchestrating
  @ObservationIgnored private let executor: any PlanExecuting
  @ObservationIgnored private let settings: any SettingsStoring
  @ObservationIgnored private let sessions: any FullSweepSessionProviding
  @ObservationIgnored private let hasFullDiskAccess: @Sendable () async -> Bool
  @ObservationIgnored private var lifecycleEpoch: UInt64 = 0
  @ObservationIgnored private var scanTask: Task<Void, Never>?
  @ObservationIgnored private var runTask: Task<Void, Never>?

  public init(
    orchestrator: any FullSweepOrchestrating,
    executor: any PlanExecuting,
    settings: any SettingsStoring,
    sessions: any FullSweepSessionProviding,
    hasFullDiskAccess: @escaping @Sendable () async -> Bool = { true }
  ) {
    self.orchestrator = orchestrator
    self.executor = executor
    self.settings = settings
    self.sessions = sessions
    self.hasFullDiskAccess = hasFullDiskAccess
  }

  deinit {
    scanTask?.cancel()
    runTask?.cancel()
  }

  /// What the hub's orb and status line read. It is derived from the state
  /// rather than published separately, so the scene and the pane can never
  /// disagree about what is happening.
  public var hubActivity: HubSweepActivity? {
    switch state {
    case .idle:
      return nil
    case .scanning(let progress):
      return .scanning(bytesReclaimable: progress.bytesReclaimable)
    case .reviewing(let review):
      return .result(
        bytesReclaimable: review.summary.bytesReclaimable,
        issueCount: review.summary.issueCount)
    case .executing:
      return .scanning(bytesReclaimable: 0)
    case .result(let summary):
      return .result(bytesReclaimable: summary.bytesReclaimed, issueCount: 0)
    case .cleanSweep:
      return .cleanSweep
    }
  }

  // MARK: - Commands

  public func startSweep() {
    switch state {
    case .scanning, .executing:
      return
    case .idle, .reviewing, .result, .cleanSweep:
      break
    }
    failureNotice = nil
    lifecycleEpoch &+= 1
    let epoch = lifecycleEpoch
    scanTask = Task { await runSweep(epoch: epoch) }
  }

  public func cancelSweep() {
    guard case .scanning = state else { return }
    lifecycleEpoch &+= 1
    scanTask?.cancel()
    scanTask = nil
    state = .idle
  }

  /// Deselection only. A row can be put back after being unticked, and
  /// nothing here can select a row an engine never offered, because the only
  /// identifiers this accepts are the ones the review already holds.
  public func toggleFinding(_ findingID: UUID) {
    guard case .reviewing(let review) = state else { return }
    guard review.jobs.flatMap(\.findings).contains(where: { $0.id == findingID }) else { return }
    var selection = review.selectedFindingIDs
    if selection.contains(findingID) {
      selection.remove(findingID)
    } else {
      selection.insert(findingID)
    }
    state = .reviewing(
      FullSweepReview(
        sessionID: review.sessionID,
        jobs: review.jobs,
        selectedFindingIDs: selection,
        summary: review.summary))
  }

  @discardableResult
  public func run() -> Bool {
    guard case .reviewing(let review) = state, !review.selectedFindingIDs.isEmpty else {
      return false
    }
    lifecycleEpoch &+= 1
    let epoch = lifecycleEpoch
    runTask = Task { await runPlan(review: review, epoch: epoch) }
    return true
  }

  public func acknowledgeResult() {
    switch state {
    case .result, .cleanSweep:
      state = .idle
    case .idle, .scanning, .reviewing, .executing:
      return
    }
  }

  // MARK: - Sweeping

  private func runSweep(epoch: UInt64) async {
    let loadedSettings = await settings.load()
    let granted = await hasFullDiskAccess()
    let context = await sessions.makeScanContext(
      settings: loadedSettings, hasFullDiskAccess: granted)
    guard epoch == lifecycleEpoch else { return }
    var accumulator = SweepAccumulator(sessionID: context.sessionID)
    state = .scanning(accumulator.progress)
    do {
      for try await event in orchestrator.scan(context) {
        guard epoch == lifecycleEpoch else { return }
        switch event {
        case .job(let job, let scanEvent):
          accumulator.apply(scanEvent, for: job)
          state = .scanning(accumulator.progress)
        case .jobFailed(let job, let reason):
          accumulator.fail(job, reason: reason)
          state = .scanning(accumulator.progress)
        case .summary(let summary):
          accumulator.finish(with: summary)
        }
      }
      guard epoch == lifecycleEpoch else { return }
      state = accumulator.finalState()
    } catch {
      guard epoch == lifecycleEpoch else { return }
      state = .idle
      failureNotice = Self.sentence(for: error, fallback: "The sweep could not be completed.")
    }
  }

  private struct SweepAccumulator {
    let sessionID: UUID
    private var findings: [FullSweepJob: [Finding]] = [:]
    private var failures: [FullSweepJob: String] = [:]
    private var filesSeen: UInt64 = 0
    private var reading: AbsolutePath?
    private var summary: FullSweepSummary?

    init(sessionID: UUID) {
      self.sessionID = sessionID
    }

    var progress: FullSweepProgress {
      FullSweepProgress(
        bytesReclaimable: findings.values.flatMap { $0 }.reduce(0) { $0 + $1.byteSize },
        issueCount: UInt32(findings.values.reduce(0) { $0 + $1.count }),
        filesSeen: filesSeen,
        finishedJobs: Set(failures.keys),
        reading: reading)
    }

    mutating func apply(_ event: ScanEvent, for job: FullSweepJob) {
      switch event {
      case .finding(let finding):
        findings[job, default: []].append(finding)
      case .progress(let counters):
        filesSeen = max(filesSeen, counters.filesSeen)
      case .reading(let path):
        reading = path
      case .phase, .degraded:
        break
      }
    }

    mutating func fail(_ job: FullSweepJob, reason: String) {
      failures[job] = reason
    }

    mutating func finish(with summary: FullSweepSummary) {
      self.summary = summary
    }

    /// The review, or the clean sweep when nothing was found at all. A sweep
    /// where every job failed is not a clean sweep: it is a sweep that could
    /// not look, and saying "nothing to do" there would be a lie.
    func finalState() -> FullSweepModuleState {
      let jobs = FullSweepJob.allCases.map { job in
        FullSweepJobFindings(
          job: job, findings: findings[job] ?? [], failure: failures[job])
      }
      let everything = jobs.flatMap(\.findings)
      guard !everything.isEmpty else {
        return failures.isEmpty
          ? .cleanSweep
          : .result(
            FullSweepRunSummary(
              bytesReclaimed: 0, completedCount: 0, failures: Array(failures.values)))
      }
      return .reviewing(
        FullSweepReview(
          sessionID: sessionID,
          jobs: jobs,
          selectedFindingIDs: Set(everything.filter(\.isPreselected).map(\.id)),
          summary: summary
            ?? FullSweepSummary(
              bytesReclaimable: everything.reduce(0) { $0 + $1.byteSize },
              issueCount: UInt32(everything.count),
              perJob: [])))
    }
  }

  // MARK: - Running

  private func runPlan(review: FullSweepReview, epoch: UInt64) async {
    let currentSettings = await settings.load()
    let context = await sessions.makePlanContext(
      sessionID: review.sessionID, settings: currentSettings)
    guard epoch == lifecycleEpoch else { return }
    let plan: OperationPlan
    do {
      plan = try orchestrator.plan(selection: review.selectedFindings, context: context)
    } catch {
      failureNotice = Self.sentence(for: error, fallback: "The sweep could not be planned.")
      return
    }
    state = .executing(finished: 0, total: UInt32(plan.operations.count))
    var reclaimed: UInt64 = 0
    var completed: UInt32 = 0
    var failures: [String] = []
    var finished: UInt32 = 0
    for await event in executor.execute(plan) {
      guard epoch == lifecycleEpoch else { return }
      switch event {
      case .refused(let refusal):
        if case .helperUnavailable(let reason) = refusal { failures.append(reason) }
      case .operationStarted:
        break
      case .operationFinished(_, let result):
        finished += 1
        state = .executing(finished: finished, total: UInt32(plan.operations.count))
        switch result {
        case .completed(let bytes):
          reclaimed += bytes
          completed += 1
        case .failed(let reason):
          failures.append(reason)
        case .skippedDenylisted, .notStarted:
          break
        }
      case .planCompleted:
        state = .result(
          FullSweepRunSummary(
            bytesReclaimed: reclaimed, completedCount: completed, failures: failures))
      }
    }
  }

  private static func sentence(for error: any Error, fallback: String) -> String {
    guard let described = (error as? any LocalizedError)?.errorDescription, !described.isEmpty
    else { return fallback }
    return described
  }
}
