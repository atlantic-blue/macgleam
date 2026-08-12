import Foundation

/// One scan composing the three jobs a Full Sweep runs, with one combined
/// result and per job detail.
///
/// Guarantees:
/// - Exactly the jobs in `FullSweepJob` run. No stub jobs, ever: a job appears
///   here when its module ships and this enum gains a case, so a sweep can
///   never report progress on something that does not exist.
/// - Jobs run concurrently; events interleave, each tagged with its job.
/// - One job failing does not sink the others. The combined result carries
///   that job's failure as a plain sentence and every other job's findings are
///   fully usable.
/// - `summary` is emitted exactly once, after every job has finished.
/// - `plan` produces one combined plan whose operations preserve each
///   underlying engine's invariants, because each engine plans its own rows.
/// - A Full Sweep never selects what an engine did not preselect: the review
///   starts from each finding's own `isPreselected` and offers deselection
///   only. This holds no preselection policy of its own, so it cannot widen
///   one.
/// - No plan this produces contains a maintenance task that clears user
///   visible data. A sweep runs without anybody opening a row, so a task whose
///   warning has to be read is unreachable here by construction and stays
///   available in the Performance module where the warning is shown.
public protocol FullSweepOrchestrating: Sendable {
  func scan(_ context: ScanContext) -> AsyncThrowingStream<FullSweepEvent, Error>
  func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan
}

/// The jobs a Full Sweep runs. A closed set, and adding to it is the only way
/// a sweep can grow: nothing here can report a job that has no module.
public enum FullSweepJob: String, Codable, Sendable, CaseIterable, Equatable {
  case deepClean
  case storageDeclutter
  case performanceBoost

  /// What the job is called on screen, in the words the modules use.
  public var title: String {
    switch self {
    case .deepClean: return "Deep clean"
    case .storageDeclutter: return "Storage declutter"
    case .performanceBoost: return "Performance boost"
    }
  }
}

public enum FullSweepEvent: Sendable {
  case job(FullSweepJob, ScanEvent)
  case jobFailed(FullSweepJob, reason: String)
  case summary(FullSweepSummary)
}

/// The one number pair the hub shows, and the detail behind it.
public struct FullSweepSummary: Codable, Sendable, Equatable {
  public let bytesReclaimable: UInt64
  public let issueCount: UInt32
  public let perJob: [FullSweepJobOutcome]

  public init(bytesReclaimable: UInt64, issueCount: UInt32, perJob: [FullSweepJobOutcome]) {
    self.bytesReclaimable = bytesReclaimable
    self.issueCount = issueCount
    self.perJob = perJob
  }
}

public struct FullSweepJobOutcome: Codable, Sendable, Equatable {
  public enum Outcome: Codable, Sendable, Equatable {
    case completed(findingCount: UInt32, bytes: UInt64)
    case failed(reason: String)
  }

  public let job: FullSweepJob
  public let outcome: Outcome

  public init(job: FullSweepJob, outcome: Outcome) {
    self.job = job
    self.outcome = outcome
  }
}
