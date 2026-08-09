import Foundation
import GleamCore
import GleamHub
import Observation
import SpaceLensEngine

/// The Space Lens module view model, on the macOS 14 Observation framework.
/// A thin SwiftUI view renders this and adds no state of its own; the
/// module's whole behaviour is this class driven against its five injected
/// protocols.
///
/// State transitions are total and deterministic: every command in every
/// state either performs its named transition or leaves the state identical.
/// The model never touches the file system (the disk is reachable only
/// through the engine's map stream and the executor) and never reads a
/// clock: every date it holds arrived in an input. There is no hub estimate
/// interplay: Space Lens has no hub card, contributes nothing to the hub's
/// figures, and its reclaimed bytes surface only on its own result screen.
@MainActor @Observable
public final class SpaceLensModuleModel {
  public private(set) var state: SpaceLensModuleState = .idle
  public private(set) var failureNotice: String?

  @ObservationIgnored private let engine: any SpaceLensMapProviding
  @ObservationIgnored private let executor: any PlanExecuting
  @ObservationIgnored private let settings: any SettingsStoring
  @ObservationIgnored private let sessions: any SpaceLensSessionProviding
  @ObservationIgnored private let access: any FullDiskAccessMonitoring

  /// Bumped by every accepted lifecycle command. In flight work captures the
  /// value at launch and applies effects only while it still matches, so a
  /// superseded mapping or execution can never write into a later lifecycle.
  @ObservationIgnored private var lifecycleEpoch: UInt64 = 0
  /// True from a lifecycle command's acceptance until its asynchronous
  /// transition lands, so a second command cannot slip into the gap.
  @ObservationIgnored private var isTransitionPending = false
  @ObservationIgnored private var mapTask: Task<Void, Never>?
  @ObservationIgnored private var watchdogTask: Task<Void, Never>?
  @ObservationIgnored private var hasSettledBacklog = false
  @ObservationIgnored private var appliedUpdateCount: UInt64 = 0
  @ObservationIgnored private var executionTask: Task<Void, Never>?
  @ObservationIgnored private var settingsUpdatesTask: Task<Void, Never>?
  @ObservationIgnored private var isExecutionCancellationRequested = false
  @ObservationIgnored private var cachedSettings = Settings.defaults
  @ObservationIgnored private var tree: MapTree?
  @ObservationIgnored private var focusPath: AbsolutePath?
  @ObservationIgnored private var selectedPaths: Set<AbsolutePath> = []

  public init(
    engine: any SpaceLensMapProviding,
    executor: any PlanExecuting,
    settings: any SettingsStoring,
    sessions: any SpaceLensSessionProviding,
    access: any FullDiskAccessMonitoring
  ) {
    precondition(
      engine.module == .spaceLens,
      "SpaceLensModuleModel requires the space lens engine, not \(engine.module)."
    )
    self.engine = engine
    self.executor = executor
    self.settings = settings
    self.sessions = sessions
    self.access = access
    consumeSettingsUpdates()
  }

  deinit {
    mapTask?.cancel()
    watchdogTask?.cancel()
    executionTask?.cancel()
    settingsUpdatesTask?.cancel()
  }

  // MARK: - Commands

  /// Idle, browsing or result to mapping with a fresh session and an empty
  /// map state focused on the volume root. Ignored while mapping or
  /// executing.
  public func startMapping(volume: AbsolutePath) {
    switch state {
    case .mapping, .executing:
      return
    case .idle, .browsing, .result:
      break
    }
    guard !isTransitionPending else { return }
    isTransitionPending = true
    failureNotice = nil
    lifecycleEpoch &+= 1
    let epoch = lifecycleEpoch
    mapTask = Task { await runMapping(volume: volume, epoch: epoch) }
  }

  /// Focus moves into a directory child of the current focus, and the
  /// returned drill carries zoomIn. Anything else returns nil and changes
  /// nothing. While the stream is still running a child that has not
  /// streamed yet is accepted on faith and reconciled when the map
  /// completes; once browsing, only nodes present in the tree qualify.
  @discardableResult
  public func drillIn(to path: AbsolutePath) -> SpaceLensDrill? {
    guard isNavigable, let tree, let focus = focusPath else { return nil }
    if let entry = tree.entry(at: path) {
      guard entry.isDirectory, entry.parent == focus else { return nil }
    } else {
      guard case .mapping = state, parentPath(of: path) == focus else { return nil }
    }
    focusPath = path
    publishMap()
    return SpaceLensDrill(target: path, direction: .zoomIn)
  }

  /// Focus moves to its parent when focus is not the volume root, and the
  /// returned drill carries zoomOut. At the root it returns nil and changes
  /// nothing; leaving the module is the chrome's job, not this model's.
  @discardableResult
  public func drillOut() -> SpaceLensDrill? {
    guard isNavigable, let tree, let focus = focusPath, focus != tree.volume else { return nil }
    guard let parent = tree.entry(at: focus)?.parent ?? parentPath(of: focus) else { return nil }
    focusPath = parent
    publishMap()
    return SpaceLensDrill(target: parent, direction: .zoomOut)
  }

  /// Selection change only, while mapping or browsing. A selected path
  /// deselects. An unselected selectable path selects, first removing any
  /// selected descendants (the ancestor covers them). A path that is
  /// unknown, unselectable or covered by a selected ancestor is the
  /// identity, which keeps the antichain and the denylist rule true by
  /// construction.
  public func toggleSelection(_ path: AbsolutePath) {
    guard isNavigable, let tree else { return }
    if selectedPaths.contains(path) {
      selectedPaths.remove(path)
      publishMap()
      return
    }
    if let entry = tree.entry(at: path) {
      guard entry.isSelectable else { return }
    } else {
      // While the stream is still running a path that has not streamed yet
      // is selected on faith and reconciled as nodes arrive; the volume
      // itself is never selectable, known without the tree.
      guard case .mapping = state, path != tree.volume, path.isDescendant(of: tree.volume)
      else { return }
    }
    guard !selectedPaths.contains(where: { path.isDescendant(of: $0) }) else { return }
    selectedPaths = selectedPaths.filter { !$0.isDescendant(of: path) }
    selectedPaths.insert(path)
    publishMap()
  }

  /// The exact operation count and byte total the current selection would
  /// plan as permanent deletion under the current mode: every selected node
  /// when the mode is permanent, nil when the mode is trash. Nil in every
  /// other state.
  public func permanentDeletionScope() -> PermanentDeletionScope? {
    guard case .browsing(let map) = state else { return nil }
    guard cachedSettings.deletionMode == .permanent else { return nil }
    guard !map.selectedPaths.isEmpty else { return nil }
    return PermanentDeletionScope(
      fileCount: UInt32(map.selectedPaths.count),
      byteTotal: map.selectedByteTotal
    )
  }

  /// Builds the plan for the current selection and starts executing it. A
  /// non nil refusal is returned and nothing changes otherwise; every
  /// refusal is decided before the engine or executor is touched.
  @discardableResult
  public func executeSelection(
    permanentConfirmation: PermanentDeletionConfirmation?
  ) -> SpaceLensCommandRefusal? {
    let map: SpaceLensMapState
    switch state {
    case .mapping:
      return .mappingStillRunning
    case .browsing(let browsing):
      map = browsing
    case .idle, .executing, .result:
      return .notBrowsing
    }
    guard !isTransitionPending else { return .notBrowsing }
    guard !map.selectedPaths.isEmpty else { return .emptySelection }
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
      await runExecution(map: map, confirmation: permanentConfirmation, epoch: epoch)
    }
    return nil
  }

  /// The confirmed cancellation of a running mapping: mapping to idle, the
  /// partial map discarded. Safe by construction, because mapping is read
  /// only and has no side effects on disk.
  public func cancelMapping() {
    guard case .mapping = state else { return }
    lifecycleEpoch &+= 1
    mapTask?.cancel()
    mapTask = nil
    watchdogTask?.cancel()
    watchdogTask = nil
    isTransitionPending = false
    discardMap()
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

  /// Result to idle. Never back to a map: an executed plan means the tree no
  /// longer matches the disk, and a stale map is worse than no map.
  public func acknowledgeResult() {
    guard case .result = state else { return }
    discardMap()
    state = .idle
  }

  // MARK: - Mapping

  private func runMapping(volume: AbsolutePath, epoch: UInt64) async {
    let loadedSettings = await settings.load()
    let hasFullDiskAccess = await access.isGranted
    let context = await sessions.makeScanContext(
      settings: loadedSettings,
      hasFullDiskAccess: hasFullDiskAccess
    )
    guard epoch == lifecycleEpoch else { return }
    cachedSettings = loadedSettings
    let stream = engine.map(volume: volume, context: context)
    tree = MapTree(volume: volume, sessionID: context.sessionID)
    focusPath = volume
    selectedPaths = []
    hasSettledBacklog = false
    appliedUpdateCount = 0
    if let map = currentMap() {
      state = .mapping(map)
    }
    isTransitionPending = false
    startBacklogWatchdog(epoch: epoch)
    await consumeMapStream(stream, epoch: epoch)
  }

  /// The mapping state publishes immediately and empty, but the growing
  /// tree is withheld from publication until the updates the engine had
  /// already streamed are applied, so the first tree carrying state shows
  /// the whole backlog rather than an arbitrary prefix. The watchdog is
  /// turn based, not clock based: once consumption stalls for a few main
  /// actor turns the backlog is provably drained.
  private func startBacklogWatchdog(epoch: UInt64) {
    watchdogTask = Task { @MainActor [weak self] in
      var lastCount = self?.appliedUpdateCount ?? 0
      var stalledTurns = 0
      for _ in 0..<1000 {
        await Task.yield()
        guard let self, epoch == self.lifecycleEpoch, !self.hasSettledBacklog else { return }
        if self.appliedUpdateCount == lastCount {
          stalledTurns += 1
          if stalledTurns >= 3 {
            self.hasSettledBacklog = true
            self.publishMap()
            return
          }
        } else {
          lastCount = self.appliedUpdateCount
          stalledTurns = 0
        }
      }
      guard let self, epoch == self.lifecycleEpoch else { return }
      self.hasSettledBacklog = true
      self.publishMap()
    }
  }

  /// Consumes the map stream on the main actor. On macOS 15 the iterator is
  /// driven with the caller's isolation, so buffered updates apply without
  /// leaving the actor between elements.
  private func consumeMapStream(
    _ stream: AsyncThrowingStream<SpaceLensUpdate, Error>,
    epoch: UInt64
  ) async {
    do {
      if #available(macOS 15.0, *) {
        var iterator = stream.makeAsyncIterator()
        while let update = try await iterator.next(isolation: MainActor.shared) {
          guard epoch == lifecycleEpoch else { return }
          apply(update)
        }
      } else {
        for try await update in stream {
          guard epoch == lifecycleEpoch else { return }
          apply(update)
        }
      }
    } catch {
      guard epoch == lifecycleEpoch else { return }
      if error is CancellationError { return }
      discardMap()
      watchdogTask?.cancel()
      hasSettledBacklog = true
      isTransitionPending = false
      state = .idle
      failureNotice = Self.plainSentence(
        for: error,
        fallback: "The disk map could not be completed."
      )
    }
  }

  private func apply(_ update: SpaceLensUpdate) {
    appliedUpdateCount &+= 1
    switch update {
    case .node(let node):
      tree?.absorb(node)
      reconcileIntentions(with: node)
      if hasSettledBacklog { publishMap() }
    case .sizeRevision(let path, let subtreeBytes):
      tree?.grow(path, to: subtreeBytes)
      if hasSettledBacklog { publishMap() }
    case .completed:
      tree?.convergeAll()
      reconcileIntentionsAtCompletion()
      watchdogTask?.cancel()
      hasSettledBacklog = true
      publishMap(completed: true)
    }
  }

  /// A selection or drill accepted on faith while mapping is checked against
  /// the node once it streams: a node that turns out unselectable leaves the
  /// selection.
  private func reconcileIntentions(with node: SpaceLensNode) {
    guard let tree else { return }
    if selectedPaths.contains(node.path), tree.entry(at: node.path)?.isSelectable != true {
      selectedPaths.remove(node.path)
    }
  }

  /// When the stream completes the tree is final: pending intentions that
  /// never materialised are dropped, so the browsing state's guarantees hold
  /// exactly. A pruned drill intention falls back to the deepest streamed
  /// ancestor of its target, so the user lands as close as the tree allows,
  /// at the volume root only when no streamed ancestor exists.
  private func reconcileIntentionsAtCompletion() {
    guard let tree else { return }
    selectedPaths = selectedPaths.filter { tree.entry(at: $0)?.isSelectable == true }
    if let focus = focusPath, focus != tree.volume, tree.entry(at: focus)?.isDirectory != true {
      focusPath = deepestStreamedAncestor(of: focus, in: tree)
    }
  }

  private func deepestStreamedAncestor(of path: AbsolutePath, in tree: MapTree) -> AbsolutePath {
    var candidate = parentPath(of: path)
    while let current = candidate, current != tree.volume {
      if tree.entry(at: current)?.isDirectory == true {
        return current
      }
      candidate = parentPath(of: current)
    }
    return tree.volume
  }

  /// The containing directory, computed on the normalised value, for
  /// intentions whose node has not streamed yet. Nil at the file system
  /// root.
  private func parentPath(of path: AbsolutePath) -> AbsolutePath? {
    guard path.value != "/" else { return nil }
    let components = path.value.split(separator: "/").dropLast()
    guard !components.isEmpty else { return AbsolutePath(normalising: "/") }
    return AbsolutePath(normalising: "/" + components.joined(separator: "/"))
  }

  private func currentMap() -> SpaceLensMapState? {
    guard let tree, let focus = focusPath else { return nil }
    return SpaceLensMapState(
      sessionID: tree.sessionID,
      volume: tree.volume,
      root: tree.buildRoot(),
      focusPath: focus,
      selectedPaths: selectedPaths
    )
  }

  /// Publishes the current map into the lifecycle state. `completed` moves
  /// mapping to browsing with the identical map state: tree, focus and
  /// selection all survive the transition.
  private func publishMap(completed: Bool = false) {
    guard let map = currentMap() else { return }
    switch state {
    case .mapping:
      state = completed ? .browsing(map) : .mapping(map)
    case .browsing:
      state = .browsing(map)
    case .idle, .executing, .result:
      return
    }
  }

  private var isNavigable: Bool {
    switch state {
    case .mapping, .browsing: return true
    case .idle, .executing, .result: return false
    }
  }

  private func discardMap() {
    tree = nil
    focusPath = nil
    selectedPaths = []
  }

  // MARK: - Execution

  /// Mints one finding per selected node: category spaceLensSelection, risk
  /// review, never preselected, the map's session identifier, and exactly
  /// one entry carrying the node's path and its converged allocated total.
  /// Byte totals therefore derive from the finding's own entries; no cache,
  /// no second source of truth.
  private func mintFindings(from map: SpaceLensMapState) -> [Finding] {
    var bytesByPath: [AbsolutePath: UInt64] = [:]
    if let root = map.root {
      var stack = [root]
      while let node = stack.popLast() {
        bytesByPath[node.path] = node.allocatedBytesSoFar
        stack.append(contentsOf: node.children)
      }
    }
    let ordered = map.selectedPaths.sorted { first, second in
      let firstBytes = bytesByPath[first] ?? 0
      let secondBytes = bytesByPath[second] ?? 0
      guard firstBytes == secondBytes else { return firstBytes > secondBytes }
      return first < second
    }
    return ordered.map { path in
      let bytes = bytesByPath[path] ?? 0
      return Finding(
        id: UUID(),
        sessionID: map.sessionID,
        category: .spaceLensSelection,
        entries: [PathEntry(path: path, allocatedBytes: bytes)],
        risk: .review,
        explanation:
          "You chose \(path.value) on the disk map, and removing it reclaims its "
          + "allocated space.",
        isPreselected: false
      )
    }
  }

  private func runExecution(
    map: SpaceLensMapState,
    confirmation: PermanentDeletionConfirmation?,
    epoch: UInt64
  ) async {
    let currentSettings = await settings.load()
    let planContext = await sessions.makePlanContext(
      sessionID: map.sessionID,
      settings: currentSettings
    )
    guard epoch == lifecycleEpoch else { return }
    cachedSettings = currentSettings
    let plan: OperationPlan
    do {
      plan = attach(
        confirmation,
        to: try engine.plan(selection: mintFindings(from: map), context: planContext)
      )
    } catch {
      isTransitionPending = false
      failureNotice = Self.planFailureSentence(for: error)
      return
    }
    state = .executing(
      SpaceLensExecutionProgress(
        planID: plan.id,
        totalOperations: UInt32(plan.operations.count),
        finishedOperations: 0,
        bytesReclaimed: 0,
        currentOperationID: nil
      )
    )
    isTransitionPending = false
    isExecutionCancellationRequested = false
    await consumeExecutionStream(plan: plan, epoch: epoch)
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

  private func consumeExecutionStream(plan: OperationPlan, epoch: UInt64) async {
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
        finishExecution(report: report, plan: plan, refusals: refusalSentences)
      }
    }
  }

  private func updateExecutionProgress(
    _ transform: (SpaceLensExecutionProgress) -> SpaceLensExecutionProgress
  ) {
    guard case .executing(let progress) = state else { return }
    state = .executing(transform(progress))
  }

  private func finishExecution(
    report: ExecutionReport,
    plan: OperationPlan,
    refusals: [String]
  ) {
    let summary = SpaceLensResultSummary(report: report, plan: plan, refusals: refusals)
    discardMap()
    state = .result(summary)
    isExecutionCancellationRequested = false
  }

  // MARK: - Shared helpers

  private func consumeSettingsUpdates() {
    let stream = settings.updates()
    settingsUpdatesTask = Task { [weak self] in
      for await updated in stream {
        guard let self else { return }
        self.cachedSettings = updated
      }
    }
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
      return plainSentence(for: error, fallback: "The removal could not be planned.")
    }
    switch planningError {
    case .emptySelection:
      return "Nothing is selected, so there is nothing to remove."
    case .findingFromDifferentSession:
      return
        "The selection came from an earlier map, so nothing was removed. Map again to refresh it."
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

// MARK: - The growing tree

/// The model's flat mirror of the engine's stream, rebuilt into the published
/// tree after every update. Per path totals only ever grow, an orphan node
/// (one whose parent has not streamed) is dropped rather than rendered
/// floating, and the volume root is never selectable whatever the engine
/// says.
private struct MapTree {
  struct Entry {
    let parent: AbsolutePath?
    let isDirectory: Bool
    var bytes: UInt64
    var hasConverged: Bool
    var isSelectable: Bool
    var children: [AbsolutePath]
  }

  let volume: AbsolutePath
  let sessionID: UUID
  private var entries: [AbsolutePath: Entry] = [:]

  init(volume: AbsolutePath, sessionID: UUID) {
    self.volume = volume
    self.sessionID = sessionID
  }

  func entry(at path: AbsolutePath) -> Entry? {
    entries[path]
  }

  mutating func absorb(_ node: SpaceLensNode) {
    if var existing = entries[node.path] {
      existing.bytes = max(existing.bytes, node.subtreeBytes)
      entries[node.path] = existing
      return
    }
    if node.path == volume {
      entries[volume] = Entry(
        parent: nil,
        isDirectory: node.isDirectory,
        bytes: node.subtreeBytes,
        hasConverged: false,
        isSelectable: false,
        children: []
      )
      return
    }
    guard let parent = node.parent, entries[parent] != nil else { return }
    entries[node.path] = Entry(
      parent: parent,
      isDirectory: node.isDirectory,
      bytes: node.subtreeBytes,
      hasConverged: false,
      isSelectable: node.isSelectable,
      children: []
    )
    entries[parent]?.children.append(node.path)
  }

  mutating func grow(_ path: AbsolutePath, to subtreeBytes: UInt64) {
    guard var entry = entries[path] else { return }
    entry.bytes = max(entry.bytes, subtreeBytes)
    entries[path] = entry
  }

  mutating func convergeAll() {
    for path in entries.keys {
      entries[path]?.hasConverged = true
    }
  }

  func buildRoot() -> SpaceLensTreeNode? {
    buildNode(at: volume)
  }

  private func buildNode(at path: AbsolutePath) -> SpaceLensTreeNode? {
    guard let entry = entries[path] else { return nil }
    let children = entry.children
      .compactMap(buildNode(at:))
      .sorted { first, second in
        guard first.allocatedBytesSoFar == second.allocatedBytesSoFar else {
          return first.allocatedBytesSoFar > second.allocatedBytesSoFar
        }
        return first.path < second.path
      }
    return SpaceLensTreeNode(
      path: path,
      isDirectory: entry.isDirectory,
      allocatedBytesSoFar: entry.bytes,
      hasConverged: entry.hasConverged,
      isSelectable: entry.isSelectable,
      children: children
    )
  }
}

extension SpaceLensResultSummary {
  /// Derives the result screen's content from exactly one execution report,
  /// consistent with it: the byte total is the report's, the counts sum to
  /// one entry per operation, failed operations contribute their plain
  /// sentences in plan order, denylist skips contribute their last path
  /// components in plan order, and execution refusals surface as failure
  /// sentences after them, never a crash and never a silent drop.
  init(report: ExecutionReport, plan: OperationPlan, refusals: [String]) {
    let operationsByID = Dictionary(
      plan.operations.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var completed: UInt32 = 0
    var failed: UInt32 = 0
    var notStarted: UInt32 = 0
    var failureSentences: [String] = []
    var skippedNames: [String] = []
    for entry in report.results {
      switch entry.result {
      case .completed:
        completed += 1
      case .failed(let reason):
        failed += 1
        failureSentences.append(reason)
      case .skippedDenylisted:
        if let name = operationsByID[entry.operationID]?.targetLastComponent {
          skippedNames.append(name)
        }
      case .notStarted:
        notStarted += 1
      }
    }
    self.init(
      bytesReclaimed: report.bytesReclaimed,
      completedCount: completed,
      failedCount: failed,
      notStartedCount: notStarted,
      failures: failureSentences + refusals,
      skippedDenylistedNames: skippedNames
    )
  }
}

extension SpaceLensExecutionProgress {
  fileprivate func starting(operationID: UUID) -> SpaceLensExecutionProgress {
    SpaceLensExecutionProgress(
      planID: planID,
      totalOperations: totalOperations,
      finishedOperations: finishedOperations,
      bytesReclaimed: bytesReclaimed,
      currentOperationID: operationID
    )
  }

  fileprivate func finishing(result: OperationResult) -> SpaceLensExecutionProgress {
    var reclaimed = bytesReclaimed
    if case .completed(let bytes) = result {
      reclaimed += bytes
    }
    return SpaceLensExecutionProgress(
      planID: planID,
      totalOperations: totalOperations,
      finishedOperations: finishedOperations + 1,
      bytesReclaimed: reclaimed,
      currentOperationID: nil
    )
  }
}

extension GleamCore.Operation {
  fileprivate var targetLastComponent: String? {
    switch kind {
    case .moveToTrash(let target), .deletePermanently(let target),
      .quarantine(let target), .archive(let target, _):
      return target.lastComponent
    case .setLaunchItemEnabled, .runMaintenance:
      return nil
    }
  }
}
