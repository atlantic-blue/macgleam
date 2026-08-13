import CleanupEngine
import CryptoKit
import Foundation
import GleamCore
import Testing

/// Foundation exports NSOperation as `Operation`; this pins the unqualified
/// name to the domain type under test for the whole module.
typealias Operation = GleamCore.Operation

/// Deterministic fixtures for the cleanup engine tests. Every date and
/// identifier is fixed and nothing reads the wall clock or the real disk.
enum CleanupFixture {

  static let createdDate = Date(timeIntervalSinceReferenceDate: 710_000_000)
  static let modifiedDate = Date(timeIntervalSinceReferenceDate: 710_000_500)

  static let sessionID = uuid(0xA1)
  static let foreignSessionID = uuid(0xA2)

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

/// The rules key pair for this suite derives from fixed bytes, so every run
/// signs with the same key. The production rules key never appears here.
enum CleanupSigningFixture {
  static let rulesPrivateKey = try! Curve25519.Signing.PrivateKey(
    rawRepresentation: Data(repeating: 0x33, count: 32)
  )
}

func makeSignedCleanupCatalog(
  version: UInt32 = 2,
  cleanupRules: [CleanupRule],
  denylist: Denylist = Denylist(patterns: [PathPattern(pattern: "/System/**")])
) throws -> RuleCatalog {
  let unsigned = RuleCatalog(
    version: RuleCatalogVersion(value: version),
    signature: Data(),
    cleanupRules: cleanupRules,
    adwareRules: [],
    denylist: denylist
  )
  let signature = try CleanupSigningFixture.rulesPrivateKey.signature(
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

func makeRule(
  identifier: String,
  category: FindingCategory,
  patterns: [String],
  risk: RiskLevel = .safe,
  preselectable: Bool = true,
  explanation: String = "Junk the system rebuilds on demand."
) -> CleanupRule {
  CleanupRule(
    identifier: identifier,
    category: category,
    pathPatterns: patterns.map { PathPattern(pattern: $0) },
    risk: risk,
    preselectable: preselectable,
    explanation: explanation
  )
}

// MARK: - Fixture trees

struct SeededFile: Sendable {
  let path: String
  let length: Int
}

/// Seeds an in memory file system with the given files, creating every
/// implied parent directory, with fixed dates throughout.
func makeSeededFileSystem(_ files: [SeededFile]) async -> InMemoryFileSystem {
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
      contents: CleanupFixture.contents(seedByte, length: file.length),
      isExecutable: false,
      created: CleanupFixture.createdDate,
      modified: CleanupFixture.modifiedDate,
      lastOpened: nil,
      extendedAttributes: [:]
    )
    seedByte &+= 1
  }
  return fileSystem
}

/// The standard fixture home: one seeded example of every C20 junk category
/// plus bystander files no cleanup rule covers.
enum JunkTree {

  static let userCacheState = "/Users/test/Library/Caches/com.example.app/state.bin"
  static let userCacheThumb = "/Users/test/Library/Caches/com.example.app/images/thumb.dat"
  static let applicationCacheBlob =
    "/Users/test/Library/Containers/com.example.app/Data/Library/Caches/blob.cache"
  static let sessionLog = "/Users/test/Library/Logs/com.example.app/session.log"
  static let brokenDownload = "/Users/test/Downloads/pending/installer.dmg.download"
  static let derivedDataObject =
    "/Users/test/Library/Developer/Xcode/DerivedData/Example-abc/Build/app.o"
  static let simulatorCacheBlob =
    "/Users/test/Library/Developer/CoreSimulator/Caches/dyld/cache.bin"
  static let browserCacheDatabase = "/Users/test/Library/Caches/com.browser.web/Cache.db"
  static let temporaryScratch = "/private/tmp/session-scratch.tmp"
  static let mailAttachment = "/Users/test/Library/Mail/Downloads/invoice.pdf"
  static let homeTrashNote = "/Users/test/.Trash/old-notes.txt"
  static let homeTrashDraft = "/Users/test/.Trash/drafts/chapter.txt"
  static let externalTrashFile = "/Volumes/External/.Trashes/501/gone.txt"

  static let bystanderDocument = "/Users/test/Documents/report.pdf"
  static let bystanderPreferences = "/Users/test/Library/Preferences/com.example.app.plist"
  static let bystanderBinary = "/Applications/Example.app/Contents/MacOS/Example"

  static let junkFiles: [SeededFile] = [
    SeededFile(path: userCacheState, length: 100),
    SeededFile(path: userCacheThumb, length: 50),
    SeededFile(path: applicationCacheBlob, length: 200),
    SeededFile(path: sessionLog, length: 300),
    SeededFile(path: brokenDownload, length: 400),
    SeededFile(path: derivedDataObject, length: 500),
    SeededFile(path: simulatorCacheBlob, length: 600),
    SeededFile(path: browserCacheDatabase, length: 700),
    SeededFile(path: temporaryScratch, length: 800),
    SeededFile(path: mailAttachment, length: 900),
    SeededFile(path: homeTrashNote, length: 110),
    SeededFile(path: homeTrashDraft, length: 120),
    SeededFile(path: externalTrashFile, length: 130),
  ]

  static let bystanderFiles: [SeededFile] = [
    SeededFile(path: bystanderDocument, length: 64),
    SeededFile(path: bystanderPreferences, length: 64),
    SeededFile(path: bystanderBinary, length: 64),
  ]

  static var junkPaths: Set<AbsolutePath> {
    Set(junkFiles.map { CleanupFixture.path($0.path) })
  }

  static func seeded(extraUserCacheFiles: Int = 0) async -> InMemoryFileSystem {
    var files = junkFiles + bystanderFiles
    for index in 0..<extraUserCacheFiles {
      files.append(
        SeededFile(
          path: "/Users/test/Library/Caches/com.example.app/bulk/file-\(index).bin",
          length: 64
        ))
    }
    return await makeSeededFileSystem(files)
  }

  /// One rule per junk category. The volume in the trash bin rule's category
  /// is a placeholder: a rule cannot know volumes ahead of time, so the
  /// engine reports the volume each matched bin actually lives on.
  static func catalog() throws -> RuleCatalog {
    try makeSignedCleanupCatalog(cleanupRules: [
      makeRule(
        identifier: "user-caches",
        category: .userCache,
        patterns: ["/Users/*/Library/Caches/com.example.app/**"],
        explanation: "Application caches the system rebuilds on demand."
      ),
      makeRule(
        identifier: "application-caches",
        category: .applicationCache,
        patterns: ["/Users/*/Library/Containers/com.example.app/Data/Library/Caches/**"],
        explanation: "Sandboxed application caches rebuilt on next launch."
      ),
      makeRule(
        identifier: "logs",
        category: .log,
        patterns: ["/Users/*/Library/Logs/**"],
        explanation: "Log files applications write for diagnostics."
      ),
      makeRule(
        identifier: "broken-downloads",
        category: .brokenDownload,
        patterns: ["/Users/*/Downloads/pending/**"],
        explanation: "Partial downloads that never completed."
      ),
      makeRule(
        identifier: "xcode-derived-data",
        category: .xcodeDerivedData,
        patterns: ["/Users/*/Library/Developer/Xcode/DerivedData/**"],
        explanation: "Build products Xcode regenerates from source."
      ),
      makeRule(
        identifier: "simulator-caches",
        category: .simulatorCache,
        patterns: ["/Users/*/Library/Developer/CoreSimulator/Caches/**"],
        explanation: "Simulator caches rebuilt when a simulator boots."
      ),
      makeRule(
        identifier: "browser-caches",
        category: .browserCache,
        patterns: ["/Users/*/Library/Caches/com.browser.web/**"],
        explanation: "Web content the browser downloads again as needed."
      ),
      makeRule(
        identifier: "temporary-files",
        category: .temporaryFile,
        patterns: ["/private/tmp/**"],
        explanation: "Temporary files left behind by finished processes."
      ),
      makeRule(
        identifier: "mail-attachments",
        category: .mailAttachmentLocalCopy,
        patterns: ["/Users/*/Library/Mail/Downloads/**"],
        explanation:
          "Local copies of mail attachments. Removing one never touches server state; the original stays with the message."
      ),
      makeRule(
        identifier: "trash-bins",
        category: .trashBin(volume: CleanupFixture.path("/")),
        patterns: ["/Users/*/.Trash/**", "/Volumes/*/.Trashes/**"],
        explanation: "Files already put in the bin, kept until the bin is emptied."
      ),
    ])
  }
}

// MARK: - Reading only file system

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

  func posixPermissions(at path: AbsolutePath) async throws -> UInt16 {
    try await backing.posixPermissions(at: path)
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

// MARK: - Ownership policies

struct UserDomainPolicy: PathOwnershipPolicy {
  func ownership(
    of path: AbsolutePath,
    environment: OwnershipEnvironment
  ) -> PathOwnership {
    .userDomain
  }
}

struct SystemDomainForPathsPolicy: PathOwnershipPolicy {
  let systemPaths: Set<AbsolutePath>

  func ownership(
    of path: AbsolutePath,
    environment: OwnershipEnvironment
  ) -> PathOwnership {
    systemPaths.contains(path) ? .systemDomain : .userDomain
  }
}

// MARK: - Context factories

func makeSettings(deletionMode: Settings.DeletionMode = .trash) -> Settings {
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
  settings: Settings = makeSettings(),
  hasFullDiskAccess: Bool = true,
  sessionID: UUID = CleanupFixture.sessionID
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
  settings: Settings = makeSettings(),
  ownership: any PathOwnershipPolicy = UserDomainPolicy(),
  sessionID: UUID = CleanupFixture.sessionID
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

func makeCleanupFinding(
  id: UUID = CleanupFixture.uuid(0xB1),
  sessionID: UUID = CleanupFixture.sessionID,
  category: FindingCategory = .userCache,
  paths: [String] = [JunkTree.userCacheState],
  byteSize: UInt64 = 1024,
  risk: RiskLevel = .safe,
  isPreselected: Bool = false
) -> Finding {
  Finding(
    id: id,
    sessionID: sessionID,
    category: category,
    entries: distributedPathEntries(paths: paths.map(CleanupFixture.path), byteSize: byteSize),
    risk: risk,
    explanation: "A reviewable cleanup finding used by the plan tests.",
    isPreselected: isPreselected
  )
}

// MARK: - Scan collection

struct ScanOutcome: Sendable {
  var orderedEvents: [ScanEvent] = []
  var findings: [Finding] = []
  var phases: [ScanPhase] = []
  var counters: [ScanCounters] = []
  var readPaths: [AbsolutePath] = []
  var degradedMessages: [String] = []

  func findings(in category: FindingCategory) -> [Finding] {
    findings.filter { $0.category == category }
  }

  var trashBinFindings: [Finding] {
    findings.filter {
      if case .trashBin = $0.category { return true }
      return false
    }
  }

  var itemisedPaths: Set<AbsolutePath> {
    findings.reduce(into: Set()) { $0.formUnion($1.paths) }
  }

  var reclaimableByteTotal: UInt64 {
    findings.reduce(0) { $0 + $1.byteSize }
  }

  /// Path entries across every yielded finding. `ScanCounters.itemCount`
  /// counts these, not findings, because one category streams as several
  /// findings (C4, C15).
  var entryCount: Int {
    findings.reduce(0) { $0 + $1.entries.count }
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
    case .reading(let path):
      outcome.readPaths.append(path)
    case .degraded(let unavailable):
      outcome.degradedMessages.append(unavailable)
    }
  }
  return outcome
}

func runCleanupScan(
  rules: RuleCatalog,
  over fileSystem: InMemoryFileSystem,
  hasFullDiskAccess: Bool = true,
  sessionID: UUID = CleanupFixture.sessionID
) async throws -> ScanOutcome {
  let context = makeScanContext(
    over: fileSystem,
    rules: rules,
    hasFullDiskAccess: hasFullDiskAccess,
    sessionID: sessionID
  )
  return try await collectScan(CleanupEngine().scan(context))
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
      && earlier.itemCount <= later.itemCount
  }
}

/// A scan reduced to the entries each category yielded, whatever partition
/// into findings the batching produced. Comparing two scans of one file system
/// state at this level is comparing what C15 promises: the entries are the
/// same, where the batch boundaries fall follows enumeration order, and C13
/// guarantees no enumeration order.
func entriesByCategory(_ outcome: ScanOutcome) -> [FindingCategory: Set<PathEntry>] {
  outcome.findings.reduce(into: [:]) { totals, finding in
    totals[finding.category, default: []].formUnion(finding.entries)
  }
}

func distinctEntryCount(_ outcome: ScanOutcome) -> Int {
  entriesByCategory(outcome).values.reduce(0) { $0 + $1.count }
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
