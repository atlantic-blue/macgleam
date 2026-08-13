import Foundation

/// The Full Sweep: three engines run at once over one scan session, and one
/// combined answer.
///
/// It composes and decides nothing else. Each job is an engine that already
/// knows what it finds, what risk it carries and what it preselects, and this
/// adds no policy of its own: it starts the three, tags what they say, keeps
/// what they found, and sums it once at the end. That is deliberate, because a
/// sweep runs without anybody opening a row, and the one thing it must not do
/// is widen what an engine chose to offer.
///
/// The one rule it holds itself is the maintenance exclusion, and it holds it
/// at plan time over everything selected rather than at selection time: a task
/// whose warning has to be read cannot be run by a sweep nobody watched.
public struct FullSweepOrchestrator: FullSweepOrchestrating {
  /// One job's engine, named by the job it runs.
  private let engines: [FullSweepJob: any GleamEngine]

  /// A job with no engine does not run and is not reported: the enum is the
  /// list of jobs, and a build missing one of them says so by failing that
  /// job rather than by quietly shrinking the sweep.
  public init(engines: [FullSweepJob: any GleamEngine]) {
    self.engines = engines
  }

  public func scan(_ context: ScanContext) -> AsyncThrowingStream<FullSweepEvent, Error> {
    AsyncThrowingStream { continuation in
      // A walk runs below whatever asked for it. Reading a few hundred
      // thousand files at the interface's own priority makes the whole machine
      // feel slow while a scan is on, and nobody is waiting on any single file
      // of it.
      let work = Task(priority: .utility) {
        await runJobs(context) { continuation.yield($0) }
        continuation.finish()
      }
      continuation.onTermination = { _ in work.cancel() }
    }
  }

  /// Every job at once, each tagged, and exactly one summary after the last
  /// of them lands.
  private func runJobs(
    _ context: ScanContext,
    yield: @escaping @Sendable (FullSweepEvent) -> Void
  ) async {
    let collector = JobCollector()
    await withTaskGroup(of: Void.self) { group in
      for job in FullSweepJob.allCases {
        group.addTask {
          await run(job, context: context, into: collector, yield: yield)
        }
      }
      await group.waitForAll()
    }
    yield(.summary(await collector.summary()))
  }

  private func run(
    _ job: FullSweepJob,
    context: ScanContext,
    into collector: JobCollector,
    yield: @escaping @Sendable (FullSweepEvent) -> Void
  ) async {
    guard let engine = engines[job] else {
      let reason = "\(job.title) is not available in this build, so it was not run."
      await collector.fail(job, reason: reason)
      yield(.jobFailed(job, reason: reason))
      return
    }
    do {
      for try await event in engine.scan(context) {
        if case .finding(let finding) = event {
          await collector.record(finding, for: job)
        }
        yield(.job(job, event))
      }
      await collector.complete(job)
    } catch {
      // One job failing leaves the others untouched. The sweep reports what
      // this one could not do and keeps everything the others found, because
      // a sweep that threw away two good results over one bad one would be
      // worse than no sweep.
      let reason = Self.sentence(for: error, job: job)
      await collector.fail(job, reason: reason)
      yield(.jobFailed(job, reason: reason))
    }
  }

  public func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan {
    guard !selection.isEmpty else { throw PlanningError.emptySelection }
    for finding in selection where finding.sessionID != context.sessionID {
      throw PlanningError.findingFromDifferentSession(finding.id)
    }
    var operations: [GleamCore.Operation] = []
    var totalBytes: UInt64 = 0
    // Each engine plans its own rows, so every invariant a module holds about
    // its own operations holds here too, unchanged and unrepeated.
    for job in FullSweepJob.allCases {
      let rows = selection.filter { Self.job(of: $0.category) == job && isSweepable($0) }
      guard !rows.isEmpty, let engine = engines[job] else { continue }
      let plan = try engine.plan(selection: rows, context: context)
      operations.append(contentsOf: plan.operations)
      totalBytes += plan.totalBytes
    }
    return OperationPlan(
      id: UUID(),
      sessionID: context.sessionID,
      operations: operations,
      totalBytes: totalBytes,
      permanentDeletionConfirmation: nil)
  }

  /// A maintenance task that clears something a person can see is dropped
  /// here rather than filtered at the review, because the review is what a
  /// sweep does not have. The flag decides, so a task added later is covered
  /// without anything being added to this list.
  private func isSweepable(_ finding: Finding) -> Bool {
    guard case .maintenanceTask(let task) = finding.category else { return true }
    return !task.clearsUserVisibleData
  }

  /// Which job owns a category. A category no job owns is not this
  /// orchestrator's to plan, so it contributes nothing rather than being
  /// planned by whichever engine happened to be first.
  public static func job(of category: FindingCategory) -> FullSweepJob? {
    switch category {
    case .userCache, .applicationCache, .log, .brokenDownload, .xcodeDerivedData,
      .simulatorCache, .browserCache, .temporaryFile, .mailAttachmentLocalCopy, .trashBin:
      return .deepClean
    case .largeFile, .oldFile, .downloadsTriage, .duplicateSet, .similarPhotoSet:
      return .storageDeclutter
    case .maintenanceTask:
      return .performanceBoost
    default:
      return nil
    }
  }

  private static func sentence(for error: any Error, job: FullSweepJob) -> String {
    guard let described = (error as? any LocalizedError)?.errorDescription, !described.isEmpty
    else { return "\(job.title) could not be completed." }
    return described
  }
}

/// What the jobs found, gathered as they run. An actor because three jobs
/// write to it at once, and the summary has to be one consistent reading of
/// all three rather than three readings taken at different moments.
private actor JobCollector {
  private var findingCounts: [FullSweepJob: UInt32] = [:]
  private var bytes: [FullSweepJob: UInt64] = [:]
  private var failures: [FullSweepJob: String] = [:]
  private var completed: Set<FullSweepJob> = []

  func record(_ finding: Finding, for job: FullSweepJob) {
    findingCounts[job, default: 0] += 1
    bytes[job, default: 0] += finding.byteSize
  }

  func complete(_ job: FullSweepJob) {
    completed.insert(job)
  }

  func fail(_ job: FullSweepJob, reason: String) {
    failures[job] = reason
  }

  /// One reading, after every job has finished. A failed job contributes no
  /// bytes and no issues: it found nothing, and saying otherwise would put a
  /// number on screen that nothing stands behind.
  func summary() -> FullSweepSummary {
    var reclaimable: UInt64 = 0
    var issues: UInt32 = 0
    var perJob: [FullSweepJobOutcome] = []
    for job in FullSweepJob.allCases {
      if let reason = failures[job] {
        perJob.append(FullSweepJobOutcome(job: job, outcome: .failed(reason: reason)))
        continue
      }
      let count = findingCounts[job] ?? 0
      let jobBytes = bytes[job] ?? 0
      reclaimable += jobBytes
      issues += count
      perJob.append(
        FullSweepJobOutcome(
          job: job, outcome: .completed(findingCount: count, bytes: jobBytes)))
    }
    return FullSweepSummary(
      bytesReclaimable: reclaimable, issueCount: issues, perJob: perJob)
  }
}
