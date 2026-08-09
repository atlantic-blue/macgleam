import ClutterEngine
import CryptoKit
import Foundation
import GleamCore
import Testing

/// Foundation exports NSOperation as `Operation`; this pins the unqualified
/// name to the domain type under test for the whole module.
typealias Operation = GleamCore.Operation

/// Deterministic fixtures for the clutter engine tests. Every date and
/// identifier is fixed and nothing reads the wall clock or the real disk.
enum ClutterFixture {

  /// The reference instant every age calculation is reckoned against. It is
  /// injected into the engine at construction, so no scan reads a clock.
  static let referenceDate = Date(timeIntervalSinceReferenceDate: 770_000_000)
  static let day: TimeInterval = 86_400

  static func daysBeforeReference(_ days: Double) -> Date {
    referenceDate.addingTimeInterval(-days * day)
  }

  static let recentOpenedDate = daysBeforeReference(10)
  static let recentModifiedDate = daysBeforeReference(12)
  static let recentCreatedDate = daysBeforeReference(15)

  /// The instant the executor's injected clock returns in the end to end
  /// tests.
  static let executionInstant = Date(timeIntervalSinceReferenceDate: 770_000_100)

  static let userHome = path("/Users/test")
  static let downloadsFolder = path("/Users/test/Downloads")

  static let sessionID = uuid(0xC1)

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
enum ClutterSigningFixture {
  static let rulesPrivateKey = try! Curve25519.Signing.PrivateKey(
    rawRepresentation: Data(repeating: 0x5C, count: 32)
  )
}

func makeSignedClutterCatalog(
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
  let signature = try ClutterSigningFixture.rulesPrivateKey.signature(
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

struct SeededClutterFile: Sendable {
  var path: String
  var length: Int
  var created: Date = ClutterFixture.recentCreatedDate
  var modified: Date = ClutterFixture.recentModifiedDate
  var lastOpened: Date? = ClutterFixture.recentOpenedDate
}

/// Seeds an in memory file system with the given files, creating every
/// implied parent directory, with fixed dates throughout.
func makeSeededFileSystem(_ files: [SeededClutterFile]) async -> InMemoryFileSystem {
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
      contents: ClutterFixture.contents(seedByte, length: file.length),
      isExecutable: false,
      created: file.created,
      modified: file.modified,
      lastOpened: file.lastOpened,
      extendedAttributes: [:]
    )
    seedByte &+= 1
  }
  return fileSystem
}

/// The standard fixture home. One file sits exactly on each threshold edge,
/// one exercises the modification date fallback, three ordinary files live
/// in Downloads, and two hostile files (outside the home, denylisted) are
/// both large and old so any scope leak produces a visible finding.
enum ClutterTree {

  static let largeThresholdBytes: UInt64 = 1_000
  static let oldThresholdDays: UInt32 = 180

  static let largeExactlyAtThreshold = "/Users/test/Documents/video-archive.mov"
  static let largeOneByteUnder = "/Users/test/Documents/almost-large.zip"
  static let oldByLastOpened = "/Users/test/Documents/thesis-notes.txt"
  static let oldOneDayNewer = "/Users/test/Documents/still-fresh.txt"
  static let oldByModificationFallback = "/Users/test/Documents/never-opened.dat"
  static let freshDocument = "/Users/test/Documents/notes-today.md"
  static let downloadInstaller = "/Users/test/Downloads/installer.dmg"
  static let downloadReceipt = "/Users/test/Downloads/receipt.pdf"
  static let downloadEpisode = "/Users/test/Downloads/podcast-episode.mp3"
  static let outsideHomeLargeAndOld = "/Volumes/External/backup-image.img"
  static let denylistedLargeAndOld = "/Users/test/Documents/protected/master-thesis.psd"

  static let denylistPattern = "/Users/test/Documents/protected/**"

  static let ancientOpenedDate = ClutterFixture.daysBeforeReference(400)

  static var files: [SeededClutterFile] {
    [
      SeededClutterFile(
        path: largeExactlyAtThreshold, length: Int(largeThresholdBytes)),
      SeededClutterFile(
        path: largeOneByteUnder, length: Int(largeThresholdBytes) - 1),
      SeededClutterFile(
        path: oldByLastOpened, length: 64,
        lastOpened: ClutterFixture.daysBeforeReference(Double(oldThresholdDays))),
      SeededClutterFile(
        path: oldOneDayNewer, length: 64,
        lastOpened: ClutterFixture.daysBeforeReference(Double(oldThresholdDays) - 1)),
      SeededClutterFile(
        path: oldByModificationFallback, length: 64,
        modified: ClutterFixture.daysBeforeReference(200),
        lastOpened: nil),
      SeededClutterFile(path: freshDocument, length: 32),
      SeededClutterFile(path: downloadInstaller, length: 300),
      SeededClutterFile(path: downloadReceipt, length: 200),
      SeededClutterFile(path: downloadEpisode, length: 150),
      SeededClutterFile(
        path: outsideHomeLargeAndOld, length: 5_000, lastOpened: ancientOpenedDate),
      SeededClutterFile(
        path: denylistedLargeAndOld, length: 5_000, lastOpened: ancientOpenedDate),
    ]
  }

  static var downloadsPaths: Set<AbsolutePath> {
    [
      ClutterFixture.path(downloadInstaller),
      ClutterFixture.path(downloadReceipt),
      ClutterFixture.path(downloadEpisode),
    ]
  }

  static func seeded(extraOldDocuments: Int = 0) async -> InMemoryFileSystem {
    var allFiles = files
    for index in 0..<extraOldDocuments {
      allFiles.append(
        SeededClutterFile(
          path: "/Users/test/Documents/archive/box-\(index).dat",
          length: 64,
          lastOpened: ancientOpenedDate
        ))
    }
    return await makeSeededFileSystem(allFiles)
  }

  static func catalog() throws -> RuleCatalog {
    try makeSignedClutterCatalog(
      denylist: Denylist(patterns: [PathPattern(pattern: denylistPattern)])
    )
  }
}

// MARK: - Reading only file system

/// Conforms to the reading side and nothing else, so every scan in the
/// suite is compile time proof that scanning never needs the mutating side.
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

/// Reports pinned allocated byte figures for named paths while the logical
/// contents stay whatever was seeded, so a test can hold allocated and
/// logical sizes apart and prove which one the engine reads.
struct AllocationPinningFileSystem: FileSystemReading {
  let backing: InMemoryFileSystem
  let allocatedBytesByPath: [AbsolutePath: UInt64]

  private func repinned(_ record: FileRecord) -> FileRecord {
    guard let pinned = allocatedBytesByPath[record.path] else { return record }
    return FileRecord(
      path: record.path,
      fileID: record.fileID,
      volumeID: record.volumeID,
      allocatedBytes: pinned,
      isDirectory: record.isDirectory,
      isExecutable: record.isExecutable,
      created: record.created,
      modified: record.modified,
      lastOpened: record.lastOpened
    )
  }

  func enumerate(
    root: AbsolutePath,
    options: EnumerationOptions
  ) -> AsyncThrowingStream<EnumerationEvent, Error> {
    let inner = backing.enumerate(root: root, options: options)
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await event in inner {
            if case .record(let record) = event {
              continuation.yield(.record(repinned(record)))
            } else {
              continuation.yield(event)
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func metadata(at path: AbsolutePath) async throws -> FileRecord {
    repinned(try await backing.metadata(at: path))
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

// MARK: - Ownership policy

struct UserDomainPolicy: PathOwnershipPolicy {
  func ownership(
    of path: AbsolutePath,
    environment: OwnershipEnvironment
  ) -> PathOwnership {
    .userDomain
  }
}

// MARK: - Construction surfaces the suite demands

/// The construction surface the tests demand of the concrete C21 engine.
/// C15 fixes the scan and plan signatures; C21 names neither a clock nor a
/// home root, so both are injected here: the home the scan is scoped to and
/// the reference date every age is reckoned against. No wall clock anywhere.
func makeClutterEngine(
  userHome: AbsolutePath = ClutterFixture.userHome,
  referenceDate: Date = ClutterFixture.referenceDate
) -> ClutterEngine {
  ClutterEngine(userHome: userHome, referenceDate: referenceDate)
}

func makeClutterSettings(
  deletionMode: Settings.DeletionMode = .trash,
  largeFileThresholdBytes: UInt64 = ClutterTree.largeThresholdBytes,
  oldFileThresholdDays: UInt32 = ClutterTree.oldThresholdDays
) -> Settings {
  Settings(
    deletionMode: deletionMode,
    largeFileThresholdBytes: largeFileThresholdBytes,
    oldFileThresholdDays: oldFileThresholdDays,
    menuBar: MenuBarPreferences(showsStorage: true, showsMemory: false, showsProcessorLoad: true),
    motion: MotionPreferences(reduceMotionOverride: nil)
  )
}

func makeScanContext(
  fileSystem: any FileSystemReading,
  rules: RuleCatalog,
  settings: Settings = makeClutterSettings(),
  hasFullDiskAccess: Bool = true,
  sessionID: UUID = ClutterFixture.sessionID
) -> ScanContext {
  ScanContext(
    sessionID: sessionID,
    fileSystem: fileSystem,
    rules: rules,
    settings: settings,
    hasFullDiskAccess: hasFullDiskAccess
  )
}

func makePlanContext(
  rules: RuleCatalog,
  settings: Settings = makeClutterSettings(),
  ownership: any PathOwnershipPolicy = UserDomainPolicy(),
  sessionID: UUID = ClutterFixture.sessionID
) -> PlanContext {
  PlanContext(
    sessionID: sessionID,
    rules: rules,
    settings: settings,
    ownership: ownership
  )
}

/// Distributes a finding's byte total over its paths as entries, remainder on
/// the first entry, so the derived byteSize is exactly the requested total.
func distributedPathEntries(paths: [AbsolutePath], byteSize: UInt64) -> [PathEntry] {
  guard !paths.isEmpty else { return [] }
  let count = UInt64(paths.count)
  let share = byteSize / count
  let remainder = byteSize % count
  return paths.enumerated().map { index, path in
    PathEntry(path: path, allocatedBytes: index == 0 ? share + remainder : share)
  }
}

func makeClutterFinding(
  id: UUID = ClutterFixture.uuid(0xD1),
  sessionID: UUID = ClutterFixture.sessionID,
  category: FindingCategory = .largeFile,
  paths: [String] = [ClutterTree.largeExactlyAtThreshold],
  byteSize: UInt64 = ClutterTree.largeThresholdBytes,
  risk: RiskLevel = .review,
  isPreselected: Bool = false
) -> Finding {
  Finding(
    id: id,
    sessionID: sessionID,
    category: category,
    entries: distributedPathEntries(paths: paths.map(ClutterFixture.path), byteSize: byteSize),
    risk: risk,
    explanation: "A reviewable clutter finding used by the plan tests.",
    isPreselected: isPreselected
  )
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
    environment: OwnershipEnvironment(currentUserHome: ClutterFixture.userHome, currentUserID: 501),
    now: { ClutterFixture.executionInstant },
    isCancelled: { false }
  )
}

// MARK: - Scan collection

struct ScanOutcome: Sendable {
  var orderedEvents: [ScanEvent] = []
  var findings: [Finding] = []
  var phases: [ScanPhase] = []
  var counters: [ScanCounters] = []
  var degradedMessages: [String] = []

  func findings(in category: FindingCategory) -> [Finding] {
    findings.filter { $0.category == category }
  }

  func pathSets(in category: FindingCategory) -> Set<Set<AbsolutePath>> {
    Set(findings(in: category).map { Set($0.paths) })
  }

  var itemisedPaths: Set<AbsolutePath> {
    findings.reduce(into: Set()) { $0.formUnion($1.paths) }
  }

  var reclaimableByteTotal: UInt64 {
    findings.reduce(0) { $0 + $1.byteSize }
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

func runClutterScan(
  rules: RuleCatalog,
  over fileSystem: InMemoryFileSystem,
  settings: Settings = makeClutterSettings(),
  engine: ClutterEngine = makeClutterEngine(),
  sessionID: UUID = ClutterFixture.sessionID
) async throws -> ScanOutcome {
  let context = makeScanContext(
    fileSystem: ReadingOnlyFileSystem(backing: fileSystem),
    rules: rules,
    settings: settings,
    sessionID: sessionID
  )
  return try await collectScan(engine.scan(context))
}

// MARK: - Assertion helpers

func allocatedByteTotal(
  of paths: [AbsolutePath],
  on fileSystem: InMemoryFileSystem
) async throws -> UInt64 {
  var total: UInt64 = 0
  for path in paths {
    total += try await fileSystem.metadata(at: path).allocatedBytes
  }
  return total
}

func phaseOrdinal(_ phase: ScanPhase) -> Int {
  switch phase {
  case .indeterminate: return 0
  case .determinate: return 1
  case .settling: return 2
  }
}

func countersAreMonotonic(_ counters: [ScanCounters]) -> Bool {
  zip(counters, counters.dropFirst()).allSatisfy { earlier, later in
    earlier.filesSeen <= later.filesSeen
      && earlier.bytesReclaimable <= later.bytesReclaimable
      && earlier.findingCount <= later.findingCount
  }
}

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
