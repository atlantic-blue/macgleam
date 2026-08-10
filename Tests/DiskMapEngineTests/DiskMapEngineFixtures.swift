import CryptoKit
import DiskMapEngine
import Foundation
import GleamCore
import Testing

/// Foundation exports NSOperation as `Operation`; this pins the unqualified
/// name to the domain type under test for the whole module.
typealias Operation = GleamCore.Operation

/// Deterministic fixtures for the disk map engine tests. Every date and
/// identifier is fixed and nothing reads the wall clock or the real disk.
enum DiskMapFixture {

  static let createdDate = Date(timeIntervalSinceReferenceDate: 780_000_000)
  static let modifiedDate = Date(timeIntervalSinceReferenceDate: 780_000_500)

  /// The instant the executor's injected clock returns in the end to end
  /// tests.
  static let executionInstant = Date(timeIntervalSinceReferenceDate: 780_000_900)

  static let sessionID = uuid(0xE1)
  static let foreignSessionID = uuid(0xE2)

  static let volumeRoot = path("/")

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

/// The rules key pair for this suite derives from fixed bytes owned by this
/// file alone, distinct from every other suite's key material. The
/// production rules key never appears here.
enum DiskMapSigningFixture {
  static let rulesPrivateKey = try! Curve25519.Signing.PrivateKey(
    rawRepresentation: Data(repeating: 0x7A, count: 32)
  )
}

func makeSignedDiskMapCatalog(
  version: UInt32 = 2,
  denylist: Denylist = Denylist(patterns: [])
) throws -> RuleCatalog {
  let unsigned = RuleCatalog(
    version: RuleCatalogVersion(value: version),
    signature: Data(),
    cleanupRules: [],
    adwareRules: [],
    denylist: denylist
  )
  let signature = try DiskMapSigningFixture.rulesPrivateKey.signature(
    for: unsigned.canonicalContentEncoding()
  )
  return RuleCatalog(
    version: unsigned.version,
    signature: signature,
    cleanupRules: unsigned.cleanupRules,
    adwareRules: unsigned.adwareRules,
    denylist: unsigned.denylist
  )
}

// MARK: - Fixture tree

struct SeededLensFile: Sendable {
  let path: String
  let length: Int
}

/// Seeds an in memory file system with the given files, creating every
/// implied parent directory, with fixed dates throughout.
func makeSeededFileSystem(_ files: [SeededLensFile]) async -> InMemoryFileSystem {
  let fileSystem = InMemoryFileSystem()
  var seededDirectories = Set<String>()
  var seedByte: UInt8 = 1
  for file in files {
    var currentDirectory = ""
    for component in file.path.split(separator: "/").dropLast() {
      currentDirectory += "/\(component)"
      if seededDirectories.insert(currentDirectory).inserted {
        await fileSystem.seedDirectory(at: AbsolutePath(normalising: currentDirectory))
      }
    }
    await fileSystem.seedFile(
      at: AbsolutePath(normalising: file.path),
      contents: DiskMapFixture.contents(seedByte, length: file.length),
      isExecutable: false,
      created: DiskMapFixture.createdDate,
      modified: DiskMapFixture.modifiedDate,
      lastOpened: nil,
      extendedAttributes: [:]
    )
    seedByte &+= 1
  }
  return fileSystem
}

/// The standard fixture volume: a small home with one denylisted subtree so
/// selectability and totals can be asserted against known shapes.
enum LensTree {

  static let reportQ1 = "/Users/lens/Documents/reports/q1.pdf"
  static let reportQ2 = "/Users/lens/Documents/reports/q2.pdf"
  static let notes = "/Users/lens/Documents/notes.txt"
  static let photo = "/Users/lens/Pictures/photo.heic"
  static let protectedKeychain = "/Users/lens/Library/Protected/secrets.keychain"

  static let documentsDirectory = "/Users/lens/Documents"
  static let reportsDirectory = "/Users/lens/Documents/reports"
  static let picturesDirectory = "/Users/lens/Pictures"
  static let protectedDirectory = "/Users/lens/Library/Protected"

  /// A literal directory pattern: the directory matches, its contents are
  /// blocked as descendants of a blocked directory (C10).
  static let denylistPattern = "/Users/lens/Library/Protected"

  static let files: [SeededLensFile] = [
    SeededLensFile(path: reportQ1, length: 3_000),
    SeededLensFile(path: reportQ2, length: 5_000),
    SeededLensFile(path: notes, length: 1_000),
    SeededLensFile(path: photo, length: 8_000),
    SeededLensFile(path: protectedKeychain, length: 2_000),
  ]

  static func seeded(extraDocumentFiles: Int = 0) async -> InMemoryFileSystem {
    var allFiles = files
    for index in 0..<extraDocumentFiles {
      allFiles.append(
        SeededLensFile(
          path: "/Users/lens/Documents/bulk/item-\(index).bin",
          length: 64
        ))
    }
    return await makeSeededFileSystem(allFiles)
  }

  static func catalog() throws -> RuleCatalog {
    try makeSignedDiskMapCatalog(
      denylist: Denylist(patterns: [PathPattern(pattern: denylistPattern)])
    )
  }
}

// MARK: - Reading only file system

/// Conforms to the reading side and nothing else, so every map in the suite
/// is compile time proof that mapping never needs the mutating side.
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

// MARK: - Ownership policy and executor

struct UserDomainPolicy: PathOwnershipPolicy {
  func ownership(
    of path: AbsolutePath,
    environment: OwnershipEnvironment
  ) -> PathOwnership {
    .userDomain
  }
}

/// The executor construction mirrors the C17 suite: injected clock, no
/// cancellation, everything user domain.
func makeExecutor(
  fileSystem: any FileSystem,
  denylist: Denylist = Denylist(patterns: [])
) -> PlanExecutor {
  PlanExecutor(
    fileSystem: fileSystem,
    denylist: denylist,
    ownershipPolicy: UserDomainPolicy(),
    environment: OwnershipEnvironment(
      currentUserHome: DiskMapFixture.path("/Users/lens"), currentUserID: 501),
    now: { DiskMapFixture.executionInstant },
    isCancelled: { false }
  )
}

// MARK: - Context factories

func makeDiskMapSettings(
  deletionMode: Settings.DeletionMode = .trash
) -> Settings {
  Settings(
    deletionMode: deletionMode,
    largeFileThresholdBytes: 1_073_741_824,
    oldFileThresholdDays: 180,
    menuBar: MenuBarPreferences(showsStorage: true, showsMemory: false, showsProcessorLoad: true),
    motion: MotionPreferences(reduceMotionOverride: nil)
  )
}

/// Every scan context wraps the file system in the reading only value, so
/// the whole suite is built on the compile time property under test.
func makeScanContext(
  over fileSystem: InMemoryFileSystem,
  rules: RuleCatalog,
  settings: Settings = makeDiskMapSettings(),
  hasFullDiskAccess: Bool = true,
  sessionID: UUID = DiskMapFixture.sessionID
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
  settings: Settings = makeDiskMapSettings(),
  ownership: any PathOwnershipPolicy = UserDomainPolicy(),
  sessionID: UUID = DiskMapFixture.sessionID
) -> PlanContext {
  PlanContext(
    sessionID: sessionID,
    rules: rules,
    settings: settings,
    ownership: ownership
  )
}

/// A disk map selection finding as C22 mints it: category
/// diskMapSelection, risk review, never preselected, one entry per node.
func makeDiskMapSelection(
  id: UUID = DiskMapFixture.uuid(0xF1),
  sessionID: UUID = DiskMapFixture.sessionID,
  entries: [PathEntry]
) -> Finding {
  Finding(
    id: id,
    sessionID: sessionID,
    category: .diskMapSelection,
    entries: entries,
    risk: .review,
    explanation: "Files selected on the disk map for removal.",
    isPreselected: false
  )
}

// MARK: - Map collection

struct MapOutcome: Sendable {
  var updates: [DiskMapUpdate] = []
  var nodesInOrder: [DiskMapNode] = []
  var completedCount = 0

  var nodePaths: Set<AbsolutePath> {
    Set(nodesInOrder.map(\.path))
  }

  func node(at path: AbsolutePath) -> DiskMapNode? {
    nodesInOrder.last { $0.path == path }
  }

  /// Every total the stream ever reported for the path, in arrival order:
  /// the node event's initial total, then each size revision.
  func totalHistory(for path: AbsolutePath) -> [UInt64] {
    updates.compactMap { update in
      switch update {
      case .node(let node) where node.path == path:
        return node.subtreeBytes
      case .sizeRevision(let revisedPath, let subtreeBytes) where revisedPath == path:
        return subtreeBytes
      default:
        return nil
      }
    }
  }

  /// The last reported total per path once the stream has completed.
  var finalTotals: [AbsolutePath: UInt64] {
    var totals: [AbsolutePath: UInt64] = [:]
    for update in updates {
      switch update {
      case .node(let node):
        totals[node.path] = node.subtreeBytes
      case .sizeRevision(let path, let subtreeBytes):
        totals[path] = subtreeBytes
      case .completed:
        break
      }
    }
    return totals
  }

  var selectabilityByPath: [AbsolutePath: Bool] {
    var selectability: [AbsolutePath: Bool] = [:]
    for node in nodesInOrder {
      selectability[node.path] = node.isSelectable
    }
    return selectability
  }
}

func collectMap(
  _ stream: AsyncThrowingStream<DiskMapUpdate, Error>
) async throws -> MapOutcome {
  var outcome = MapOutcome()
  for try await update in stream {
    outcome.updates.append(update)
    switch update {
    case .node(let node):
      outcome.nodesInOrder.append(node)
    case .completed:
      outcome.completedCount += 1
    case .sizeRevision:
      break
    }
  }
  return outcome
}

func runMap(
  over fileSystem: InMemoryFileSystem,
  rules: RuleCatalog,
  volume: AbsolutePath = DiskMapFixture.volumeRoot,
  sessionID: UUID = DiskMapFixture.sessionID
) async throws -> MapOutcome {
  let context = makeScanContext(over: fileSystem, rules: rules, sessionID: sessionID)
  return try await collectMap(DiskMapEngine().map(volume: volume, context: context))
}

// MARK: - True totals

func componentAncestors(of path: AbsolutePath) -> [AbsolutePath] {
  var ancestors: [AbsolutePath] = [DiskMapFixture.path("/")]
  var current = ""
  for component in path.value.split(separator: "/") {
    current += "/\(component)"
    ancestors.append(AbsolutePath(normalising: current))
  }
  return ancestors
}

/// The true allocated subtree total for every path in the tree, computed
/// straight from the file system's own records: each record's allocated
/// bytes count toward itself and every ancestor up to the root.
func trueSubtreeTotals(
  on fileSystem: InMemoryFileSystem
) async throws -> [AbsolutePath: UInt64] {
  var options = EnumerationOptions.default
  options.includesHiddenFiles = true
  var totals: [AbsolutePath: UInt64] = [DiskMapFixture.volumeRoot: 0]
  for try await event in fileSystem.enumerate(
    root: DiskMapFixture.volumeRoot, options: options)
  {
    guard case .record(let record) = event else { continue }
    for ancestor in componentAncestors(of: record.path) {
      totals[ancestor, default: 0] += record.allocatedBytes
    }
  }
  return totals
}

func allocatedBytes(
  of path: String,
  on fileSystem: InMemoryFileSystem
) async throws -> UInt64 {
  try await fileSystem.metadata(at: DiskMapFixture.path(path)).allocatedBytes
}

// MARK: - Assertion helpers

func operationTarget(_ operation: Operation) -> AbsolutePath? {
  switch operation.kind {
  case .moveToTrash(let target),
    .deletePermanently(let target),
    .quarantine(let target):
    return target
  case .archive(let target, _):
    return target
  case .setLaunchItemEnabled, .runMaintenance:
    return nil
  }
}

func executorFinalReport(in events: [ExecutionEvent]) -> ExecutionReport? {
  let reports = events.compactMap { event -> ExecutionReport? in
    if case .planCompleted(let report) = event {
      return report
    }
    return nil
  }
  guard reports.count == 1, let last = events.last, case .planCompleted = last else {
    return nil
  }
  return reports.first
}

func isNonDecreasing(_ values: [UInt64]) -> Bool {
  zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }
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
