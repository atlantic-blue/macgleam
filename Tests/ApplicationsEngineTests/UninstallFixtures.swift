import ApplicationsEngine
import CryptoKit
import Foundation
import GleamCore
import Testing

/// Foundation exports NSOperation as `Operation`; this pins the unqualified
/// name to the domain type under test for the whole module.
typealias Operation = GleamCore.Operation

/// Deterministic fixtures for the uninstall half of C26, wired to the real
/// SafetyNet store (C18) and the real executor (C17).
///
/// Three properties hold across every suite here. Nothing reads a wall clock:
/// the instant the store stamps and the instant the executor reports are
/// injected. Nothing touches a real file: the whole world is the in memory
/// file system, and the store writes its payloads and its manifest through
/// that same file system. And nothing stands in for the store: an uninstall's
/// promise is that it is reversible, so the thing that has to keep the promise
/// is the thing under test, never a fake that agrees with it.
enum UninstallFixture {

  /// Where the application keeps the SafetyNet, inside Application Support so
  /// it outlives the application bundle (C18). It sits inside a recognised
  /// leftover location on purpose: that is where it lives on a real machine.
  static let storeDirectory = ApplicationsFixture.path(
    "\(ApplicationsFixture.userLibrary)/Application Support/MacGleam/SafetyNet")

  /// The instant the store's injected date source returns, so `storedAt` and
  /// `expiresAt` are fixed values rather than ranges.
  static let storeInstant = Date(timeIntervalSince1970: 1_726_000_000)
  static let executionInstant = Date(timeIntervalSince1970: 1_726_000_500)

  static let environment = OwnershipEnvironment(
    currentUserHome: ApplicationsFixture.path(ApplicationsFixture.home),
    currentUserID: 501
  )

  /// A second binary inside the mail bundle, seeded executable and tagged.
  /// The fixture disk's own bundles carry no execute bit anywhere, and an
  /// application whose binary comes back from the SafetyNet without one
  /// cannot be launched, which is the whole point of restoring it.
  static let mailExecutable = "/Applications/ExampleMail.app/Contents/MacOS/ExampleMail"

  static let mailExecutableAttributes: [String: Data] = [
    "com.apple.quarantine": Data([0x00, 0x81, 0x4D, 0x21]),
    "com.apple.metadata:_kMDItemUserTags": Data([0x11, 0x22, 0x33, 0x44]),
  ]

  /// The bytes of the file a test parks on an origin path to occupy it.
  static let occupierContents = Data(repeating: 0x5A, count: 64)
}

// MARK: - The denylist

/// The effective denylist obtained the way production obtains one: a
/// catalogue signed with this suite's own key, verified and adopted by a real
/// store, independent of any engine.
func applicationsDenylist(blocking patterns: [String] = []) async throws -> Denylist {
  let key = try Curve25519.Signing.PrivateKey(
    rawRepresentation: ApplicationsFixture.signingKeySeed)
  let catalog = try makeSignedApplicationsCatalog(version: 1, blocking: patterns)
  let verifier = try RuleCatalogVerifier(publicKey: key.publicKey.rawRepresentation)
  let store = try RuleCatalogStore(baseline: catalog, verifier: verifier)
  return await store.effectiveDenylist
}

// MARK: - Ownership policies

/// Everything runs in this process. The uninstall suites use this so their
/// assertions are about the SafetyNet rather than about privilege routing,
/// which C17 and C31 pin in their own suites.
struct UninstallUserDomainPolicy: PathOwnershipPolicy {
  func ownership(of path: AbsolutePath, environment: OwnershipEnvironment) -> PathOwnership {
    .userDomain
  }
}

/// The realistic answer: the user's own home is theirs, everything else is
/// the helper's. The fixture disk carries a launch daemon in /Library, so
/// this policy is what decides an operation's privilege at plan time (C7).
struct UninstallHomeOwnershipPolicy: PathOwnershipPolicy {
  func ownership(of path: AbsolutePath, environment: OwnershipEnvironment) -> PathOwnership {
    let home = ApplicationsFixture.path(ApplicationsFixture.home)
    return path == home || path.isDescendant(of: home) ? .userDomain : .systemDomain
  }
}

// MARK: - Construction surfaces the tests demand

/// The C18 store, constructed over the fixture disk. The directory and the
/// instant are injected, so no test reads a wall clock and a second store can
/// be built over the same directory.
func makeUninstallSafetyNet(
  fileSystem: any FileSystem,
  denylist: Denylist,
  directory: AbsolutePath = UninstallFixture.storeDirectory,
  now: @escaping @Sendable () -> Date = { UninstallFixture.storeInstant }
) -> SafetyNetStore {
  SafetyNetStore(
    directory: directory,
    fileSystem: fileSystem,
    denylist: denylist,
    now: now
  )
}

/// The construction surface the uninstall demands of the C17 executor: the
/// SafetyNet store is injected, because "quarantine and archive operations
/// route through the SafetyNet store; the executor never invents storage
/// paths itself" is a wiring the executor cannot satisfy without holding one.
func makeUninstallExecutor(
  fileSystem: any FileSystem,
  denylist: Denylist,
  safetyNet: any SafetyNetStoring,
  ownership: any PathOwnershipPolicy = UninstallUserDomainPolicy(),
  isCancelled: @escaping @Sendable () -> Bool = { false }
) -> PlanExecutor {
  PlanExecutor(
    fileSystem: fileSystem,
    denylist: denylist,
    ownershipPolicy: ownership,
    environment: UninstallFixture.environment,
    safetyNet: safetyNet,
    now: { UninstallFixture.executionInstant },
    isCancelled: isCancelled
  )
}

func makeUninstallPlanContext(
  rules: RuleCatalog,
  settings: Settings = makeApplicationsSettings(),
  ownership: any PathOwnershipPolicy = UninstallUserDomainPolicy(),
  sessionID: UUID = ApplicationsFixture.sessionID
) -> PlanContext {
  PlanContext(
    sessionID: sessionID,
    rules: rules,
    settings: settings,
    ownership: ownership
  )
}

// MARK: - The fixture disk

/// The adversarial application world with one addition: a real executable
/// inside the mail bundle, carrying extended attributes, so restore fidelity
/// is a statement about a file somebody could launch again.
func uninstallWorld() async throws -> InMemoryFileSystem {
  let fileSystem = try await ApplicationWorld.seeded()
  await fileSystem.seedFile(
    at: ApplicationsFixture.path(UninstallFixture.mailExecutable),
    contents: ApplicationsFixture.contents(0x77, length: 3_072),
    isExecutable: true,
    created: ApplicationsFixture.createdDate,
    modified: ApplicationsFixture.modifiedDate,
    lastOpened: nil,
    extendedAttributes: UninstallFixture.mailExecutableAttributes
  )
  return fileSystem
}

// MARK: - Scanning, selecting, planning

/// One scanned world, ready to select from.
struct UninstallSetup: Sendable {
  let fileSystem: InMemoryFileSystem
  let outcome: ScanOutcome
  let catalog: RuleCatalog
}

func uninstallSetup(
  blocking patterns: [String] = [],
  sessionID: UUID = ApplicationsFixture.sessionID
) async throws -> UninstallSetup {
  let fileSystem = try await uninstallWorld()
  let catalog = try makeSignedApplicationsCatalog(blocking: patterns)
  let context = makeScanContext(
    over: fileSystem, rules: catalog, sessionID: sessionID)
  let outcome = try await collectScan(ApplicationsEngine().scan(context))
  expectCompleteScan(outcome)
  return UninstallSetup(fileSystem: fileSystem, outcome: outcome, catalog: catalog)
}

/// Everything the review would show for one application: its bundle finding
/// first, then its leftover findings ordered by their first path, so a
/// selection is the same list every run whatever order the scan emitted.
func uninstallFindings(of bundleID: String, in outcome: ScanOutcome) -> [Finding] {
  let bundles = outcome.bundleFindings.filter { applicationBundleID(of: $0) == bundleID }
  let leftovers = outcome.leftoverFindings
    .filter { applicationBundleID(of: $0) == bundleID }
    .sorted { ($0.paths.first?.value ?? "") < ($1.paths.first?.value ?? "") }
  return bundles + leftovers
}

func uninstallSelection(
  of bundleIDs: [String],
  in outcome: ScanOutcome,
  sourceLocation: SourceLocation = #_sourceLocation
) -> [Finding] {
  let selection = bundleIDs.flatMap { uninstallFindings(of: $0, in: outcome) }
  #expect(
    selection.isEmpty == false,
    "the scan offered nothing for \(bundleIDs), so nothing below this line proves anything",
    sourceLocation: sourceLocation)
  return selection
}

/// The paths one application's uninstall covers: the bundle and every
/// leftover attributed to it, in selection order.
func uninstallPaths(of selection: [Finding]) -> [AbsolutePath] {
  selection.flatMap(\.paths)
}

// MARK: - Reading a plan

func archiveTarget(of operation: Operation) -> AbsolutePath? {
  if case .archive(let target, _) = operation.kind { return target }
  return nil
}

func archiveGroupID(of operation: Operation) -> UUID? {
  if case .archive(_, let groupID) = operation.kind { return groupID }
  return nil
}

func archiveTargets(in plan: OperationPlan) -> [AbsolutePath] {
  plan.operations.compactMap(archiveTarget)
}

func archiveGroupIDs(in plan: OperationPlan) -> Set<UUID> {
  Set(plan.operations.compactMap(archiveGroupID))
}

/// The group identifiers carried by the operations that came from one
/// application's findings. One uninstall is one group, so this set has
/// exactly one member for an application that was selected.
func archiveGroupIDs(
  ofBundle bundleID: String,
  in plan: OperationPlan,
  selection: [Finding]
) -> Set<UUID> {
  let findingIDs = Set(
    selection.filter { applicationBundleID(of: $0) == bundleID }.map(\.id))
  return Set(
    plan.operations
      .filter { findingIDs.contains($0.findingID) }
      .compactMap(archiveGroupID))
}

/// A readable name for the kind, so a failure says which operation appeared
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

/// True for the two kinds that take a file away without putting it anywhere
/// it can be got back from. C26's safety property is that no uninstall plan
/// contains one, so the question is asked once here and every suite asks it
/// rather than writing its own switch.
func isIrreversibleRemoval(_ kind: Operation.Kind) -> Bool {
  switch kind {
  case .moveToTrash, .deletePermanently:
    return true
  case .archive, .quarantine, .setLaunchItemEnabled, .runMaintenance:
    return false
  }
}

func isArchive(_ kind: Operation.Kind) -> Bool {
  if case .archive = kind { return true }
  return false
}

/// The one assertion every uninstall plan in these suites passes through,
/// whatever produced it. Checked by kind rather than by target, so an
/// operation aimed at a path nobody thought of still fails it.
func expectArchiveOnly(
  in plan: OperationPlan,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  let removals = plan.operations.map(\.kind).filter(isIrreversibleRemoval).map(kindName)
  #expect(
    removals.isEmpty,
    "C26: no uninstall plan ever contains moveToTrash or deletePermanently, found \(removals)",
    sourceLocation: sourceLocation)
  let strangers = plan.operations.map(\.kind).filter { !isArchive($0) }.map(kindName)
  #expect(
    strangers.isEmpty,
    "an uninstall plans archives and nothing else, found \(strangers)",
    sourceLocation: sourceLocation)
  #expect(
    plan.permanentDeletionConfirmation == nil,
    "a plan that deletes nothing permanently has nothing to confirm the scope of",
    sourceLocation: sourceLocation)
}

/// Planning either refuses or produces a plan; both are contract conforming
/// answers to a hostile selection, and neither may yield a removal. Returns
/// the plan when one was produced so a caller can assert more about it.
@discardableResult
func planExpectingArchiveOnly(
  _ selection: [Finding],
  context: PlanContext,
  engine: ApplicationsEngine = ApplicationsEngine(),
  sourceLocation: SourceLocation = #_sourceLocation
) -> OperationPlan? {
  do {
    let plan = try engine.plan(selection: selection, context: context)
    expectArchiveOnly(in: plan, sourceLocation: sourceLocation)
    return plan
  } catch {
    #expect(
      error is PlanningError,
      "a refusal is a contract conforming answer, but it must be a PlanningError",
      sourceLocation: sourceLocation)
    return nil
  }
}

/// Every non empty subset of the given findings, smallest first, so a sweep
/// covers each finding alone, every pair, and the whole set together.
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

// MARK: - Findings built by hand

/// A finding from another module, carrying real paths from the fixture disk.
/// Feeding one of these to the uninstall plan builder is the hostile case
/// C26's "no uninstall plan ever contains moveToTrash or deletePermanently"
/// has to survive.
func makeForeignFinding(
  id: UUID = ApplicationsFixture.uuid(0xE1),
  sessionID: UUID = ApplicationsFixture.sessionID,
  category: FindingCategory = .userCache,
  paths: [String],
  bytesEach: UInt64 = 512,
  risk: RiskLevel = .safe,
  isPreselected: Bool = true
) -> Finding {
  Finding(
    id: id,
    sessionID: sessionID,
    category: category,
    entries: paths.map {
      PathEntry(path: ApplicationsFixture.path($0), allocatedBytes: bytesEach)
    },
    risk: risk,
    explanation: "A finding from another module, carrying paths that can be removed.",
    isPreselected: isPreselected
  )
}

/// An Applications finding built by hand, for the selections a scan would
/// never produce.
func makeApplicationFinding(
  id: UUID = ApplicationsFixture.uuid(0xD1),
  sessionID: UUID = ApplicationsFixture.sessionID,
  category: FindingCategory,
  paths: [String],
  bytesEach: UInt64 = 1_024,
  risk: RiskLevel = .review,
  isPreselected: Bool = false
) -> Finding {
  Finding(
    id: id,
    sessionID: sessionID,
    category: category,
    entries: paths.map {
      PathEntry(path: ApplicationsFixture.path($0), allocatedBytes: bytesEach)
    },
    risk: risk,
    explanation: "An application row built by the tests.",
    isPreselected: isPreselected
  )
}

// MARK: - Observing the disk through the boundary

/// Everything about a path that a restore has to reinstate, read back through
/// C13 alone. Compared attribute by attribute rather than whole, so a failure
/// names what was lost.
struct UninstallPathState: Equatable, Sendable {
  var isDirectory: Bool
  var contents: Data?
  var posixPermissions: UInt16
  var extendedAttributes: [String: Data]
  var created: Date?
  var modified: Date?
}

func uninstallState(
  of path: AbsolutePath,
  in fileSystem: any FileSystem
) async throws -> UninstallPathState {
  let record = try await fileSystem.metadata(at: path)
  return UninstallPathState(
    isDirectory: record.isDirectory,
    contents: record.isDirectory
      ? nil : try await fileSystem.readData(at: path, maxBytes: 10_000_000),
    posixPermissions: try await fileSystem.posixPermissions(at: path),
    extendedAttributes: try await fileSystem.extendedAttributes(at: path),
    created: record.created,
    modified: record.modified
  )
}

/// The state of a path and of everything underneath it. An application is a
/// directory, so "the bundle came back" is only worth saying about the whole
/// subtree.
func uninstallSubtreeState(
  of root: AbsolutePath,
  in fileSystem: any FileSystem
) async throws -> [AbsolutePath: UninstallPathState] {
  var states: [AbsolutePath: UninstallPathState] = [:]
  states[root] = try await uninstallState(of: root, in: fileSystem)
  guard states[root]?.isDirectory == true else { return states }
  var options = EnumerationOptions.default
  options.includesHiddenFiles = true
  options.descendsIntoPackages = true
  for try await event in fileSystem.enumerate(root: root, options: options) {
    if case .record(let record) = event {
      states[record.path] = try await uninstallState(of: record.path, in: fileSystem)
    }
  }
  return states
}

func uninstallSubtreeState(
  of roots: [AbsolutePath],
  in fileSystem: any FileSystem
) async throws -> [AbsolutePath: UninstallPathState] {
  var states: [AbsolutePath: UninstallPathState] = [:]
  for root in roots {
    for (path, state) in try await uninstallSubtreeState(of: root, in: fileSystem) {
      states[path] = state
    }
  }
  return states
}

/// Asserts fidelity one attribute at a time. A path that merely exists passes
/// "it came back"; only this catches a lost attribute, and it names which one.
func expectSamePath(
  _ actual: UninstallPathState,
  _ expected: UninstallPathState,
  at path: AbsolutePath,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(
    actual.isDirectory == expected.isDirectory, "\(path.value): kind",
    sourceLocation: sourceLocation)
  #expect(
    actual.contents == expected.contents, "\(path.value): contents",
    sourceLocation: sourceLocation)
  #expect(
    actual.posixPermissions == expected.posixPermissions, "\(path.value): permission mode",
    sourceLocation: sourceLocation)
  #expect(
    actual.extendedAttributes == expected.extendedAttributes,
    "\(path.value): extended attributes", sourceLocation: sourceLocation)
  #expect(
    actual.created == expected.created, "\(path.value): creation date",
    sourceLocation: sourceLocation)
  #expect(
    actual.modified == expected.modified, "\(path.value): modification date",
    sourceLocation: sourceLocation)
}

/// Every path in the captured tree is back, and each one attribute for
/// attribute. The count is asserted too, so a restore that drops a file
/// deep inside a bundle cannot pass by putting the top level back.
func expectSameTree(
  _ before: [AbsolutePath: UninstallPathState],
  in fileSystem: any FileSystem,
  sourceLocation: SourceLocation = #_sourceLocation
) async throws {
  #expect(
    before.isEmpty == false,
    "nothing was captured, so nothing below this line proves anything",
    sourceLocation: sourceLocation)
  for (path, expected) in before.sorted(by: { $0.key.value < $1.key.value }) {
    guard await fileSystem.exists(path) else {
      Issue.record("\(path.value) did not come back", sourceLocation: sourceLocation)
      continue
    }
    let actual = try await uninstallState(of: path, in: fileSystem)
    expectSamePath(actual, expected, at: path, sourceLocation: sourceLocation)
  }
}

// MARK: - Running the uninstall

/// One whole journey: scan the fixture disk, select the named applications,
/// plan the uninstall, and run it through the real executor into the real
/// SafetyNet store.
struct UninstallRun: Sendable {
  let fileSystem: InMemoryFileSystem
  let store: SafetyNetStore
  let selection: [Finding]
  let plan: OperationPlan
  let events: [ExecutionEvent]
  let before: [AbsolutePath: UninstallPathState]

  var targets: [AbsolutePath] { archiveTargets(in: plan) }
}

func runUninstall(
  of bundleIDs: [String],
  blocking patterns: [String] = [],
  deletionMode: Settings.DeletionMode = .trash,
  ownership: any PathOwnershipPolicy = UninstallUserDomainPolicy(),
  sourceLocation: SourceLocation = #_sourceLocation
) async throws -> UninstallRun {
  let setup = try await uninstallSetup(blocking: patterns)
  let selection = uninstallSelection(of: bundleIDs, in: setup.outcome)
  let plan = try ApplicationsEngine().plan(
    selection: selection,
    context: makeUninstallPlanContext(
      rules: setup.catalog,
      settings: makeApplicationsSettings(deletionMode: deletionMode),
      ownership: ownership
    )
  )
  // Every assertion downstream of an uninstall is about files that moved. A
  // plan with no operations satisfies most of them by doing nothing at all,
  // so the journey refuses to be run vacuously.
  #expect(
    plan.operations.isEmpty == false,
    "the uninstall planned nothing, so nothing downstream of this proves anything",
    sourceLocation: sourceLocation)
  let before = try await uninstallSubtreeState(
    of: archiveTargets(in: plan), in: setup.fileSystem)
  let denylist = try await applicationsDenylist(blocking: patterns)
  let store = makeUninstallSafetyNet(fileSystem: setup.fileSystem, denylist: denylist)
  let executor = makeUninstallExecutor(
    fileSystem: setup.fileSystem,
    denylist: denylist,
    safetyNet: store,
    ownership: ownership
  )
  var events: [ExecutionEvent] = []
  for await event in executor.execute(plan) {
    events.append(event)
  }
  return UninstallRun(
    fileSystem: setup.fileSystem,
    store: store,
    selection: selection,
    plan: plan,
    events: events,
    before: before
  )
}

/// The report is well formed only when exactly one planCompleted exists and
/// it is the final event. Returns nil otherwise so every call site fails
/// loudly on a malformed stream.
func uninstallFinalReport(in events: [ExecutionEvent]) -> ExecutionReport? {
  let reports = events.compactMap { event -> ExecutionReport? in
    if case .planCompleted(let report) = event { return report }
    return nil
  }
  guard reports.count == 1, let last = events.last, case .planCompleted = last else {
    return nil
  }
  return reports.first
}

func isCompleted(_ result: OperationResult) -> Bool {
  if case .completed = result { return true }
  return false
}

// MARK: - Reading the store

func storedItem(
  forOrigin origin: AbsolutePath,
  in items: [SafetyNetItem]
) -> SafetyNetItem? {
  items.first { $0.originPath == origin }
}

func storedOriginPaths(_ items: [SafetyNetItem]) -> Set<AbsolutePath> {
  Set(items.map(\.originPath))
}
