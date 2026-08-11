import Foundation
import GleamCore
import PerformanceEngine
import Testing
import os

/// Deterministic fixtures for the Performance module's login item half (C24,
/// and C23's login item portion). Nothing here reads a wall clock, runs
/// launchctl, asks SMAppService anything, or touches the machine's own login
/// items. Every item, instant and identifier is fixed in this file, and both
/// boundaries a change can cross (this process, and the privileged side) are
/// doubles that record what reached them, so "it stayed in" and "it went out"
/// are each provable from the positive side rather than only from an absence.
enum LaunchItemFixture {

  /// The instant the manager's injected clock returns for a change this
  /// process makes, and the instant the privileged double stamps on the change
  /// it reports back. The two differ so a record can be traced to the side
  /// that produced it.
  static let userChangeInstant = Date(timeIntervalSinceReferenceDate: 800_100_000)
  static let privilegedChangeInstant = Date(timeIntervalSinceReferenceDate: 800_200_000)
  /// The clock of a second launch of the app, after the first has quit.
  static let relaunchInstant = Date(timeIntervalSinceReferenceDate: 800_300_000)

  /// C24: the identifier is stable and made of the label plus the scope, which
  /// is also the shape the helper suites use.
  static func id(_ label: String, _ scope: LaunchItem.Scope) -> LaunchItemID {
    LaunchItemID(value: "\(label)|\(scope.rawValue)")
  }

  // MARK: The fixture machine's login items

  /// A modern registration owned by an app whose name resolves.
  static let notesHelper = makeLaunchItem(
    label: "com.example.notes.helper",
    kind: .appService,
    scope: .user,
    owningAppBundleID: "com.example.notes",
    owningAppName: "Example Notes",
    path: "/Applications/Example Notes.app",
    isEnabled: true
  )

  /// A legacy user agent, the shape most third party updaters take.
  static let updaterAgent = makeLaunchItem(
    label: "com.example.updater",
    kind: .legacyLaunchAgent,
    scope: .user,
    owningAppBundleID: "com.example.updater",
    owningAppName: "Example Updater",
    path: "/Users/gleam/Library/LaunchAgents/com.example.updater.plist",
    isEnabled: true
  )

  /// System scope: the change has to leave this process.
  static let backupDaemon = makeLaunchItem(
    label: "com.example.backup",
    kind: .legacyLaunchDaemon,
    scope: .system,
    owningAppBundleID: "com.example.backup",
    owningAppName: "Example Backup",
    path: "/Library/LaunchDaemons/com.example.backup.plist",
    isEnabled: true
  )

  /// Nothing on the machine says which app registered this. It is still a real
  /// item a person may want to turn off, so it is listed.
  static let ownerlessAgent = makeLaunchItem(
    label: "com.example.stray",
    kind: .legacyLaunchAgent,
    scope: .user,
    owningAppBundleID: nil,
    owningAppName: nil,
    path: "/Users/gleam/Library/LaunchAgents/com.example.stray.plist",
    isEnabled: true
  )

  /// The bundle identifier resolves and the display name does not.
  static let telemetryDaemon = makeLaunchItem(
    label: "com.example.telemetry",
    kind: .legacyLaunchDaemon,
    scope: .system,
    owningAppBundleID: "com.example.telemetry",
    owningAppName: nil,
    path: "/Library/LaunchDaemons/com.example.telemetry.plist",
    isEnabled: true
  )

  /// Already off when MacGleam first met it. Restoring this one must leave it
  /// off, which is the case a blind re enable gets wrong.
  static let dormantAgent = makeLaunchItem(
    label: "com.example.dormant",
    kind: .legacyLaunchAgent,
    scope: .user,
    owningAppBundleID: "com.example.dormant",
    owningAppName: "Example Dormant",
    path: "/Users/gleam/Library/LaunchAgents/com.example.dormant.plist",
    isEnabled: false
  )

  static let inventory: [LaunchItem] = [
    notesHelper, updaterAgent, backupDaemon, ownerlessAgent, telemetryDaemon, dormantAgent,
  ]

  /// An identifier for something that is not registered on this machine, in
  /// either scope. Changing one of these is the "it is gone" case.
  static let ghostUserItem = id("com.example.ghost", .user)
  static let ghostSystemItem = id("com.example.ghost", .system)

  static func items(_ items: [LaunchItem]) -> [LaunchItemID] {
    items.map(\.identifier)
  }
}

// MARK: - Building items

func makeLaunchItem(
  label: String,
  kind: LaunchItem.Kind,
  scope: LaunchItem.Scope,
  owningAppBundleID: String?,
  owningAppName: String?,
  path: String,
  isEnabled: Bool
) -> LaunchItem {
  LaunchItem(
    identifier: LaunchItemFixture.id(label, scope),
    label: label,
    kind: kind,
    scope: scope,
    owningAppBundleID: owningAppBundleID,
    owningAppName: owningAppName,
    path: PerformanceFixture.path(path),
    isEnabled: isEnabled
  )
}

/// The same item in the other state. LaunchItem is a value with immutable
/// fields, so a state change is a new value rather than a mutation.
func launchItem(_ item: LaunchItem, setTo isEnabled: Bool) -> LaunchItem {
  LaunchItem(
    identifier: item.identifier,
    label: item.label,
    kind: item.kind,
    scope: item.scope,
    owningAppBundleID: item.owningAppBundleID,
    owningAppName: item.owningAppName,
    path: item.path,
    isEnabled: isEnabled
  )
}

// MARK: - The fixture machine

enum LaunchItemSourceFailure: Error, Sendable, Equatable {
  case theInventoryCouldNotBeRead
}

/// The machine's login items as this process can see them, and the one change
/// this process may make itself (C24: user scope items change in process).
/// Holds its own state, records every attempt by name, and reaches nothing
/// outside itself.
final class FakeLaunchItemSource: LaunchItemSourcing {
  struct Attempt: Sendable, Equatable {
    let item: LaunchItemID
    let enabled: Bool
  }

  private struct State {
    var items: [LaunchItem]
    var attempts: [Attempt] = []
    var listings = 0
  }

  private let state: OSAllocatedUnfairLock<State>
  private let listingFailure: LaunchItemSourceFailure?

  init(
    items: [LaunchItem] = LaunchItemFixture.inventory,
    listingFailure: LaunchItemSourceFailure? = nil
  ) {
    self.state = OSAllocatedUnfairLock(initialState: State(items: items))
    self.listingFailure = listingFailure
  }

  /// Every change this process attempted, in order. A system scope change
  /// appearing here is the routing failure the contract forbids.
  var attempts: [Attempt] {
    state.withLock { $0.attempts }
  }

  var sawNoAttempt: Bool {
    attempts.isEmpty
  }

  var listingCount: Int {
    state.withLock { $0.listings }
  }

  /// The machine as it stands now, whichever side changed it.
  var currentItems: [LaunchItem] {
    state.withLock { $0.items }
  }

  func current(_ item: LaunchItemID) -> LaunchItem? {
    state.withLock { current in current.items.first { $0.identifier == item } }
  }

  func isEnabled(_ item: LaunchItemID) -> Bool? {
    current(item)?.isEnabled
  }

  /// The privileged side reaching the machine. It changes the same items this
  /// process reads, and records no in process attempt, because none was made.
  func applyPrivilegedChange(_ enabled: Bool, item: LaunchItemID) {
    state.withLock { current in
      guard let index = current.items.firstIndex(where: { $0.identifier == item }) else { return }
      current.items[index] = launchItem(current.items[index], setTo: enabled)
    }
  }

  func items() async throws -> [LaunchItem] {
    if let listingFailure {
      throw listingFailure
    }
    return state.withLock { current in
      current.listings += 1
      return current.items
    }
  }

  func setEnabled(_ enabled: Bool, item: LaunchItemID) async throws {
    try state.withLock { current in
      current.attempts.append(Attempt(item: item, enabled: enabled))
      guard let index = current.items.firstIndex(where: { $0.identifier == item }) else {
        throw LaunchItemError.itemNotFound(item: item)
      }
      current.items[index] = launchItem(current.items[index], setTo: enabled)
    }
  }
}

/// Conforms to the inventory side and nothing else. Handing this to a scan is
/// the compile time proof that listing login items cannot change one.
struct InventoryOnlyLaunchItems: LaunchItemInventorying {
  let backing: FakeLaunchItemSource

  func items() async throws -> [LaunchItem] {
    try await backing.items()
  }
}

// MARK: - The privileged side

/// Stands in for the privileged side of a launch item change at the boundary
/// the manager sees. It records what crossed, applies the change to the same
/// fixture machine the source reads, and answers what the test scripted. It
/// never decides whether a change should have been sent, which is the routing
/// property under test, and it speaks to no daemon: the wire contract is
/// pinned in the helper suites and the real daemon is the s3b work.
final class FakePrivilegedLaunchItemChanger: PrivilegedLaunchItemChanging {
  struct Handover: Sendable, Equatable {
    let item: LaunchItemID
    let enabled: Bool
  }

  private let recorded = OSAllocatedUnfairLock(initialState: [Handover]())
  private let machine: FakeLaunchItemSource
  private let instant: Date
  private let failures: [LaunchItemID: PrivilegedLaunchItemFailure]

  init(
    applyingTo machine: FakeLaunchItemSource,
    at instant: Date = LaunchItemFixture.privilegedChangeInstant,
    failures: [LaunchItemID: PrivilegedLaunchItemFailure] = [:]
  ) {
    self.machine = machine
    self.instant = instant
    self.failures = failures
  }

  var handovers: [Handover] {
    recorded.withLock { $0 }
  }

  var sawNothing: Bool {
    handovers.isEmpty
  }

  func setLaunchItemEnabled(
    _ enabled: Bool,
    item: LaunchItemID
  ) async throws -> LaunchItemChange {
    recorded.withLock { $0.append(Handover(item: item, enabled: enabled)) }
    if let failure = failures[item] {
      throw failure
    }
    guard let previous = machine.isEnabled(item) else {
      throw PrivilegedLaunchItemFailure.itemUnresolvable
    }
    machine.applyPrivilegedChange(enabled, item: item)
    return LaunchItemChange(
      item: item,
      previousEnabled: previous,
      newEnabled: enabled,
      changedAt: instant
    )
  }
}

// MARK: - Persistence

/// The bytes a store would have written. Two stores over one file are two
/// launches of the app over one record, which is how "survives relaunch" is
/// asserted without writing anything to a real disk.
actor LaunchItemChangeFile {
  private var bytes: Data?

  init(bytes: Data? = nil) {
    self.bytes = bytes
  }

  func read() -> Data? {
    bytes
  }

  func write(_ data: Data) {
    bytes = data
  }
}

/// Persists the records the way the app would, through an encoding, so a
/// record that only ever lived in memory fails the relaunch tests instead of
/// passing them by accident.
struct FakeLaunchItemChangeStore: LaunchItemChangeStoring {
  let file: LaunchItemChangeFile

  init(file: LaunchItemChangeFile = LaunchItemChangeFile()) {
    self.file = file
  }

  func recordedChanges() async throws -> [LaunchItemChange] {
    guard let data = await file.read() else {
      return []
    }
    return try JSONDecoder().decode([LaunchItemChange].self, from: data)
  }

  func record(_ change: LaunchItemChange) async throws {
    var records = try await recordedChanges()
    records.append(change)
    let encoded = try JSONEncoder().encode(records)
    await file.write(encoded)
  }
}

/// What is on the fixture's disk, read without going through the store, so a
/// test can prove the record survived an encoding rather than trusting the
/// store that wrote it.
func persistedChanges(
  in file: LaunchItemChangeFile
) async throws -> [LaunchItemChange] {
  guard let data = await file.read() else {
    return []
  }
  return try JSONDecoder().decode([LaunchItemChange].self, from: data)
}

// MARK: - The manager under test

func makeLaunchItemManager(
  source: FakeLaunchItemSource,
  privileged: (any PrivilegedLaunchItemChanging)? = nil,
  store: any LaunchItemChangeStoring = FakeLaunchItemChangeStore(),
  now: @escaping @Sendable () -> Date = { LaunchItemFixture.userChangeInstant }
) -> LaunchItemManager {
  LaunchItemManager(source: source, privileged: privileged, store: store, now: now)
}

/// The whole fixture machine wired up: the source, the privileged side that
/// applies to the same machine, the store and its file. One value so a test
/// reads as a story rather than as four constructions.
struct LaunchItemWorld {
  let source: FakeLaunchItemSource
  let privileged: FakePrivilegedLaunchItemChanger
  let file: LaunchItemChangeFile
  let store: FakeLaunchItemChangeStore
  let manager: LaunchItemManager

  init(
    items: [LaunchItem] = LaunchItemFixture.inventory,
    privilegedFailures: [LaunchItemID: PrivilegedLaunchItemFailure] = [:],
    now: @escaping @Sendable () -> Date = { LaunchItemFixture.userChangeInstant }
  ) {
    let source = FakeLaunchItemSource(items: items)
    let privileged = FakePrivilegedLaunchItemChanger(
      applyingTo: source, failures: privilegedFailures)
    let file = LaunchItemChangeFile()
    let store = FakeLaunchItemChangeStore(file: file)
    self.source = source
    self.privileged = privileged
    self.file = file
    self.store = store
    self.manager = makeLaunchItemManager(
      source: source, privileged: privileged, store: store, now: now)
  }

  /// A second launch of the app over the same machine and the same records:
  /// new manager, new store, new clock, nothing carried in memory.
  func relaunched(
    now: @escaping @Sendable () -> Date = { LaunchItemFixture.relaunchInstant }
  ) -> (manager: LaunchItemManager, store: FakeLaunchItemChangeStore) {
    let store = FakeLaunchItemChangeStore(file: file)
    let manager = makeLaunchItemManager(
      source: source, privileged: privileged, store: store, now: now)
    return (manager, store)
  }

  var inventoryOnly: InventoryOnlyLaunchItems {
    InventoryOnlyLaunchItems(backing: source)
  }
}

// MARK: - Reading findings and operations

func launchItemCategory(
  of finding: Finding
) -> (item: LaunchItemID, scope: LaunchItem.Scope)? {
  if case .launchItem(let item, let scope) = finding.category {
    return (item, scope)
  }
  return nil
}

func launchItemChange(
  of operation: Operation
) -> (item: LaunchItemID, enabled: Bool)? {
  if case .setLaunchItemEnabled(let item, let enabled) = operation.kind {
    return (item, enabled)
  }
  return nil
}

extension ScanOutcome {
  /// Only the login item half of the Performance scan.
  var launchItemFindings: [Finding] {
    findings.filter { launchItemCategory(of: $0) != nil }
  }

  var launchItems: [LaunchItemID] {
    launchItemFindings.compactMap { launchItemCategory(of: $0)?.item }
  }

  func launchItemFinding(for item: LaunchItemID) -> Finding? {
    launchItemFindings.first { launchItemCategory(of: $0)?.item == item }
  }
}

// MARK: - Findings, operations and plans

/// A login item finding built by hand, for the selections a scan would not
/// produce. `entries` defaults to none because a login item finding names a
/// registration, never a file; the hostile tests are the ones that pass
/// entries.
func makeLaunchItemFinding(
  item: LaunchItem,
  id: UUID = PerformanceFixture.uuid(0xA1),
  sessionID: UUID = PerformanceFixture.sessionID,
  entries: [PathEntry] = [],
  risk: RiskLevel = .review,
  explanation: String = "A login item built by the tests.",
  isPreselected: Bool = false
) -> Finding {
  Finding(
    id: id,
    sessionID: sessionID,
    category: .launchItem(item: item.identifier, scope: item.scope),
    entries: entries,
    risk: risk,
    explanation: explanation,
    isPreselected: isPreselected
  )
}

func makeLaunchItemOperation(
  item: LaunchItemID,
  enabled: Bool = false,
  privilege: Operation.Privilege,
  id: UUID = PerformanceFixture.uuid(0xB1),
  findingID: UUID = PerformanceFixture.uuid(0xA1)
) -> Operation {
  Operation(
    id: id,
    findingID: findingID,
    kind: .setLaunchItemEnabled(item: item, enabled: enabled),
    privilege: privilege
  )
}

func makeLaunchItemPlan(
  _ operations: [Operation],
  sessionID: UUID = PerformanceFixture.sessionID
) -> OperationPlan {
  OperationPlan(
    id: PerformanceFixture.uuid(0xB0),
    sessionID: sessionID,
    operations: operations,
    totalBytes: 0,
    permanentDeletionConfirmation: nil
  )
}

// MARK: - Scanning and planning with an inventory

func runPerformanceScan(
  inventory: any LaunchItemInventorying,
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
  return try await collectScan(PerformanceEngine(launchItems: inventory).scan(context))
}

/// One user journey in a line: scan the fixture machine, select the named
/// login items, and plan them. Every plan level test starts from the plan a
/// real selection produces rather than from operations assembled by hand.
func planLoginItems(
  _ items: [LaunchItemID],
  inventory: any LaunchItemInventorying,
  settings: Settings = makePerformanceSettings(),
  sessionID: UUID = PerformanceFixture.sessionID
) async throws -> (plan: OperationPlan, findings: [Finding]) {
  let outcome = try await runPerformanceScan(
    inventory: inventory, sessionID: sessionID, settings: settings)
  let selection = items.compactMap(outcome.launchItemFinding(for:))
  #expect(selection.count == items.count, "the scan did not list every item asked for")
  let plan = try PerformanceEngine(launchItems: inventory).plan(
    selection: selection,
    context: makePlanContext(
      rules: try makeSignedPerformanceCatalog(), settings: settings, sessionID: sessionID)
  )
  return (plan, selection)
}

// MARK: - Execution

/// An executor that knows about login items. The launch item manager is the
/// authority on where a change happens; the operation's privilege field routes
/// nothing, which is what the routing suite asserts.
func makeLaunchItemExecutor(
  manager: (any LaunchItemManaging)?,
  helper: (any PrivilegedOperationPerforming)? = nil,
  fileSystem: any FileSystem = TrappingFileSystem(),
  denylist: Denylist,
  ownership: any PathOwnershipPolicy = EverythingIsUserDomainPolicy()
) -> PlanExecutor {
  PlanExecutor(
    fileSystem: fileSystem,
    denylist: denylist,
    helper: helper,
    ownershipPolicy: ownership,
    environment: PerformanceFixture.environment,
    now: { PerformanceFixture.executionInstant },
    isCancelled: { false },
    launchItems: manager
  )
}
