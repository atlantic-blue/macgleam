import Foundation
import GleamCore
import Observation
import ProtectionEngine

/// The narrow engine seam the module consumes, so tests script a scan and a
/// plan without the real engine. ProtectionEngine is the one production
/// conformance and this adds nothing to C27.
public protocol ProtectionScanning: Sendable {
  func scan(_ context: ScanContext) -> AsyncThrowingStream<ScanEvent, Error>
  func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan
}

extension ProtectionEngine: ProtectionScanning {}

/// Mints the per session contexts, the same shape the other modules use.
public protocol ProtectionSessionProviding: Sendable {
  func makeScanContext(settings: Settings, hasFullDiskAccess: Bool) async -> ScanContext
  func makePlanContext(sessionID: UUID, settings: Settings) async -> PlanContext
}

/// The Protection module's view model. A thin view renders this and adds no
/// state of its own.
///
/// Two things make it different from Cleanup, and both come from what the
/// module does. Threats arrive ticked because containment is reversible and
/// leaving malware running while somebody reads a list is the worse default.
/// Traces never do, and clearing them is permanent, so a run that includes one
/// needs a confirmation naming their exact counts before anything happens.
@MainActor @Observable
public final class ProtectionModuleModel {
  public private(set) var state: ProtectionModuleState = .idle
  public private(set) var degradedNotices: [String] = []
  public private(set) var failureNotice: String?

  @ObservationIgnored private let engine: any ProtectionScanning
  @ObservationIgnored private let executor: any PlanExecuting
  @ObservationIgnored private let settings: any SettingsStoring
  @ObservationIgnored private let sessions: any ProtectionSessionProviding
  @ObservationIgnored private let hasFullDiskAccess: @Sendable () async -> Bool

  /// Bumped by every accepted lifecycle command, so work in flight from a
  /// superseded scan or run can never write into a later one.
  @ObservationIgnored private var lifecycleEpoch: UInt64 = 0
  @ObservationIgnored private var isTransitionPending = false
  @ObservationIgnored private var scanTask: Task<Void, Never>?
  @ObservationIgnored private var executionTask: Task<Void, Never>?
  @ObservationIgnored private var cachedSettings = Settings.defaults

  public init(
    engine: any ProtectionScanning,
    executor: any PlanExecuting,
    settings: any SettingsStoring,
    sessions: any ProtectionSessionProviding,
    hasFullDiskAccess: @escaping @Sendable () async -> Bool = { true }
  ) {
    self.engine = engine
    self.executor = executor
    self.settings = settings
    self.sessions = sessions
    self.hasFullDiskAccess = hasFullDiskAccess
  }

  deinit {
    scanTask?.cancel()
    executionTask?.cancel()
  }

  // MARK: - Commands

  public func startScan() {
    switch state {
    case .scanning, .executing:
      return
    case .idle, .reviewing, .result, .allClear:
      break
    }
    guard !isTransitionPending else { return }
    isTransitionPending = true
    failureNotice = nil
    lifecycleEpoch &+= 1
    let epoch = lifecycleEpoch
    scanTask = Task { await runScan(epoch: epoch) }
  }

  public func cancelScan() {
    guard case .scanning = state else { return }
    lifecycleEpoch &+= 1
    scanTask?.cancel()
    scanTask = nil
    isTransitionPending = false
    state = .idle
  }

  /// Toggles one row. An unknown identifier is ignored and never a lifecycle
  /// change.
  public func toggleFinding(_ findingID: UUID) {
    guard case .reviewing(let review) = state else { return }
    guard (review.threats + review.traces).contains(where: { $0.id == findingID }) else { return }
    var selection = review.selectedFindingIDs
    if selection.contains(findingID) {
      selection.remove(findingID)
    } else {
      selection.insert(findingID)
    }
    state = .reviewing(
      ProtectionReviewState(
        sessionID: review.sessionID,
        threats: review.threats,
        traces: review.traces,
        selectedFindingIDs: selection))
  }

  /// The exact file count and byte total the selection would clear
  /// permanently: the traces and nothing else. Nil when no trace is selected,
  /// and nil in every state but reviewing.
  public func clearedScope() -> PermanentDeletionScope? {
    guard case .reviewing(let review) = state else { return nil }
    let traces = review.selectedTraces
    guard !traces.isEmpty else { return nil }
    return PermanentDeletionScope(
      fileCount: UInt32(traces.reduce(0) { $0 + $1.paths.count }),
      byteTotal: traces.reduce(0) { $0 + $1.byteSize })
  }

  /// Runs the selection. A non nil refusal means nothing changed, and every
  /// refusal is decided before the engine or the executor is touched.
  @discardableResult
  public func executeSelection(
    clearingConfirmation: PermanentDeletionConfirmation?
  ) -> ProtectionCommandRefusal? {
    guard case .reviewing(let review) = state, !isTransitionPending else { return .notReviewing }
    guard !review.selectedFindingIDs.isEmpty else { return .emptySelection }
    if let scope = clearedScope() {
      guard let confirmation = clearingConfirmation else {
        return .tracesUnconfirmed(required: scope)
      }
      guard confirmation.fileCount == scope.fileCount, confirmation.byteTotal == scope.byteTotal
      else { return .confirmationMismatch(required: scope) }
    }
    isTransitionPending = true
    lifecycleEpoch &+= 1
    let epoch = lifecycleEpoch
    executionTask = Task {
      await runExecution(review: review, confirmation: clearingConfirmation, epoch: epoch)
    }
    return nil
  }

  public func acknowledgeResult() {
    switch state {
    case .result, .allClear:
      state = .idle
    case .idle, .scanning, .reviewing, .executing:
      return
    }
  }

  // MARK: - Scanning

  private func runScan(epoch: UInt64) async {
    let loadedSettings = await settings.load()
    let granted = await hasFullDiskAccess()
    let context = await sessions.makeScanContext(
      settings: loadedSettings, hasFullDiskAccess: granted)
    guard epoch == lifecycleEpoch else { return }
    cachedSettings = loadedSettings
    degradedNotices = []
    var accumulator = Accumulator(sessionID: context.sessionID)
    state = .scanning(accumulator.progress)
    isTransitionPending = false
    do {
      for try await event in engine.scan(context) {
        guard epoch == lifecycleEpoch else { return }
        apply(event, to: &accumulator)
      }
      guard epoch == lifecycleEpoch else { return }
      finishScan(with: accumulator)
    } catch {
      guard epoch == lifecycleEpoch else { return }
      state = .idle
      failureNotice = Self.sentence(for: error, fallback: "The scan could not be completed.")
    }
  }

  private func apply(_ event: ScanEvent, to accumulator: inout Accumulator) {
    switch event {
    case .phase(let phase):
      accumulator.advance(to: phase)
      state = .scanning(accumulator.progress)
    case .progress(let counters):
      accumulator.merge(counters)
      state = .scanning(accumulator.progress)
    case .finding(let finding):
      accumulator.append(finding)
    case .degraded(let sentence):
      appendDegradedNotice(sentence)
    }
  }

  private func finishScan(with accumulator: Accumulator) {
    guard !accumulator.threats.isEmpty || !accumulator.traces.isEmpty else {
      state = .allClear(filesChecked: accumulator.progress.counters.filesSeen)
      return
    }
    state = .reviewing(
      ProtectionReviewState(
        sessionID: accumulator.sessionID,
        threats: accumulator.threats,
        traces: accumulator.traces,
        selectedFindingIDs: Set(accumulator.threats.filter(\.isPreselected).map(\.id))))
  }

  /// One scan's findings, split into the two lists the review shows and kept
  /// in arrival order inside each.
  private struct Accumulator {
    let sessionID: UUID
    private(set) var threats: [Finding] = []
    private(set) var traces: [Finding] = []
    private var phase = ScanPhase.indeterminate
    private var counters = ScanCounters.zero

    init(sessionID: UUID) {
      self.sessionID = sessionID
    }

    var progress: ProtectionScanProgress {
      ProtectionScanProgress(sessionID: sessionID, phase: phase, counters: counters)
    }

    mutating func advance(to next: ScanPhase) {
      guard Self.rank(of: next) >= Self.rank(of: phase) else { return }
      phase = next
    }

    mutating func merge(_ next: ScanCounters) {
      counters = ScanCounters(
        filesSeen: max(counters.filesSeen, next.filesSeen),
        bytesReclaimable: max(counters.bytesReclaimable, next.bytesReclaimable),
        itemCount: max(counters.itemCount, next.itemCount))
    }

    mutating func append(_ finding: Finding) {
      guard finding.sessionID == sessionID else { return }
      if ProtectionModuleModel.isTrace(finding.category) {
        traces.append(finding)
      } else {
        threats.append(finding)
      }
    }

    private static func rank(of phase: ScanPhase) -> Int {
      switch phase {
      case .indeterminate: return 0
      case .determinate: return 1
      case .settling: return 2
      }
    }
  }

  nonisolated static func isTrace(_ category: FindingCategory) -> Bool {
    switch category {
    case .browserHistory, .browserCookies, .browserSiteData, .recentItemsList,
      .wifiNetworkHistory:
      return true
    default:
      return false
    }
  }

  // MARK: - Running

  private func runExecution(
    review: ProtectionReviewState,
    confirmation: PermanentDeletionConfirmation?,
    epoch: UInt64
  ) async {
    let currentSettings = await settings.load()
    let planContext = await sessions.makePlanContext(
      sessionID: review.sessionID, settings: currentSettings)
    guard epoch == lifecycleEpoch else { return }
    cachedSettings = currentSettings
    let plan: OperationPlan
    do {
      plan = attach(
        confirmation,
        to: try engine.plan(selection: review.selectedFindings, context: planContext))
    } catch {
      isTransitionPending = false
      failureNotice = Self.sentence(for: error, fallback: "This could not be planned.")
      return
    }
    state = .executing(
      ProtectionExecutionProgress(
        planID: plan.id,
        totalOperations: UInt32(plan.operations.count),
        finishedOperations: 0,
        currentOperationID: nil))
    isTransitionPending = false
    await consume(plan: plan, review: review, epoch: epoch)
  }

  /// The confirmation the caller passed is attached and never one built here,
  /// because a confirmation is evidence somebody saw the counts.
  private func attach(
    _ confirmation: PermanentDeletionConfirmation?,
    to plan: OperationPlan
  ) -> OperationPlan {
    OperationPlan(
      id: plan.id,
      sessionID: plan.sessionID,
      operations: plan.operations,
      totalBytes: plan.totalBytes,
      permanentDeletionConfirmation: confirmation)
  }

  private func consume(
    plan: OperationPlan,
    review: ProtectionReviewState,
    epoch: UInt64
  ) async {
    var refusals: [String] = []
    var contained: UInt32 = 0
    var cleared: UInt32 = 0
    var reclaimed: UInt64 = 0
    var skipped: [String] = []
    var failures: [String] = []
    for await event in executor.execute(plan) {
      guard epoch == lifecycleEpoch else { return }
      switch event {
      case .refused(let refusal):
        refusals.append(Self.sentence(for: refusal))
      case .operationStarted(let operationID):
        updateProgress { progress in
          ProtectionExecutionProgress(
            planID: progress.planID,
            totalOperations: progress.totalOperations,
            finishedOperations: progress.finishedOperations,
            currentOperationID: operationID)
        }
      case .operationFinished(let operationID, let result):
        let kind = plan.operations.first { $0.id == operationID }?.kind
        switch result {
        case .completed(let bytes):
          reclaimed += bytes
          if case .quarantine = kind {
            contained += 1
          } else {
            cleared += 1
          }
        case .skippedDenylisted:
          if let name = Self.targetName(of: kind) { skipped.append(name) }
        case .failed(let reason):
          failures.append(reason)
        case .notStarted:
          break
        }
        updateProgress { progress in
          ProtectionExecutionProgress(
            planID: progress.planID,
            totalOperations: progress.totalOperations,
            finishedOperations: progress.finishedOperations + 1,
            currentOperationID: nil)
        }
      case .planCompleted:
        state = .result(
          ProtectionResultSummary(
            containedCount: contained,
            clearedCount: cleared,
            bytesReclaimed: reclaimed,
            failures: refusals + failures,
            skippedDenylistedNames: skipped))
      }
    }
  }

  private func updateProgress(
    _ transform: (ProtectionExecutionProgress) -> ProtectionExecutionProgress
  ) {
    guard case .executing(let progress) = state else { return }
    state = .executing(transform(progress))
  }

  private func appendDegradedNotice(_ sentence: String) {
    guard !sentence.isEmpty, !degradedNotices.contains(sentence) else { return }
    degradedNotices.append(sentence)
  }

  private static func targetName(of kind: GleamCore.Operation.Kind?) -> String? {
    switch kind {
    case .moveToTrash(let target), .deletePermanently(let target), .quarantine(let target),
      .archive(let target, _):
      return target.lastComponent
    default:
      return nil
    }
  }

  private static func sentence(for refusal: ExecutionRefusal) -> String {
    switch refusal {
    case .permanentDeletionUnconfirmed:
      return "The clearing was not confirmed, so nothing was cleared."
    case .helperUnavailable(let reason):
      return reason
    }
  }

  private static func sentence(for error: any Error, fallback: String) -> String {
    guard let described = (error as? any LocalizedError)?.errorDescription, !described.isEmpty
    else { return fallback }
    return described
  }
}
