import CryptoKit
import Foundation
import GleamCore
import PerformanceEngine
import Testing
import os

/// Foundation exports NSOperation as `Operation`; this pins the unqualified
/// name to the domain type under test for the whole module.
typealias Operation = GleamCore.Operation

/// Deterministic fixtures for the Performance module's maintenance half
/// (C23). Nothing here reads a wall clock, runs a system command, asks for
/// privilege or touches the real machine's caches or network configuration.
/// Every instant, identifier and signing key is fixed in this file.
enum PerformanceFixture {

  /// The instant the executor's injected clock returns.
  static let executionInstant = Date(timeIntervalSinceReferenceDate: 800_000_000)

  static let sessionID = uuid(0xC1)
  static let otherSessionID = uuid(0xC2)

  static let userHome = path("/Users/gleam")
  static let environment = OwnershipEnvironment(currentUserHome: userHome, currentUserID: 501)

  /// A path that exists in the fixture file system, so a hostile finding
  /// carrying it is a plausible removal target rather than a nonsense one.
  static let realUserCachePath = "/Users/gleam/Library/Caches/com.example.app/state.bin"
  static let realSystemCachePath = "/Library/Caches/com.example.app/shared.bin"

  /// Signing seed owned by this suite alone, distinct from every other
  /// fixture file's key material. The production rules key never appears here.
  static let signingKeySeed = Data((0..<32).map { UInt8(truncatingIfNeeded: 0x5C &+ $0 &* 7) })

  static func uuid(_ suffix: UInt8) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000000%02X", suffix))!
  }

  static func path(_ value: String) -> AbsolutePath {
    AbsolutePath(normalising: value)
  }

  static func contents(_ seed: UInt8, length: Int) -> Data {
    Data((0..<length).map { UInt8((Int($0) + Int(seed)) % 251) })
  }
}

// MARK: - Signed catalogue fixtures

func makeSignedPerformanceCatalog(
  version: UInt32 = 2,
  blocking patterns: [String] = []
) throws -> RuleCatalog {
  let key = try Curve25519.Signing.PrivateKey(
    rawRepresentation: PerformanceFixture.signingKeySeed)
  let unsigned = RuleCatalog(
    version: RuleCatalogVersion(value: version),
    signature: Data(),
    cleanupRules: [],
    adwareRules: [],
    denylist: Denylist(patterns: patterns.map { PathPattern(pattern: $0) })
  )
  let signature = try key.signature(for: unsigned.canonicalContentEncoding())
  return RuleCatalog(
    version: unsigned.version,
    signature: signature,
    cleanupRules: unsigned.cleanupRules,
    adwareRules: unsigned.adwareRules,
    denylist: unsigned.denylist
  )
}

/// The effective denylist obtained the way production obtains one: a
/// catalogue signed with this file's key, verified and adopted by a real
/// store, independent of any engine.
func performanceDenylist(blocking patterns: [String] = []) async throws -> Denylist {
  let key = try Curve25519.Signing.PrivateKey(
    rawRepresentation: PerformanceFixture.signingKeySeed)
  let catalog = try makeSignedPerformanceCatalog(version: 1, blocking: patterns)
  let verifier = try RuleCatalogVerifier(publicKey: key.publicKey.rawRepresentation)
  let store = try RuleCatalogStore(baseline: catalog, verifier: verifier)
  return await store.effectiveDenylist
}

// MARK: - File systems

/// Conforms to the reading side and nothing else. Handing this to a scan is
/// the compile time proof that scanning never needs the mutating side.
struct ReadingOnlyFileSystem: FileSystemReading {
  let backing: InMemoryFileSystem

  func enumerate(
    root: AbsolutePath,
    options: EnumerationOptions
  ) -> AsyncThrowingStream<EnumerationEvent, Error> {
    backing.enumerate(root: root, options: options)
  }

  func metadata(at path: AbsolutePath) async throws -> FileRecord {
    try await backing.metadata(at: path)
  }

  func readData(at path: AbsolutePath, maxBytes: UInt64) async throws -> Data {
    try await backing.readData(at: path, maxBytes: maxBytes)
  }

  func extendedAttributes(at path: AbsolutePath) async throws -> [String: Data] {
    try await backing.extendedAttributes(at: path)
  }

  func exists(_ path: AbsolutePath) async -> Bool {
    await backing.exists(path)
  }

  func volumeInfo(at path: AbsolutePath) async throws -> VolumeInfo {
    try await backing.volumeInfo(at: path)
  }
}

/// The fixture disk: two real files a hostile finding can point at, so
/// "nothing was removed" is a statement about files that were actually there.
func makeFixtureFileSystem() async -> InMemoryFileSystem {
  let fileSystem = InMemoryFileSystem()
  for directory in [
    "/Users", "/Users/gleam", "/Users/gleam/Library", "/Users/gleam/Library/Caches",
    "/Users/gleam/Library/Caches/com.example.app", "/Library", "/Library/Caches",
    "/Library/Caches/com.example.app",
  ] {
    await fileSystem.seedDirectory(at: PerformanceFixture.path(directory))
  }
  var seed: UInt8 = 1
  for file in [PerformanceFixture.realUserCachePath, PerformanceFixture.realSystemCachePath] {
    await fileSystem.seedFile(
      at: PerformanceFixture.path(file),
      contents: PerformanceFixture.contents(seed, length: 512),
      isExecutable: false,
      created: Date(timeIntervalSinceReferenceDate: 799_000_000),
      modified: Date(timeIntervalSinceReferenceDate: 799_000_500),
      lastOpened: nil,
      extendedAttributes: [:]
    )
    seed &+= 1
  }
  return fileSystem
}

enum FileSystemUseError: Error, Equatable {
  case readsAreNotPartOfMaintenance
  case mutationsAreNotPartOfMaintenance
}

/// Records every attempted mutation and performs none. Running a maintenance
/// plan against this is how "the work never happens in this process" is
/// asserted: if anything at all reached the file system, `mutations` says so
/// by name and nothing on the fixture disk moved regardless.
final class TrappingFileSystem: FileSystemReading, FileSystemMutating, Sendable {
  private let attempted = OSAllocatedUnfairLock(initialState: [String]())

  var mutations: [String] {
    attempted.withLock { $0 }
  }

  private func record(_ name: String) {
    attempted.withLock { $0.append(name) }
  }

  func enumerate(
    root: AbsolutePath,
    options: EnumerationOptions
  ) -> AsyncThrowingStream<EnumerationEvent, Error> {
    AsyncThrowingStream { $0.finish() }
  }

  func metadata(at path: AbsolutePath) async throws -> FileRecord {
    throw FileSystemUseError.readsAreNotPartOfMaintenance
  }

  func readData(at path: AbsolutePath, maxBytes: UInt64) async throws -> Data {
    throw FileSystemUseError.readsAreNotPartOfMaintenance
  }

  func extendedAttributes(at path: AbsolutePath) async throws -> [String: Data] {
    throw FileSystemUseError.readsAreNotPartOfMaintenance
  }

  func exists(_ path: AbsolutePath) async -> Bool {
    false
  }

  func volumeInfo(at path: AbsolutePath) async throws -> VolumeInfo {
    throw FileSystemUseError.readsAreNotPartOfMaintenance
  }

  func moveToTrash(_ path: AbsolutePath) async throws -> AbsolutePath {
    record("moveToTrash(\(path.value))")
    throw FileSystemUseError.mutationsAreNotPartOfMaintenance
  }

  func move(_ source: AbsolutePath, to destination: AbsolutePath) async throws {
    record("move(\(source.value))")
    throw FileSystemUseError.mutationsAreNotPartOfMaintenance
  }

  func delete(_ path: AbsolutePath) async throws {
    record("delete(\(path.value))")
    throw FileSystemUseError.mutationsAreNotPartOfMaintenance
  }

  func createDirectory(at path: AbsolutePath) async throws {
    record("createDirectory(\(path.value))")
    throw FileSystemUseError.mutationsAreNotPartOfMaintenance
  }

  func setPosixPermissions(_ mode: UInt16, at path: AbsolutePath) async throws {
    record("setPosixPermissions(\(path.value))")
    throw FileSystemUseError.mutationsAreNotPartOfMaintenance
  }

  func setExtendedAttributes(_ attributes: [String: Data], at path: AbsolutePath) async throws {
    record("setExtendedAttributes(\(path.value))")
    throw FileSystemUseError.mutationsAreNotPartOfMaintenance
  }
}

// MARK: - Ownership policies

/// Everything is user domain. Under C17 that means the executor would run an
/// operation in process if it could, so a maintenance task reaching the
/// helper against this policy is the routing decision under test rather than
/// a side effect of the fixture's ownership answers.
struct EverythingIsUserDomainPolicy: PathOwnershipPolicy {
  func ownership(
    of path: AbsolutePath,
    environment: OwnershipEnvironment
  ) -> PathOwnership {
    .userDomain
  }
}

// MARK: - The fake helper

/// One operation as the executor handed it over, with the privilege the plan
/// gave it. C30 requires every mutating request to name the plan and the
/// operation it belongs to, so both travel.
struct PrivilegedHandover: Sendable, Equatable {
  let operationID: UUID
  let planID: UUID
  let kind: Operation.Kind
  let privilege: Operation.Privilege
}

/// Stands in for the privileged helper at the boundary the executor sees
/// (C17, `PrivilegedOperationPerforming`). It records what crossed and
/// answers what the test scripted. It never decides whether an operation
/// should have been sent, which is the whole thing under test, and it runs no
/// system command: the real daemon's behaviour is pinned in the helper
/// suites, and the tasks' effect on a real machine is the s3c human check.
final class FakeHelper: PrivilegedOperationPerforming {
  private let state = OSAllocatedUnfairLock(initialState: [PrivilegedHandover]())
  private let scripted: [MaintenanceTask: OperationResult]
  private let fallback: OperationResult

  init(
    results: [MaintenanceTask: OperationResult] = [:],
    otherwise fallback: OperationResult = .completed(bytesReclaimed: 0)
  ) {
    self.scripted = results
    self.fallback = fallback
  }

  var handovers: [PrivilegedHandover] {
    state.withLock { $0 }
  }

  var sawNothing: Bool {
    handovers.isEmpty
  }

  /// The maintenance tasks that crossed the boundary, in the order they
  /// crossed.
  var performedTasks: [MaintenanceTask] {
    handovers.compactMap { handover in
      if case .runMaintenance(let task) = handover.kind { return task }
      return nil
    }
  }

  /// The kinds that crossed, so a suite can assert nothing but maintenance
  /// ever reached a process running as root.
  var performedKinds: [Operation.Kind] {
    handovers.map(\.kind)
  }

  func perform(_ operation: Operation, planID: UUID) async -> OperationResult {
    state.withLock {
      $0.append(
        PrivilegedHandover(
          operationID: operation.id,
          planID: planID,
          kind: operation.kind,
          privilege: operation.privilege
        ))
    }
    if case .runMaintenance(let task) = operation.kind, let result = scripted[task] {
      return result
    }
    return fallback
  }
}

// MARK: - Contexts

func makePerformanceSettings(
  deletionMode: Settings.DeletionMode = .trash
) -> Settings {
  Settings(
    deletionMode: deletionMode,
    largeFileThresholdBytes: 1_073_741_824,
    oldFileThresholdDays: 180,
    menuBar: MenuBarPreferences(showsStorage: true, showsMemory: true, showsProcessorLoad: true),
    motion: MotionPreferences(reduceMotionOverride: nil)
  )
}

/// Every scan context wraps the file system in the reading only value, so the
/// whole suite is built on the compile time property that a scan cannot
/// mutate anything.
func makeScanContext(
  over fileSystem: InMemoryFileSystem,
  rules: RuleCatalog,
  settings: Settings = makePerformanceSettings(),
  hasFullDiskAccess: Bool = true,
  sessionID: UUID = PerformanceFixture.sessionID
) -> ScanContext {
  ScanContext(
    sessionID: sessionID,
    fileSystem: ReadingOnlyFileSystem(backing: fileSystem),
    rules: rules,
    settings: settings,
    hasFullDiskAccess: hasFullDiskAccess
  )
}

func makePlanContext(
  rules: RuleCatalog,
  settings: Settings = makePerformanceSettings(),
  ownership: any PathOwnershipPolicy = EverythingIsUserDomainPolicy(),
  sessionID: UUID = PerformanceFixture.sessionID
) -> PlanContext {
  PlanContext(
    sessionID: sessionID,
    rules: rules,
    settings: settings,
    ownership: ownership
  )
}

// MARK: - Findings

func maintenanceTask(of finding: Finding) -> MaintenanceTask? {
  if case .maintenanceTask(let task) = finding.category { return task }
  return nil
}

func maintenanceTask(of operation: Operation) -> MaintenanceTask? {
  if case .runMaintenance(let task) = operation.kind { return task }
  return nil
}

/// A maintenance finding built by hand, for the selections a scan would not
/// produce. `entries` defaults to none because a maintenance task names a
/// task, never a file; the hostile tests are the ones that pass entries.
func makeMaintenanceFinding(
  task: MaintenanceTask,
  id: UUID = PerformanceFixture.uuid(0xD1),
  sessionID: UUID = PerformanceFixture.sessionID,
  entries: [PathEntry] = [],
  risk: RiskLevel = .safe,
  explanation: String = "A maintenance task built by the tests.",
  isPreselected: Bool = false
) -> Finding {
  Finding(
    id: id,
    sessionID: sessionID,
    category: .maintenanceTask(task: task),
    entries: entries,
    risk: risk,
    explanation: explanation,
    isPreselected: isPreselected
  )
}

/// A finding from another module, carrying real paths and real bytes. Feeding
/// one of these to the Performance plan builder is the hostile case C23's
/// "no PerformanceEngine plan ever contains a file removal operation" has to
/// survive.
func makeForeignFindingWithPaths(
  id: UUID = PerformanceFixture.uuid(0xE1),
  sessionID: UUID = PerformanceFixture.sessionID,
  category: FindingCategory = .userCache,
  paths: [String] = [
    PerformanceFixture.realUserCachePath, PerformanceFixture.realSystemCachePath,
  ],
  bytesEach: UInt64 = 512,
  risk: RiskLevel = .safe,
  isPreselected: Bool = true
) -> Finding {
  Finding(
    id: id,
    sessionID: sessionID,
    category: category,
    entries: paths.map {
      PathEntry(path: PerformanceFixture.path($0), allocatedBytes: bytesEach)
    },
    risk: risk,
    explanation: "A finding from another module, carrying paths that can be removed.",
    isPreselected: isPreselected
  )
}

// MARK: - Scan collection

struct ScanOutcome: Sendable {
  var orderedEvents: [ScanEvent] = []
  var findings: [Finding] = []
  var phases: [ScanPhase] = []
  var counters: [ScanCounters] = []
  var degradedMessages: [String] = []

  /// Only the maintenance half of the Performance scan. Login items are s3d
  /// and every assertion in this suite filters them out rather than assuming
  /// they are absent.
  var maintenanceFindings: [Finding] {
    findings.filter { maintenanceTask(of: $0) != nil }
  }

  var maintenanceTasks: [MaintenanceTask] {
    maintenanceFindings.compactMap(maintenanceTask(of:))
  }

  func maintenanceFinding(for task: MaintenanceTask) -> Finding? {
    maintenanceFindings.first { maintenanceTask(of: $0) == task }
  }
}

func collectScan(
  _ stream: AsyncThrowingStream<ScanEvent, Error>
) async throws -> ScanOutcome {
  var outcome = ScanOutcome()
  for try await event in stream {
    outcome.orderedEvents.append(event)
    switch event {
    case .phase(let phase):
      outcome.phases.append(phase)
    case .progress(let counters):
      outcome.counters.append(counters)
    case .finding(let finding):
      outcome.findings.append(finding)
    case .degraded(let unavailable):
      outcome.degradedMessages.append(unavailable)
    }
  }
  return outcome
}

func runPerformanceScan(
  hasFullDiskAccess: Bool = true,
  sessionID: UUID = PerformanceFixture.sessionID,
  settings: Settings = makePerformanceSettings()
) async throws -> ScanOutcome {
  let context = makeScanContext(
    over: await makeFixtureFileSystem(),
    rules: try makeSignedPerformanceCatalog(),
    settings: settings,
    hasFullDiskAccess: hasFullDiskAccess,
    sessionID: sessionID
  )
  return try await collectScan(PerformanceEngine().scan(context))
}

// MARK: - Plan shape

/// The four kinds that take a file away from where the user left it. C23's
/// safety property is that a Performance plan never contains one, so the set
/// is named once here and every suite asks this question rather than its own.
func isFileRemoval(_ kind: Operation.Kind) -> Bool {
  switch kind {
  case .moveToTrash, .deletePermanently, .quarantine, .archive:
    return true
  case .setLaunchItemEnabled, .runMaintenance:
    return false
  }
}

func fileRemovalOperations(in plan: OperationPlan) -> [Operation] {
  plan.operations.filter { isFileRemoval($0.kind) }
}

/// A readable name for the kind, so a failure says which removal appeared
/// rather than printing a UUID soup.
func kindName(_ kind: Operation.Kind) -> String {
  switch kind {
  case .moveToTrash: return "moveToTrash"
  case .deletePermanently: return "deletePermanently"
  case .quarantine: return "quarantine"
  case .archive: return "archive"
  case .setLaunchItemEnabled: return "setLaunchItemEnabled"
  case .runMaintenance(let task): return "runMaintenance(\(task.rawValue))"
  }
}

/// The one assertion every Performance plan in this suite passes through,
/// whatever produced it. Removals are checked by kind rather than by target,
/// so a removal aimed at a path nobody thought of still fails it.
func expectNoFileRemoval(
  in plan: OperationPlan,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  let removals = fileRemovalOperations(in: plan).map { kindName($0.kind) }
  #expect(
    removals.isEmpty,
    "C23: no PerformanceEngine plan ever contains a file removal operation, found \(removals)",
    sourceLocation: sourceLocation)
  #expect(
    plan.permanentDeletionConfirmation == nil,
    "a plan that removes nothing has nothing to confirm the permanent deletion of",
    sourceLocation: sourceLocation)
}

/// Planning either refuses or produces a plan; both are contract conforming
/// answers to a hostile selection, and neither may yield a removal. Returns
/// the plan when one was produced so a caller can assert more about it.
@discardableResult
func planExpectingNoFileRemoval(
  _ selection: [Finding],
  context: PlanContext,
  engine: PerformanceEngine = PerformanceEngine(),
  sourceLocation: SourceLocation = #_sourceLocation
) -> OperationPlan? {
  do {
    let plan = try engine.plan(selection: selection, context: context)
    expectNoFileRemoval(in: plan, sourceLocation: sourceLocation)
    return plan
  } catch {
    #expect(
      error is PlanningError,
      "a refusal is a contract conforming answer, but it must be a PlanningError",
      sourceLocation: sourceLocation)
    return nil
  }
}

/// Every non empty subset of the given tasks, smallest first, so a sweep
/// covers each task alone, every pair, and the whole set together.
func everySelection<Element>(of items: [Element]) -> [[Element]] {
  guard !items.isEmpty else { return [] }
  var subsets: [[Element]] = []
  for mask in 1..<(1 << items.count) {
    subsets.append(
      items.enumerated().compactMap { index, item in
        mask & (1 << index) == 0 ? nil : item
      })
  }
  return subsets.sorted { $0.count < $1.count }
}

/// One user journey in a line: scan, select the named maintenance tasks, and
/// plan them. Routing and repeat tests start from the plan a real selection
/// would produce rather than from an operation assembled by hand.
func planMaintenance(
  _ tasks: [MaintenanceTask] = MaintenanceTask.allCases,
  sessionID: UUID = PerformanceFixture.sessionID,
  settings: Settings = makePerformanceSettings()
) async throws -> (plan: OperationPlan, findings: [Finding]) {
  let outcome = try await runPerformanceScan(sessionID: sessionID, settings: settings)
  let selection = tasks.compactMap(outcome.maintenanceFinding(for:))
  #expect(selection.count == tasks.count, "the scan did not offer every task asked for")
  let plan = try PerformanceEngine().plan(
    selection: selection,
    context: makePlanContext(
      rules: try makeSignedPerformanceCatalog(), settings: settings, sessionID: sessionID)
  )
  return (plan, selection)
}

// MARK: - Execution

func makeExecutor(
  helper: (any PrivilegedOperationPerforming)?,
  fileSystem: any FileSystem,
  denylist: Denylist,
  ownership: any PathOwnershipPolicy = EverythingIsUserDomainPolicy(),
  isCancelled: @escaping @Sendable () -> Bool = { false }
) -> PlanExecutor {
  PlanExecutor(
    fileSystem: fileSystem,
    denylist: denylist,
    helper: helper,
    ownershipPolicy: ownership,
    environment: PerformanceFixture.environment,
    now: { PerformanceFixture.executionInstant },
    isCancelled: isCancelled
  )
}

func executorCollect(
  _ executor: PlanExecutor,
  executing plan: OperationPlan
) async -> [ExecutionEvent] {
  var events: [ExecutionEvent] = []
  for await event in executor.execute(plan) {
    events.append(event)
  }
  return events
}

/// The report is well formed only when exactly one planCompleted exists and
/// it is the final event. Returns nil otherwise so every call site fails
/// loudly on a malformed stream.
func executorFinalReport(in events: [ExecutionEvent]) -> ExecutionReport? {
  let reports = events.compactMap { event -> ExecutionReport? in
    if case .planCompleted(let report) = event { return report }
    return nil
  }
  guard reports.count == 1, let last = events.last, case .planCompleted = last else {
    return nil
  }
  return reports.first
}

func executorRefusal(in events: [ExecutionEvent]) -> ExecutionRefusal? {
  for event in events {
    if case .refused(let refusal) = event { return refusal }
  }
  return nil
}

// MARK: - Assertion helpers

func phaseOrdinal(_ phase: ScanPhase) -> Int {
  switch phase {
  case .indeterminate: return 0
  case .determinate: return 1
  case .settling: return 2
  }
}

func countersAreMonotonic(_ counters: [ScanCounters]) -> Bool {
  zip(counters, counters.dropFirst()).allSatisfy { previous, next in
    previous.filesSeen <= next.filesSeen
      && previous.bytesReclaimable <= next.bytesReclaimable
      && previous.itemCount <= next.itemCount
  }
}

/// A sentence a person can read: words, not a diagnostic dump, and no
/// acronym where the contract spells the term out.
func expectPlainSentence(
  _ sentence: String,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(sentence.isEmpty == false, sourceLocation: sourceLocation)
  #expect(sentence.contains(" "), "a sentence has words", sourceLocation: sourceLocation)
  #expect(
    sentence.first?.isUppercase == true,
    "a sentence starts with a capital",
    sourceLocation: sourceLocation)
  #expect(
    sentence.hasSuffix(".") || sentence.hasSuffix("?"),
    "a sentence ends",
    sourceLocation: sourceLocation)
  #expect(sentence.contains("Error Domain=") == false, sourceLocation: sourceLocation)
  #expect(sentence.contains("Optional(") == false, sourceLocation: sourceLocation)
  for identifier in ["flushDomainNameSystemCache", "runMaintenance", "_"] {
    #expect(
      sentence.contains(identifier) == false,
      "a sentence for a person carries no source identifier",
      sourceLocation: sourceLocation)
  }
}

/// True when the body finishes inside the allowance. Bounds "cancellation
/// ends the stream promptly"; the contract states no latency figure, so two
/// seconds is the generous ceiling. No assertion reads the clock.
func completesPromptly(
  within seconds: Double = 2.0,
  _ body: @escaping @Sendable () async -> Void
) async -> Bool {
  await withTaskGroup(of: Bool.self) { group in
    group.addTask {
      await body()
      return true
    }
    group.addTask {
      try? await Task.sleep(for: .seconds(seconds))
      return false
    }
    let finishedFirst = await group.next() ?? false
    group.cancelAll()
    return finishedFirst
  }
}
