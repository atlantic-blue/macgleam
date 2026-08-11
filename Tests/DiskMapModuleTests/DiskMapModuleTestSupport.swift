import DiskMapEngine
import DiskMapModule
import Foundation
import GleamCore
import GleamHub
import Testing

/// Foundation exports NSOperation as `Operation`; this pins the unqualified
/// name to the domain type for the whole module.
typealias Operation = GleamCore.Operation

// MARK: - Fixtures

enum LensModuleFixture {

  static let confirmationInstant = Date(timeIntervalSince1970: 1_760_000_000)
  static let executionStart = Date(timeIntervalSince1970: 1_760_000_100)
  static let executionEnd = Date(timeIntervalSince1970: 1_760_000_200)

  static let sessionA = uuid(0xA1)
  static let sessionB = uuid(0xA2)
  static let sessionC = uuid(0xA3)

  static func uuid(_ suffix: UInt8) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000000%02X", suffix))!
  }

  static func path(_ value: String) -> AbsolutePath {
    AbsolutePath(normalising: value)
  }

  static func settings(mode: Settings.DeletionMode = .trash) -> Settings {
    Settings(
      deletionMode: mode,
      largeFileThresholdBytes: 1_073_741_824,
      oldFileThresholdDays: 180,
      menuBar: MenuBarPreferences(
        showsStorage: true, showsMemory: false, showsProcessorLoad: false),
      motion: MotionPreferences(reduceMotionOverride: nil)
    )
  }

  static let emptyCatalog = RuleCatalog(
    version: RuleCatalogVersion(value: 1),
    signature: Data(),
    cleanupRules: [],
    adwareRules: [],
    denylist: Denylist(patterns: [])
  )

  // The standard scripted volume. The engine fake streams these; every
  // module test reads the model's published tree against them.
  static let volume = path("/Volumes/Lens")
  static let mediaDirectory = path("/Volumes/Lens/Media")
  static let filmFile = path("/Volumes/Lens/Media/film.mov")
  static let clipFile = path("/Volumes/Lens/Media/clip.mov")
  static let documentsDirectory = path("/Volumes/Lens/Documents")
  static let protectedDirectory = path("/Volumes/Lens/Protected")

  static let mediaBytes: UInt64 = 10_000
  static let filmBytes: UInt64 = 6_000
  static let clipBytes: UInt64 = 4_000
  static let documentsBytes: UInt64 = 1_500
  static let protectedBytes: UInt64 = 800
  static let volumeBytes: UInt64 = 12_300

  static func node(
    _ path: AbsolutePath,
    parent: AbsolutePath?,
    isDirectory: Bool,
    subtreeBytes: UInt64,
    isSelectable: Bool = true
  ) -> DiskMapNode {
    DiskMapNode(
      path: path,
      parent: parent,
      isDirectory: isDirectory,
      subtreeBytes: subtreeBytes,
      isSelectable: isSelectable
    )
  }
}

func makeConfirmation(
  fileCount: UInt32,
  byteTotal: UInt64,
  confirmedAt: Date = LensModuleFixture.confirmationInstant
) -> PermanentDeletionConfirmation {
  PermanentDeletionConfirmation(
    fileCount: fileCount, byteTotal: byteTotal, confirmedAt: confirmedAt)
}

func makeReport(
  planID: UUID,
  results: [(UUID, OperationResult)],
  bytesReclaimed: UInt64
) -> ExecutionReport {
  ExecutionReport(
    planID: planID,
    results: results.map { (operationID: $0.0, result: $0.1) },
    bytesReclaimed: bytesReclaimed,
    startedAt: LensModuleFixture.executionStart,
    finishedAt: LensModuleFixture.executionEnd
  )
}

// MARK: - File system that must never be called

struct RefusedFileSystemAccess: Error {}

/// Handed to every scan context. The model never touches the file system
/// (C39 purity), so any call through this type is a recorded test failure.
final class RefusingFileSystem: FileSystemReading, @unchecked Sendable {
  private let lock = NSLock()
  private var violations: [String] = []

  var violationCount: Int { lock.withLock { violations.count } }

  private func refuse(_ name: String) {
    lock.withLock { violations.append(name) }
    Issue.record("the disk map model touched the file system through \(name)")
  }

  func enumerate(
    root: AbsolutePath, options: EnumerationOptions
  ) -> AsyncThrowingStream<EnumerationEvent, Error> {
    refuse("enumerate")
    return AsyncThrowingStream { $0.finish(throwing: RefusedFileSystemAccess()) }
  }

  func metadata(at path: AbsolutePath) async throws -> FileRecord {
    refuse("metadata")
    throw RefusedFileSystemAccess()
  }

  func readData(at path: AbsolutePath, maxBytes: UInt64) async throws -> Data {
    refuse("readData")
    throw RefusedFileSystemAccess()
  }

  func extendedAttributes(at path: AbsolutePath) async throws -> [String: Data] {
    refuse("extendedAttributes")
    throw RefusedFileSystemAccess()
  }

  func exists(_ path: AbsolutePath) async -> Bool {
    refuse("exists")
    return false
  }

  func volumeInfo(at path: AbsolutePath) async throws -> VolumeInfo {
    refuse("volumeInfo")
    throw RefusedFileSystemAccess()
  }
}

struct EverythingUserDomainPolicy: PathOwnershipPolicy {
  func ownership(of path: AbsolutePath, environment: OwnershipEnvironment) -> PathOwnership {
    .userDomain
  }
}

// MARK: - Fake map provider

/// A map stream under full test control: the test receives the continuation
/// once the model subscribes, scripts updates, and finishes or fails the
/// stream. Scripted sequences must honour C22 (totals only grow), because
/// the protocol carries C22's guarantees verbatim.
struct MapFeed: Sendable {
  let volume: AbsolutePath
  let context: ScanContext
  let continuation: AsyncThrowingStream<DiskMapUpdate, Error>.Continuation

  func send(_ updates: DiskMapUpdate...) {
    for update in updates { continuation.yield(update) }
  }

  func finish() { continuation.finish() }

  func fail(_ error: any Error) { continuation.finish(throwing: error) }
}

final class FakeDiskMapMapProvider: DiskMapMapProviding, @unchecked Sendable {
  let module: GleamModule

  private let lock = NSLock()
  private var pendingFeeds: [MapFeed] = []
  private var feedWaiters: [CheckedContinuation<MapFeed, Never>] = []
  private var recordedVolumes: [AbsolutePath] = []
  private var recordedMapContexts: [ScanContext] = []
  private var recordedPlanSelections: [[Finding]] = []
  private var recordedPlanContexts: [PlanContext] = []
  private var builtPlans: [OperationPlan] = []
  private var planFailure: (any Error)?
  private var operationSuffix: UInt8 = 0x50
  private var planSuffix: UInt8 = 0x40

  init(module: GleamModule = .diskMap) {
    self.module = module
  }

  var mapCallCount: Int { lock.withLock { recordedMapContexts.count } }
  var lastMappedVolume: AbsolutePath? { lock.withLock { recordedVolumes.last } }
  var lastMapContext: ScanContext? { lock.withLock { recordedMapContexts.last } }
  var planCallCount: Int { lock.withLock { recordedPlanSelections.count } }
  var lastPlanSelection: [Finding]? { lock.withLock { recordedPlanSelections.last } }
  var lastPlanContext: PlanContext? { lock.withLock { recordedPlanContexts.last } }
  var lastPlan: OperationPlan? { lock.withLock { builtPlans.last } }

  func failPlans(with error: any Error) {
    lock.withLock { planFailure = error }
  }

  func map(
    volume: AbsolutePath,
    context: ScanContext
  ) -> AsyncThrowingStream<DiskMapUpdate, Error> {
    let (stream, continuation) = AsyncThrowingStream<DiskMapUpdate, Error>.makeStream()
    let feed = MapFeed(volume: volume, context: context, continuation: continuation)
    lock.lock()
    recordedVolumes.append(volume)
    recordedMapContexts.append(context)
    if feedWaiters.isEmpty {
      pendingFeeds.append(feed)
      lock.unlock()
    } else {
      let waiter = feedWaiters.removeFirst()
      lock.unlock()
      waiter.resume(returning: feed)
    }
    return stream
  }

  /// Awaits the model's subscription to the next map stream.
  func nextMapFeed() async -> MapFeed {
    await withCheckedContinuation { continuation in
      lock.lock()
      if pendingFeeds.isEmpty {
        feedWaiters.append(continuation)
        lock.unlock()
      } else {
        let feed = pendingFeeds.removeFirst()
        lock.unlock()
        continuation.resume(returning: feed)
      }
    }
  }

  /// Expands each selected finding into one operation per entry, trash or
  /// permanent by the context's deletion mode (C22: Trash by default,
  /// identical to Cleanup). The confirmation is left nil: attaching the
  /// caller's confirmation is the model's job.
  func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan {
    lock.lock()
    recordedPlanSelections.append(selection)
    recordedPlanContexts.append(context)
    if let planFailure {
      lock.unlock()
      throw planFailure
    }
    var operations: [Operation] = []
    for finding in selection {
      for entry in finding.entries {
        operationSuffix &+= 1
        operations.append(
          Operation(
            id: LensModuleFixture.uuid(operationSuffix),
            findingID: finding.id,
            kind: context.settings.deletionMode == .permanent
              ? .deletePermanently(target: entry.path)
              : .moveToTrash(target: entry.path),
            privilege: .user
          ))
      }
    }
    planSuffix &+= 1
    let plan = OperationPlan(
      id: LensModuleFixture.uuid(planSuffix),
      sessionID: context.sessionID,
      operations: operations,
      totalBytes: selection.reduce(0) { $0 + $1.byteSize },
      permanentDeletionConfirmation: nil
    )
    builtPlans.append(plan)
    lock.unlock()
    return plan
  }
}

// MARK: - Fake executor

struct ExecutionFeed: Sendable {
  let plan: OperationPlan
  let continuation: AsyncStream<ExecutionEvent>.Continuation

  func send(_ events: ExecutionEvent...) {
    for event in events { continuation.yield(event) }
  }

  func finish() { continuation.finish() }
}

final class FakePlanExecutor: PlanExecuting, @unchecked Sendable {
  private let lock = NSLock()
  private var pendingFeeds: [ExecutionFeed] = []
  private var feedWaiters: [CheckedContinuation<ExecutionFeed, Never>] = []
  private var receivedPlans: [OperationPlan] = []

  var executeCallCount: Int { lock.withLock { receivedPlans.count } }
  var lastPlan: OperationPlan? { lock.withLock { receivedPlans.last } }

  func execute(_ plan: OperationPlan) -> AsyncStream<ExecutionEvent> {
    let (stream, continuation) = AsyncStream<ExecutionEvent>.makeStream()
    let feed = ExecutionFeed(plan: plan, continuation: continuation)
    lock.lock()
    receivedPlans.append(plan)
    if feedWaiters.isEmpty {
      pendingFeeds.append(feed)
      lock.unlock()
    } else {
      let waiter = feedWaiters.removeFirst()
      lock.unlock()
      waiter.resume(returning: feed)
    }
    return stream
  }

  /// Awaits the model handing over a plan for execution.
  func nextExecutionFeed() async -> ExecutionFeed {
    await withCheckedContinuation { continuation in
      lock.lock()
      if pendingFeeds.isEmpty {
        feedWaiters.append(continuation)
        lock.unlock()
      } else {
        let feed = pendingFeeds.removeFirst()
        lock.unlock()
        continuation.resume(returning: feed)
      }
    }
  }
}

// MARK: - Fake settings store

final class FakeSettingsStore: SettingsStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var current: Settings
  private var emitted: [Settings] = []
  private var continuations: [AsyncStream<Settings>.Continuation] = []

  init(initial: Settings) {
    current = initial
  }

  func load() async -> Settings {
    lock.withLock { current }
  }

  func save(_ settings: Settings) async throws {
    broadcast(settings)
  }

  func updates() -> AsyncStream<Settings> {
    let (stream, continuation) = AsyncStream<Settings>.makeStream()
    lock.withLock {
      for value in emitted { continuation.yield(value) }
      continuations.append(continuation)
    }
    return stream
  }

  /// Scripts a settings change arriving as if another surface saved it.
  func pushUpdate(_ settings: Settings) {
    broadcast(settings)
  }

  private func broadcast(_ settings: Settings) {
    lock.lock()
    current = settings
    emitted.append(settings)
    let targets = continuations
    lock.unlock()
    for continuation in targets { continuation.yield(settings) }
  }
}

// MARK: - Fake session provider

struct ScanContextRequest: Sendable, Equatable {
  let settings: Settings
  let hasFullDiskAccess: Bool
}

struct PlanContextRequest: Sendable, Equatable {
  let sessionID: UUID
  let settings: Settings
}

final class FakeDiskMapSessionProvider: DiskMapSessionProviding, @unchecked Sendable {
  let fileSystem = RefusingFileSystem()

  private let lock = NSLock()
  private var sessionQueue: [UUID]
  private var mintedIDs: [UUID] = []
  private var scanRequests: [ScanContextRequest] = []
  private var planRequests: [PlanContextRequest] = []

  init(sessionIDs: [UUID]) {
    sessionQueue = sessionIDs
  }

  var minted: [UUID] { lock.withLock { mintedIDs } }
  var recordedScanRequests: [ScanContextRequest] { lock.withLock { scanRequests } }
  var recordedPlanRequests: [PlanContextRequest] { lock.withLock { planRequests } }

  func makeScanContext(settings: Settings, hasFullDiskAccess: Bool) async -> ScanContext {
    let sessionID: UUID = lock.withLock {
      let next = sessionQueue.isEmpty ? UUID() : sessionQueue.removeFirst()
      mintedIDs.append(next)
      scanRequests.append(
        ScanContextRequest(settings: settings, hasFullDiskAccess: hasFullDiskAccess))
      return next
    }
    return ScanContext(
      sessionID: sessionID,
      fileSystem: fileSystem,
      rules: LensModuleFixture.emptyCatalog,
      settings: settings,
      hasFullDiskAccess: hasFullDiskAccess
    )
  }

  func makePlanContext(sessionID: UUID, settings: Settings) async -> PlanContext {
    lock.withLock {
      planRequests.append(PlanContextRequest(sessionID: sessionID, settings: settings))
    }
    return PlanContext(
      sessionID: sessionID,
      rules: LensModuleFixture.emptyCatalog,
      settings: settings,
      ownership: EverythingUserDomainPolicy()
    )
  }
}

// MARK: - Fake full disk access monitor

final class FakeFullDiskAccessMonitor: FullDiskAccessMonitoring, @unchecked Sendable {
  private let lock = NSLock()
  private var granted: Bool
  private var openCallCounter = 0

  init(granted: Bool = true) {
    self.granted = granted
  }

  var isGranted: Bool {
    get async { lock.withLock { granted } }
  }

  var openPrivacySettingsCallCount: Int { lock.withLock { openCallCounter } }

  func setGranted(_ value: Bool) {
    lock.withLock { granted = value }
  }

  func updates() -> AsyncStream<Bool> {
    AsyncStream { _ in }
  }

  @MainActor func openPrivacySettings() {
    lock.withLock { openCallCounter += 1 }
    Issue.record("the disk map model must never open privacy settings itself")
  }
}

// MARK: - Harness

@MainActor
struct DiskMapHarness {
  let engine: FakeDiskMapMapProvider
  let executor: FakePlanExecutor
  let store: FakeSettingsStore
  let sessions: FakeDiskMapSessionProvider
  let access: FakeFullDiskAccessMonitor
  let model: DiskMapModuleModel
}

@MainActor
func makeDiskMapHarness(
  deletionMode: Settings.DeletionMode = .trash,
  granted: Bool = true,
  sessionIDs: [UUID] = [
    LensModuleFixture.sessionA, LensModuleFixture.sessionB, LensModuleFixture.sessionC,
  ]
) -> DiskMapHarness {
  let engine = FakeDiskMapMapProvider()
  let executor = FakePlanExecutor()
  let store = FakeSettingsStore(initial: LensModuleFixture.settings(mode: deletionMode))
  let sessions = FakeDiskMapSessionProvider(sessionIDs: sessionIDs)
  let access = FakeFullDiskAccessMonitor(granted: granted)
  let model = DiskMapModuleModel(
    engine: engine,
    executor: executor,
    settings: store,
    sessions: sessions,
    access: access
  )
  return DiskMapHarness(
    engine: engine, executor: executor, store: store,
    sessions: sessions, access: access, model: model
  )
}

// MARK: - State extraction

@MainActor
func mappingState(_ model: DiskMapModuleModel) -> DiskMapMapState? {
  if case .mapping(let map) = model.state { return map }
  return nil
}

@MainActor
func browsingState(_ model: DiskMapModuleModel) -> DiskMapMapState? {
  if case .browsing(let map) = model.state { return map }
  return nil
}

@MainActor
func currentMapState(_ model: DiskMapModuleModel) -> DiskMapMapState? {
  mappingState(model) ?? browsingState(model)
}

@MainActor
func executionProgress(_ model: DiskMapModuleModel) -> DiskMapExecutionProgress? {
  if case .executing(let progress) = model.state { return progress }
  return nil
}

@MainActor
func currentSummary(_ model: DiskMapModuleModel) -> DiskMapResultSummary? {
  if case .result(let summary) = model.state { return summary }
  return nil
}

@MainActor
struct ModelSnapshot: Equatable {
  let state: DiskMapModuleState
  let failureNotice: String?
}

@MainActor
func snapshot(_ model: DiskMapModuleModel) -> ModelSnapshot {
  ModelSnapshot(state: model.state, failureNotice: model.failureNotice)
}

// MARK: - Tree helpers

func findNode(
  _ root: DiskMapTreeNode?, at path: AbsolutePath
) -> DiskMapTreeNode? {
  guard let root else { return nil }
  if root.path == path { return root }
  for child in root.children {
    if let found = findNode(child, at: path) { return found }
  }
  return nil
}

func everyNode(_ root: DiskMapTreeNode?) -> [DiskMapTreeNode] {
  guard let root else { return [] }
  return [root] + root.children.flatMap { everyNode($0) }
}

// MARK: - Deterministic waiting (cooperative yields, no wall clock)

@MainActor
func expectEventually(
  _ description: String,
  yields: Int = 50_000,
  until condition: @MainActor () -> Bool
) async {
  for _ in 0..<yields {
    if condition() { return }
    await Task.yield()
  }
  Issue.record("ran out of yields waiting until \(description)")
}

@MainActor
func settleBriefly(yields: Int = 400) async {
  for _ in 0..<yields {
    await Task.yield()
  }
}

// MARK: - Flow helpers

@MainActor
func beginMapping(
  _ harness: DiskMapHarness,
  volume: AbsolutePath = LensModuleFixture.volume
) async -> MapFeed {
  harness.model.startMapping(volume: volume)
  return await harness.engine.nextMapFeed()
}

/// Streams the standard scripted volume: the root, two directories, two
/// files and one denylisted directory, then the revisions that settle every
/// directory total. Honours C22 throughout: totals only ever grow.
@MainActor
func sendStandardTree(_ feed: MapFeed) {
  feed.send(
    .node(
      LensModuleFixture.node(
        LensModuleFixture.volume, parent: nil, isDirectory: true, subtreeBytes: 0)),
    .node(
      LensModuleFixture.node(
        LensModuleFixture.mediaDirectory, parent: LensModuleFixture.volume,
        isDirectory: true, subtreeBytes: 0)),
    .node(
      LensModuleFixture.node(
        LensModuleFixture.filmFile, parent: LensModuleFixture.mediaDirectory,
        isDirectory: false, subtreeBytes: LensModuleFixture.filmBytes)),
    .node(
      LensModuleFixture.node(
        LensModuleFixture.clipFile, parent: LensModuleFixture.mediaDirectory,
        isDirectory: false, subtreeBytes: LensModuleFixture.clipBytes)),
    .node(
      LensModuleFixture.node(
        LensModuleFixture.documentsDirectory, parent: LensModuleFixture.volume,
        isDirectory: true, subtreeBytes: LensModuleFixture.documentsBytes)),
    .node(
      LensModuleFixture.node(
        LensModuleFixture.protectedDirectory, parent: LensModuleFixture.volume,
        isDirectory: true, subtreeBytes: LensModuleFixture.protectedBytes,
        isSelectable: false)),
    .sizeRevision(
      path: LensModuleFixture.mediaDirectory, subtreeBytes: LensModuleFixture.mediaBytes),
    .sizeRevision(
      path: LensModuleFixture.volume, subtreeBytes: LensModuleFixture.volumeBytes)
  )
}

@MainActor
func reachBrowsing(_ harness: DiskMapHarness) async -> DiskMapMapState? {
  let feed = await beginMapping(harness)
  sendStandardTree(feed)
  feed.send(.completed)
  feed.finish()
  await expectEventually("the model reaches browsing") {
    browsingState(harness.model) != nil
  }
  return browsingState(harness.model)
}

@MainActor
func reachExecuting(
  _ harness: DiskMapHarness,
  selecting paths: [AbsolutePath] = [LensModuleFixture.filmFile],
  confirmation: PermanentDeletionConfirmation? = nil
) async -> ExecutionFeed? {
  guard await reachBrowsing(harness) != nil else { return nil }
  for path in paths {
    harness.model.toggleSelection(path)
  }
  let refusal = harness.model.executeSelection(permanentConfirmation: confirmation)
  guard refusal == nil else {
    Issue.record("executeSelection was refused with \(String(describing: refusal))")
    return nil
  }
  let feed = await harness.executor.nextExecutionFeed()
  await expectEventually("the model reaches executing") {
    executionProgress(harness.model) != nil
  }
  return feed
}

@MainActor
func reachResult(
  _ harness: DiskMapHarness,
  bytesReclaimed: UInt64 = LensModuleFixture.filmBytes
) async -> DiskMapResultSummary? {
  guard let run = await reachExecuting(harness) else { return nil }
  var results: [(UUID, OperationResult)] = []
  for operation in run.plan.operations {
    run.send(.operationStarted(operationID: operation.id))
    run.send(
      .operationFinished(
        operationID: operation.id, result: .completed(bytesReclaimed: bytesReclaimed)))
    results.append((operation.id, .completed(bytesReclaimed: bytesReclaimed)))
  }
  run.send(
    .planCompleted(
      makeReport(planID: run.plan.id, results: results, bytesReclaimed: bytesReclaimed)))
  run.finish()
  await expectEventually("the result arrives") {
    currentSummary(harness.model) != nil
  }
  return currentSummary(harness.model)
}
