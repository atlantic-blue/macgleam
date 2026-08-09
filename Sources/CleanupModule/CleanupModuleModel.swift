import Foundation
import GleamCore
import Observation

/// The cleanup module view model, on the macOS 14 Observation framework. A
/// thin SwiftUI view renders this and adds no state of its own; the module's
/// whole behaviour is this class driven against its five injected protocols.
///
/// State transitions are total and deterministic: every command in every
/// state either performs its named transition or leaves the state identical,
/// and equal command and event sequences produce equal state sequences. The
/// model never touches the file system (the disk is reachable only through
/// the engine's scan stream and the executor) and never reads a clock: every
/// date it holds arrived in an input.
@MainActor @Observable
public final class CleanupModuleModel {
  public private(set) var state: CleanupModuleState = .idle
  public private(set) var degradedNotices: [String] = []
  public private(set) var failureNotice: String?
  public private(set) var hubEstimateBytes: UInt64 = 0

  @ObservationIgnored private let engine: any GleamEngine
  @ObservationIgnored private let executor: any PlanExecuting
  @ObservationIgnored private let settings: any SettingsStoring
  @ObservationIgnored private let sessions: any CleanupSessionProviding
  @ObservationIgnored private let degraded: any CleanupDegradedStateProviding

  /// Bumped by every accepted lifecycle command. In flight work captures the
  /// value at launch and applies effects only while it still matches, so a
  /// superseded scan or execution can never write into a later lifecycle.
  @ObservationIgnored private var lifecycleEpoch: UInt64 = 0
  /// True from a lifecycle command's acceptance until its asynchronous
  /// transition lands, so a second command cannot slip into the gap.
  @ObservationIgnored private var isTransitionPending = false
  @ObservationIgnored private var scanTask: Task<Void, Never>?
  @ObservationIgnored private var executionTask: Task<Void, Never>?
  @ObservationIgnored private var settingsUpdatesTask: Task<Void, Never>?
  @ObservationIgnored private var isExecutionCancellationRequested = false
  @ObservationIgnored private var cachedSettings = Settings.defaults

  public init(
    engine: any GleamEngine,
    executor: any PlanExecuting,
    settings: any SettingsStoring,
    sessions: any CleanupSessionProviding,
    degraded: any CleanupDegradedStateProviding
  ) {
    precondition(
      engine.module == .cleanup,
      "CleanupModuleModel requires the cleanup engine, not \(engine.module)."
    )
    self.engine = engine
    self.executor = executor
    self.settings = settings
    self.sessions = sessions
    self.degraded = degraded
    consumeSettingsUpdates()
  }

  deinit {
    scanTask?.cancel()
    executionTask?.cancel()
    settingsUpdatesTask?.cancel()
  }

  // MARK: - Commands

  /// Begins a fresh scan session from idle, reviewing, result or cleanSweep.
  /// Ignored while scanning or executing. From reviewing it discards the
  /// current findings and selection.
  public func startScan() {
    switch state {
    case .scanning, .executing:
      return
    case .idle, .reviewing, .result, .cleanSweep:
      break
    }
    guard !isTransitionPending else { return }
    isTransitionPending = true
    failureNotice = nil
    lifecycleEpoch &+= 1
    let epoch = lifecycleEpoch
    scanTask = Task { await runScan(epoch: epoch) }
  }

  /// Toggles one finding's selection while reviewing. An unknown finding
  /// identifier is ignored; never a lifecycle change.
  public func toggleFinding(_ findingID: UUID) {
    guard case .reviewing(let review) = state else { return }
    guard review.categories.contains(where: { $0.findings.contains { $0.id == findingID } })
    else { return }
    var selection = review.selectedFindingIDs
    if selection.contains(findingID) {
      selection.remove(findingID)
    } else {
      selection.insert(findingID)
    }
    applySelection(selection, to: review)
  }

  /// Selects every finding in the category when at least one is unselected,
  /// otherwise deselects every one. Reviewing only; unknown categories are
  /// ignored.
  public func toggleCategory(_ category: FindingCategory) {
    guard case .reviewing(let review) = state else { return }
    guard let group = review.categories.first(where: { $0.category == category }) else { return }
    let groupIDs = Set(group.findings.map(\.id))
    let hasUnselected = !groupIDs.isSubset(of: review.selectedFindingIDs)
    let selection =
      hasUnselected
      ? review.selectedFindingIDs.union(groupIDs)
      : review.selectedFindingIDs.subtracting(groupIDs)
    applySelection(selection, to: review)
  }

  /// The exact file count and byte total the current selection would plan as
  /// permanent deletion under the current deletion mode: every selected
  /// finding when the mode is permanent, and trash bin findings always,
  /// whatever the mode. Nil when reviewing with no permanent operations, and
  /// nil in every other state.
  public func permanentDeletionScope() -> PermanentDeletionScope? {
    guard case .reviewing(let review) = state else { return nil }
    let permanentFindings = review.selectedFindings.filter {
      plansPermanently($0.category, mode: cachedSettings.deletionMode)
    }
    guard !permanentFindings.isEmpty else { return nil }
    return PermanentDeletionScope(
      fileCount: UInt32(permanentFindings.reduce(0) { $0 + $1.paths.count }),
      byteTotal: permanentFindings.reduce(0) { $0 + $1.byteSize }
    )
  }

  /// Builds the plan for the current selection and starts executing it. A
  /// non nil refusal is returned and nothing changes otherwise; every refusal
  /// is decided before the engine or executor is touched.
  @discardableResult
  public func executeSelection(
    permanentConfirmation: PermanentDeletionConfirmation?
  ) -> CleanupCommandRefusal? {
    guard case .reviewing(let review) = state, !isTransitionPending else { return .notReviewing }
    guard !review.selectedFindingIDs.isEmpty else { return .emptySelection }
    if let scope = permanentDeletionScope() {
      guard let confirmation = permanentConfirmation else {
        return .permanentDeletionUnconfirmed(required: scope)
      }
      guard confirmation.fileCount == scope.fileCount, confirmation.byteTotal == scope.byteTotal
      else {
        return .confirmationMismatch(required: scope)
      }
    }
    isTransitionPending = true
    lifecycleEpoch &+= 1
    let epoch = lifecycleEpoch
    executionTask = Task {
      await runExecution(review: review, confirmation: permanentConfirmation, epoch: epoch)
    }
    return nil
  }

  /// The confirmed cancellation of a running scan: scanning to idle, partial
  /// findings discarded. Safe by construction, because a scan has no side
  /// effects on disk.
  public func cancelScan() {
    guard case .scanning = state else { return }
    lifecycleEpoch &+= 1
    scanTask?.cancel()
    scanTask = nil
    isTransitionPending = false
    state = .idle
  }

  /// Requests cancellation of the running plan. Cancellation takes effect
  /// between operations, never mid item; the state remains executing until
  /// the executor's terminal report arrives, then moves to result, whose
  /// summary is the partial result screen.
  public func cancelExecution() {
    guard case .executing = state, !isExecutionCancellationRequested else { return }
    isExecutionCancellationRequested = true
  }

  /// Result or cleanSweep to idle.
  public func acknowledgeResult() {
    switch state {
    case .result, .cleanSweep:
      state = .idle
    case .idle, .scanning, .reviewing, .executing:
      return
    }
  }

  // MARK: - Scanning

  private func runScan(epoch: UInt64) async {
    let loadedSettings = await settings.load()
    let degradedState = await degraded.current()
    let context = await sessions.makeScanContext(
      settings: loadedSettings,
      hasFullDiskAccess: degradedState.hasFullDiskAccess
    )
    guard epoch == lifecycleEpoch else { return }
    cachedSettings = loadedSettings
    degradedNotices = []
    appendDegradedNotices(degradedState.unavailable)
    hubEstimateBytes = 0
    let accumulator = ScanAccumulator(sessionID: context.sessionID)
    state = .scanning(accumulator.progress)
    isTransitionPending = false
    await consumeScanStream(context: context, accumulator: accumulator, epoch: epoch)
  }

  private func consumeScanStream(
    context: ScanContext,
    accumulator initial: ScanAccumulator,
    epoch: UInt64
  ) async {
    var accumulator = initial
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
      failureNotice = Self.plainSentence(
        for: error,
        fallback: "The scan could not be completed."
      )
    }
  }

  private func apply(_ event: ScanEvent, to accumulator: inout ScanAccumulator) {
    switch event {
    case .phase(let phase):
      accumulator.advance(to: phase)
      state = .scanning(accumulator.progress)
    case .progress(let counters):
      accumulator.merge(counters)
      state = .scanning(accumulator.progress)
      hubEstimateBytes = accumulator.progress.counters.bytesReclaimable
    case .finding(let finding):
      accumulator.append(finding)
    case .degraded(let unavailable):
      appendDegradedNotices([unavailable])
    }
  }

  private func finishScan(with accumulator: ScanAccumulator) {
    guard !accumulator.findings.isEmpty else {
      state = .cleanSweep(filesChecked: accumulator.progress.counters.filesSeen)
      hubEstimateBytes = 0
      return
    }
    let review = CleanupReviewState(
      sessionID: accumulator.sessionID,
      categories: accumulator.categories,
      selectedFindingIDs: Set(
        accumulator.findings
          .filter { $0.isPreselected && $0.risk == .safe }
          .map(\.id)
      )
    )
    state = .reviewing(review)
    hubEstimateBytes = review.selectedByteTotal
  }

  /// Accumulates one scan session's stream: monotonic counters, forward only
  /// phases, and findings grouped by category in order of first appearance.
  /// Findings that do not belong to the session are dropped, so every
  /// reviewed finding provably belongs to it.
  private struct ScanAccumulator {
    let sessionID: UUID
    private(set) var findings: [Finding] = []
    private var phase = ScanPhase.indeterminate
    private var counters = ScanCounters.zero
    private var categoryOrder: [FindingCategory] = []
    private var findingsByCategory: [FindingCategory: [Finding]] = [:]

    init(sessionID: UUID) {
      self.sessionID = sessionID
    }

    var progress: CleanupScanProgress {
      CleanupScanProgress(sessionID: sessionID, phase: phase, counters: counters)
    }

    var categories: [CleanupReviewCategory] {
      categoryOrder.map {
        CleanupReviewCategory(category: $0, findings: findingsByCategory[$0] ?? [])
      }
    }

    mutating func advance(to next: ScanPhase) {
      guard Self.rank(of: next) >= Self.rank(of: phase) else { return }
      phase = next
    }

    mutating func merge(_ next: ScanCounters) {
      counters = ScanCounters(
        filesSeen: max(counters.filesSeen, next.filesSeen),
        bytesReclaimable: max(counters.bytesReclaimable, next.bytesReclaimable),
        itemCount: max(counters.itemCount, next.itemCount)
      )
    }

    mutating func append(_ finding: Finding) {
      guard finding.sessionID == sessionID else { return }
      findings.append(finding)
      if findingsByCategory[finding.category] == nil {
        categoryOrder.append(finding.category)
      }
      findingsByCategory[finding.category, default: []].append(finding)
    }

    private static func rank(of phase: ScanPhase) -> Int {
      switch phase {
      case .indeterminate: return 0
      case .determinate: return 1
      case .settling: return 2
      }
    }
  }

  // MARK: - Execution

  private func runExecution(
    review: CleanupReviewState,
    confirmation: PermanentDeletionConfirmation?,
    epoch: UInt64
  ) async {
    let currentSettings = await settings.load()
    let planContext = await sessions.makePlanContext(
      sessionID: review.sessionID,
      settings: currentSettings
    )
    guard epoch == lifecycleEpoch else { return }
    cachedSettings = currentSettings
    let plan: OperationPlan
    do {
      plan = attach(
        confirmation, to: try engine.plan(selection: review.selectedFindings, context: planContext))
    } catch {
      isTransitionPending = false
      failureNotice = Self.planFailureSentence(for: error)
      return
    }
    state = .executing(
      CleanupExecutionProgress(
        planID: plan.id,
        totalOperations: UInt32(plan.operations.count),
        finishedOperations: 0,
        bytesReclaimed: 0,
        currentOperationID: nil
      )
    )
    isTransitionPending = false
    isExecutionCancellationRequested = false
    await consumeExecutionStream(plan: plan, review: review, epoch: epoch)
  }

  /// The model attaches the caller's confirmation to the plan and never
  /// constructs one itself, because the confirmation is evidence the user
  /// saw the counts.
  private func attach(
    _ confirmation: PermanentDeletionConfirmation?,
    to plan: OperationPlan
  ) -> OperationPlan {
    OperationPlan(
      id: plan.id,
      sessionID: plan.sessionID,
      operations: plan.operations,
      totalBytes: plan.totalBytes,
      permanentDeletionConfirmation: confirmation
    )
  }

  private func consumeExecutionStream(
    plan: OperationPlan,
    review: CleanupReviewState,
    epoch: UInt64
  ) async {
    var refusalSentences: [String] = []
    for await event in executor.execute(plan) {
      guard epoch == lifecycleEpoch else { return }
      switch event {
      case .refused(let refusal):
        refusalSentences.append(Self.sentence(for: refusal))
      case .operationStarted(let operationID):
        updateExecutionProgress { $0.starting(operationID: operationID) }
      case .operationFinished(_, let result):
        updateExecutionProgress { $0.finishing(result: result) }
      case .planCompleted(let report):
        finishExecution(report: report, plan: plan, review: review, refusals: refusalSentences)
      }
    }
  }

  private func updateExecutionProgress(
    _ transform: (CleanupExecutionProgress) -> CleanupExecutionProgress
  ) {
    guard case .executing(let progress) = state else { return }
    let next = transform(progress)
    state = .executing(next)
    hubEstimateBytes = next.bytesReclaimed
  }

  private func finishExecution(
    report: ExecutionReport,
    plan: OperationPlan,
    review: CleanupReviewState,
    refusals: [String]
  ) {
    let summary = CleanupResultSummary(
      report: report, plan: plan, review: review, refusals: refusals)
    state = .result(summary)
    hubEstimateBytes = summary.bytesReclaimed
    isExecutionCancellationRequested = false
  }

  // MARK: - Shared helpers

  private func applySelection(_ selection: Set<UUID>, to review: CleanupReviewState) {
    let next = CleanupReviewState(
      sessionID: review.sessionID,
      categories: review.categories,
      selectedFindingIDs: selection
    )
    state = .reviewing(next)
    hubEstimateBytes = next.selectedByteTotal
  }

  /// The banner never contains duplicates or empty strings, and sentences
  /// append in arrival order.
  private func appendDegradedNotices(_ sentences: [String]) {
    for sentence in sentences
    where !sentence.isEmpty && !degradedNotices.contains(sentence) {
      degradedNotices.append(sentence)
    }
  }

  private func consumeSettingsUpdates() {
    let stream = settings.updates()
    settingsUpdatesTask = Task { [weak self] in
      for await updated in stream {
        guard let self else { return }
        self.cachedSettings = updated
      }
    }
  }

  /// Trash bin contents always plan as permanent deletion, whatever the
  /// mode; everything else follows the deletion mode.
  private func plansPermanently(
    _ category: FindingCategory,
    mode: Settings.DeletionMode
  ) -> Bool {
    if case .trashBin = category { return true }
    return mode == .permanent
  }

  private static func sentence(for refusal: ExecutionRefusal) -> String {
    switch refusal {
    case .permanentDeletionUnconfirmed:
      return "The permanent deletion was not confirmed, so nothing was removed."
    case .helperUnavailable(let reason):
      return reason
    }
  }

  private static func planFailureSentence(for error: any Error) -> String {
    guard let planningError = error as? PlanningError else {
      return plainSentence(for: error, fallback: "The cleanup could not be planned.")
    }
    switch planningError {
    case .emptySelection:
      return "Nothing is selected, so there is nothing to clean."
    case .findingFromDifferentSession:
      return
        "The selection came from an earlier scan, so nothing was removed. Scan again to refresh it."
    case .keptCopyMissing:
      return "The kept copy of a set was missing from the selection, so nothing was removed."
    }
  }

  private static func plainSentence(for error: any Error, fallback: String) -> String {
    guard let described = (error as? any LocalizedError)?.errorDescription,
      !described.isEmpty
    else { return fallback }
    return described
  }
}

extension CleanupExecutionProgress {
  fileprivate func starting(operationID: UUID) -> CleanupExecutionProgress {
    CleanupExecutionProgress(
      planID: planID,
      totalOperations: totalOperations,
      finishedOperations: finishedOperations,
      bytesReclaimed: bytesReclaimed,
      currentOperationID: operationID
    )
  }

  fileprivate func finishing(result: OperationResult) -> CleanupExecutionProgress {
    var reclaimed = bytesReclaimed
    if case .completed(let bytes) = result {
      reclaimed += bytes
    }
    return CleanupExecutionProgress(
      planID: planID,
      totalOperations: totalOperations,
      finishedOperations: finishedOperations + 1,
      bytesReclaimed: reclaimed,
      currentOperationID: nil
    )
  }
}
