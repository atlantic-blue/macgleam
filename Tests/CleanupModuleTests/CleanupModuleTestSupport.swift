import CleanupModule
import Foundation
import GleamCore
import Testing

/// Foundation exports NSOperation as `Operation`; this pins the unqualified
/// name to the domain type for the whole module.
typealias Operation = GleamCore.Operation

// MARK: - Fixtures

enum ModuleFixture {

  static let confirmationInstant = Date(timeIntervalSince1970: 1_723_000_000)
  static let executionStart = Date(timeIntervalSince1970: 1_723_000_100)
  static let executionEnd = Date(timeIntervalSince1970: 1_723_000_200)

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

  static let fullAccess = CleanupDegradedState(hasFullDiskAccess: true, unavailable: [])

  static let mailUnavailableSentence =
    "Mail attachment local copies are unreachable without Full Disk Access."
  static let trashUnavailableSentence =
    "Trash bins on other volumes are unreachable without Full Disk Access."

  static let withoutFullDiskAccess = CleanupDegradedState(
    hasFullDiskAccess: false,
    unavailable: [mailUnavailableSentence, trashUnavailableSentence]
  )

  static let emptyCatalog = RuleCatalog(
    version: RuleCatalogVersion(value: 1),
    signature: Data(),
    cleanupRules: [],
    adwareRules: [],
    denylist: Denylist(patterns: [])
  )

  static func finding(
    id: UUID,
    sessionID: UUID = sessionA,
    category: FindingCategory,
    paths: [String],
    byteSize: UInt64,
    risk: RiskLevel = .safe,
    isPreselected: Bool
  ) -> Finding {
    Finding(
      id: id,
      sessionID: sessionID,
      category: category,
      paths: paths.map(path),
      byteSize: byteSize,
      risk: risk,
      explanation: "A cleanup finding scripted for the module tests.",
      isPreselected: isPreselected
    )
  }

  /// Two files, 1,000 bytes, safe and preselected.
  static func cacheFinding(sessionID: UUID = sessionA) -> Finding {
    finding(
      id: uuid(0x01),
      sessionID: sessionID,
      category: .userCache,
      paths: [
        "/Users/test/Library/Caches/com.example.app/state.bin",
        "/Users/test/Library/Caches/com.example.app/images/thumb.dat",
      ],
      byteSize: 1_000,
      isPreselected: true
    )
  }

  /// One file, 300 bytes, safe and preselected.
  static func logFinding(sessionID: UUID = sessionA) -> Finding {
    finding(
      id: uuid(0x02),
      sessionID: sessionID,
      category: .log,
      paths: ["/Users/test/Library/Logs/com.example.app/session.log"],
      byteSize: 300,
      isPreselected: true
    )
  }

  /// One file, 200 bytes, safe but not preselected. Same category as the
  /// cache finding, so category toggling has a mixed group to work on.
  static func spareCacheFinding(sessionID: UUID = sessionA) -> Finding {
    finding(
      id: uuid(0x03),
      sessionID: sessionID,
      category: .userCache,
      paths: ["/Users/test/Library/Containers/com.example.app/Data/Library/Caches/blob.cache"],
      byteSize: 200,
      isPreselected: false
    )
  }

  /// Review risk yet claiming preselection: the hostile input C38's defence
  /// in depth rule exists for.
  static func riskyPreselectedFinding(sessionID: UUID = sessionA) -> Finding {
    finding(
      id: uuid(0x04),
      sessionID: sessionID,
      category: .browserCache,
      paths: ["/Users/test/Library/Caches/com.browser.web/Cache.db"],
      byteSize: 400,
      risk: .review,
      isPreselected: true
    )
  }

  /// Dangerous risk yet claiming preselection.
  static func dangerousPreselectedFinding(sessionID: UUID = sessionA) -> Finding {
    finding(
      id: uuid(0x06),
      sessionID: sessionID,
      category: .temporaryFile,
      paths: ["/private/tmp/session-scratch.tmp"],
      byteSize: 500,
      risk: .dangerous,
      isPreselected: true
    )
  }

  /// Two files, 700 bytes. Trash bin contents always plan permanently (C20).
  static func trashBinFinding(sessionID: UUID = sessionA) -> Finding {
    finding(
      id: uuid(0x05),
      sessionID: sessionID,
      category: .trashBin(volume: path("/")),
      paths: [
        "/Users/test/.Trash/old-notes.txt",
        "/Users/test/.Trash/drafts/chapter.txt",
      ],
      byteSize: 700,
      isPreselected: true
    )
  }
}

func makeCounters(
  _ filesSeen: UInt64, _ bytesReclaimable: UInt64, _ findingCount: UInt32
) -> ScanCounters {
  var counters = ScanCounters.zero
  counters.filesSeen = filesSeen
  counters.bytesReclaimable = bytesReclaimable
  counters.findingCount = findingCount
  return counters
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
    startedAt: ModuleFixture.executionStart,
    finishedAt: ModuleFixture.executionEnd
  )
}

// MARK: - File system that must never be called

struct RefusedFileSystemAccess: Error {}

/// Handed to every scan context. The model never touches the file system
/// (C38 purity), so any call through this type is a recorded test failure.
final class RefusingFileSystem: FileSystemReading, @unchecked Sendable {
  private let lock = NSLock()
  private var violations: [String] = []

  var violationCount: Int { lock.withLock { violations.count } }

  private func refuse(_ name: String) {
    lock.withLock { violations.append(name) }
    Issue.record("the cleanup model touched the file system through \(name)")
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

// MARK: - Fake engine

/// A scan under full test control: the test receives the continuation once
/// the model subscribes, scripts events, and finishes or fails the stream.
struct ScanFeed: Sendable {
  let context: ScanContext
  let continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation

  func send(_ events: ScanEvent...) {
    for event in events { continuation.yield(event) }
  }

  func finish() { continuation.finish() }

  func fail(_ error: any Error) { continuation.finish(throwing: error) }
}

final class FakeCleanupEngine: GleamEngine, @unchecked Sendable {
  let module: GleamModule

  private let lock = NSLock()
  private var pendingFeeds: [ScanFeed] = []
  private var feedWaiters: [CheckedContinuation<ScanFeed, Never>] = []
  private var recordedScanContexts: [ScanContext] = []
  private var recordedPlanSelections: [[Finding]] = []
  private var recordedPlanContexts: [PlanContext] = []
  private var builtPlans: [OperationPlan] = []
  private var planFailure: (any Error)?
  private var operationSuffix: UInt8 = 0x50
  private var planSuffix: UInt8 = 0x40

  init(module: GleamModule = .cleanup) {
    self.module = module
  }

  var scanCallCount: Int { lock.withLock { recordedScanContexts.count } }
  var planCallCount: Int { lock.withLock { recordedPlanSelections.count } }
  var lastPlanSelection: [Finding]? { lock.withLock { recordedPlanSelections.last } }
  var lastPlanContext: PlanContext? { lock.withLock { recordedPlanContexts.last } }
  var lastPlan: OperationPlan? { lock.withLock { builtPlans.last } }

  func failPlans(with error: any Error) {
    lock.withLock { planFailure = error }
  }

  func scan(_ context: ScanContext) -> AsyncThrowingStream<ScanEvent, Error> {
    let (stream, continuation) = AsyncThrowingStream<ScanEvent, Error>.makeStream()
    let feed = ScanFeed(context: context, continuation: continuation)
    lock.lock()
    recordedScanContexts.append(context)
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

  /// Awaits the model's subscription to the next scan stream.
  func nextScanFeed() async -> ScanFeed {
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

  /// Expands each selected finding into one operation per path, trash or
  /// permanent by the context's deletion mode, trash bin contents always
  /// permanent (C20). The confirmation is left nil: attaching the caller's
  /// confirmation is the model's job.
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
      let isTrashBin: Bool
      if case .trashBin = finding.category { isTrashBin = true } else { isTrashBin = false }
      let isPermanent = isTrashBin || context.settings.deletionMode == .permanent
      for target in finding.paths {
        operationSuffix &+= 1
        operations.append(
          Operation(
            id: ModuleFixture.uuid(operationSuffix),
            findingID: finding.id,
            kind: isPermanent
              ? .deletePermanently(target: target)
              : .moveToTrash(target: target),
            privilege: .user
          ))
      }
    }
    planSuffix &+= 1
    let plan = OperationPlan(
      id: ModuleFixture.uuid(planSuffix),
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
  private var loadCallCounter = 0
  private var savedValues: [Settings] = []

  init(initial: Settings) {
    current = initial
  }

  var loadCallCount: Int { lock.withLock { loadCallCounter } }
  var saved: [Settings] { lock.withLock { savedValues } }

  func load() async -> Settings {
    lock.withLock {
      loadCallCounter += 1
      return current
    }
  }

  func save(_ settings: Settings) async throws {
    broadcast(settings) { savedValues.append(settings) }
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
    broadcast(settings) {}
  }

  private func broadcast(_ settings: Settings, sideEffect: () -> Void) {
    lock.lock()
    current = settings
    emitted.append(settings)
    sideEffect()
    let targets = continuations
    lock.unlock()
    for continuation in targets { continuation.yield(settings) }
  }
}

// MARK: - Fake session and degraded providers

struct ScanContextRequest: Sendable, Equatable {
  let settings: Settings
  let hasFullDiskAccess: Bool
}

struct PlanContextRequest: Sendable, Equatable {
  let sessionID: UUID
  let settings: Settings
}

final class FakeCleanupSessionProvider: CleanupSessionProviding, @unchecked Sendable {
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
      rules: ModuleFixture.emptyCatalog,
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
      rules: ModuleFixture.emptyCatalog,
      settings: settings,
      ownership: EverythingUserDomainPolicy()
    )
  }
}

final class FakeDegradedStateProvider: CleanupDegradedStateProviding, @unchecked Sendable {
  private let lock = NSLock()
  private var state: CleanupDegradedState
  private var callCounter = 0

  init(state: CleanupDegradedState) {
    self.state = state
  }

  var currentCallCount: Int { lock.withLock { callCounter } }

  func set(_ newState: CleanupDegradedState) {
    lock.withLock { state = newState }
  }

  func current() async -> CleanupDegradedState {
    lock.withLock {
      callCounter += 1
      return state
    }
  }
}

// MARK: - Harness

@MainActor
struct CleanupModuleHarness {
  let engine: FakeCleanupEngine
  let executor: FakePlanExecutor
  let store: FakeSettingsStore
  let sessions: FakeCleanupSessionProvider
  let degraded: FakeDegradedStateProvider
  let model: CleanupModuleModel
}

@MainActor
func makeCleanupHarness(
  deletionMode: Settings.DeletionMode = .trash,
  degradedState: CleanupDegradedState = ModuleFixture.fullAccess,
  sessionIDs: [UUID] = [ModuleFixture.sessionA, ModuleFixture.sessionB, ModuleFixture.sessionC]
) -> CleanupModuleHarness {
  let engine = FakeCleanupEngine()
  let executor = FakePlanExecutor()
  let store = FakeSettingsStore(initial: ModuleFixture.settings(mode: deletionMode))
  let sessions = FakeCleanupSessionProvider(sessionIDs: sessionIDs)
  let degraded = FakeDegradedStateProvider(state: degradedState)
  let model = CleanupModuleModel(
    engine: engine,
    executor: executor,
    settings: store,
    sessions: sessions,
    degraded: degraded
  )
  return CleanupModuleHarness(
    engine: engine, executor: executor, store: store,
    sessions: sessions, degraded: degraded, model: model
  )
}

// MARK: - State extraction

@MainActor
func scanProgress(_ model: CleanupModuleModel) -> CleanupScanProgress? {
  if case .scanning(let progress) = model.state { return progress }
  return nil
}

@MainActor
func currentReview(_ model: CleanupModuleModel) -> CleanupReviewState? {
  if case .reviewing(let review) = model.state { return review }
  return nil
}

@MainActor
func executionProgress(_ model: CleanupModuleModel) -> CleanupExecutionProgress? {
  if case .executing(let progress) = model.state { return progress }
  return nil
}

@MainActor
func currentSummary(_ model: CleanupModuleModel) -> CleanupResultSummary? {
  if case .result(let summary) = model.state { return summary }
  return nil
}

@MainActor
struct ModelSnapshot: Equatable {
  let state: CleanupModuleState
  let hubEstimateBytes: UInt64
  let degradedNotices: [String]
  let failureNotice: String?
}

@MainActor
func snapshot(_ model: CleanupModuleModel) -> ModelSnapshot {
  ModelSnapshot(
    state: model.state,
    hubEstimateBytes: model.hubEstimateBytes,
    degradedNotices: model.degradedNotices,
    failureNotice: model.failureNotice
  )
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
func beginScan(_ harness: CleanupModuleHarness) async -> ScanFeed {
  harness.model.startScan()
  return await harness.engine.nextScanFeed()
}

@MainActor
func reachReviewing(
  _ harness: CleanupModuleHarness,
  findings: [Finding],
  filesSeen: UInt64 = 100
) async -> CleanupReviewState? {
  let feed = await beginScan(harness)
  var counters = ScanCounters.zero
  feed.send(.phase(.indeterminate))
  for finding in findings {
    counters.filesSeen += 10
    counters.bytesReclaimable += finding.byteSize
    counters.findingCount += 1
    feed.send(.finding(finding), .progress(counters))
  }
  counters.filesSeen = max(counters.filesSeen, filesSeen)
  feed.send(.phase(.settling), .progress(counters))
  feed.finish()
  await expectEventually("the model reaches reviewing") {
    currentReview(harness.model) != nil
  }
  return currentReview(harness.model)
}

@MainActor
func reachExecuting(
  _ harness: CleanupModuleHarness,
  findings: [Finding],
  toggling: [UUID] = [],
  confirmation: PermanentDeletionConfirmation? = nil
) async -> ExecutionFeed? {
  guard await reachReviewing(harness, findings: findings) != nil else { return nil }
  for findingID in toggling {
    harness.model.toggleFinding(findingID)
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
  _ harness: CleanupModuleHarness,
  bytesReclaimed: UInt64 = 1_000
) async -> CleanupResultSummary? {
  guard
    let run = await reachExecuting(harness, findings: [ModuleFixture.cacheFinding()])
  else { return nil }
  let operations = run.plan.operations
  var results: [(UUID, OperationResult)] = []
  var remaining = bytesReclaimed
  for (index, operation) in operations.enumerated() {
    let share =
      index == operations.count - 1
      ? remaining
      : bytesReclaimed / UInt64(operations.count)
    remaining -= share
    run.send(.operationStarted(operationID: operation.id))
    run.send(
      .operationFinished(operationID: operation.id, result: .completed(bytesReclaimed: share)))
    results.append((operation.id, .completed(bytesReclaimed: share)))
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

@MainActor
func reachCleanSweep(
  _ harness: CleanupModuleHarness,
  filesChecked: UInt64 = 4_321
) async {
  let feed = await beginScan(harness)
  feed.send(
    .phase(.indeterminate),
    .progress(makeCounters(filesChecked, 0, 0)),
    .phase(.settling)
  )
  feed.finish()
  await expectEventually("the clean sweep arrives") {
    harness.model.state == .cleanSweep(filesChecked: filesChecked)
  }
}

// MARK: - Command totality helper

enum ForeignCommand: Equatable {
  case startScan
  case toggleUnknownFinding
  case toggleCategory
  case executeSelection
  case cancelScan
  case cancelExecution
  case acknowledgeResult
}

@MainActor
func expectCommandsAreIdentity(
  _ commands: [ForeignCommand],
  on harness: CleanupModuleHarness
) async {
  for command in commands {
    let before = snapshot(harness.model)
    let mintedBefore = harness.sessions.minted.count
    switch command {
    case .startScan:
      harness.model.startScan()
    case .toggleUnknownFinding:
      harness.model.toggleFinding(ModuleFixture.uuid(0xEE))
    case .toggleCategory:
      harness.model.toggleCategory(.userCache)
    case .executeSelection:
      #expect(harness.model.executeSelection(permanentConfirmation: nil) == .notReviewing)
    case .cancelScan:
      harness.model.cancelScan()
    case .cancelExecution:
      harness.model.cancelExecution()
    case .acknowledgeResult:
      harness.model.acknowledgeResult()
    }
    await settleBriefly()
    #expect(
      snapshot(harness.model) == before,
      "\(command) must be the identity in this state")
    if command == .startScan {
      #expect(
        harness.sessions.minted.count == mintedBefore,
        "an ignored startScan must not mint a session")
    }
  }
}
