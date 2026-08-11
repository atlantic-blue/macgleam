import Foundation
import GleamCore
import LeftoversEngine

// Fixtures for the s2b duplicates tests. Everything here is prefixed
// Duplicates to stay clear of the s2a fixture symbols.

// MARK: - Fixed clock and tree constants

let duplicatesReferenceDate = Date(timeIntervalSince1970: 1_755_000_000)
let duplicatesFileDate = Date(timeIntervalSince1970: 1_755_000_000 - 86_400)
let duplicatesUserHome = AbsolutePath(normalising: "/Users/mgduptest")
let duplicatesSigningKeyBytes = Data(repeating: 0x6D, count: 32)

// MARK: - Content builders

func duplicatesContent(byte: UInt8, count: Int = 64) -> Data {
  Data(repeating: byte, count: count)
}

// MARK: - Fake file

struct DuplicatesFakeFile: Sendable {
  let path: AbsolutePath
  let contents: Data
  let allocatedBytes: UInt64
  let created: Date?
  let modified: Date?
  let lastOpened: Date?
}

func duplicatesFile(
  _ relativePath: String,
  content: Data,
  allocatedBytes: UInt64 = 4_096
) -> DuplicatesFakeFile {
  DuplicatesFakeFile(
    path: AbsolutePath(normalising: duplicatesUserHome.value + "/" + relativePath),
    contents: content,
    allocatedBytes: allocatedBytes,
    created: duplicatesFileDate,
    modified: duplicatesFileDate,
    lastOpened: duplicatesFileDate
  )
}

func duplicatesFileAt(
  absolute: String,
  content: Data,
  allocatedBytes: UInt64 = 4_096
) -> DuplicatesFakeFile {
  DuplicatesFakeFile(
    path: AbsolutePath(normalising: absolute),
    contents: content,
    allocatedBytes: allocatedBytes,
    created: duplicatesFileDate,
    modified: duplicatesFileDate,
    lastOpened: duplicatesFileDate
  )
}

// MARK: - In memory FileSystemReading

struct DuplicatesFakeFileSystem: FileSystemReading {
  private let filesByPath: [AbsolutePath: DuplicatesFakeFile]
  private let fileIDs: [AbsolutePath: UInt64]
  private let directoryIDs: [AbsolutePath: UInt64]

  init(files: [DuplicatesFakeFile]) {
    var byPath: [AbsolutePath: DuplicatesFakeFile] = [:]
    for file in files { byPath[file.path] = file }
    self.filesByPath = byPath

    var ids: [AbsolutePath: UInt64] = [:]
    for (index, path) in byPath.keys.sorted().enumerated() {
      ids[path] = UInt64(index + 1)
    }
    self.fileIDs = ids

    var directories: Set<AbsolutePath> = []
    for file in files {
      let components = file.path.value.split(separator: "/").map(String.init)
      guard components.count > 1 else { continue }
      var running = ""
      for component in components.dropLast() {
        running += "/" + component
        directories.insert(AbsolutePath(normalising: running))
      }
    }
    var directoryIdentifiers: [AbsolutePath: UInt64] = [:]
    for (index, path) in directories.sorted().enumerated() {
      directoryIdentifiers[path] = UInt64(1_000_000 + index)
    }
    self.directoryIDs = directoryIdentifiers
  }

  func enumerate(
    root: AbsolutePath,
    options: EnumerationOptions
  ) -> AsyncThrowingStream<EnumerationEvent, Error> {
    let records = recordsUnder(root: root, options: options)
    return AsyncThrowingStream { continuation in
      for record in records {
        continuation.yield(.record(record))
      }
      continuation.finish()
    }
  }

  func metadata(at path: AbsolutePath) async throws -> FileRecord {
    if let file = filesByPath[path] {
      return fileRecord(for: file)
    }
    if directoryIDs[path] != nil {
      return directoryRecord(for: path)
    }
    throw FileSystemError.notFound(path)
  }

  func readData(at path: AbsolutePath, maxBytes: UInt64) async throws -> Data {
    guard let file = filesByPath[path] else {
      if directoryIDs[path] != nil {
        throw FileSystemError.ioFailure(path, description: "The path is a directory.")
      }
      throw FileSystemError.notFound(path)
    }
    let byteCount = Int(min(maxBytes, UInt64(file.contents.count)))
    return Data(file.contents.prefix(byteCount))
  }

  func extendedAttributes(at path: AbsolutePath) async throws -> [String: Data] {
    guard filesByPath[path] != nil || directoryIDs[path] != nil else {
      throw FileSystemError.notFound(path)
    }
    return [:]
  }

  func exists(_ path: AbsolutePath) async -> Bool {
    filesByPath[path] != nil || directoryIDs[path] != nil
  }

  func volumeInfo(at path: AbsolutePath) async throws -> VolumeInfo {
    VolumeInfo(
      root: AbsolutePath(normalising: "/"),
      volumeID: 1,
      capacityBytes: 512 * 1_073_741_824,
      availableBytes: 256 * 1_073_741_824,
      isInternal: true
    )
  }

  private func recordsUnder(
    root: AbsolutePath,
    options: EnumerationOptions
  ) -> [FileRecord] {
    func isSkipped(_ path: AbsolutePath) -> Bool {
      options.skipSubtrees.contains { path == $0 || path.isDescendant(of: $0) }
    }
    let directoryRecords = directoryIDs.keys
      .filter { $0.isDescendant(of: root) && !isSkipped($0) }
      .sorted()
      .map(directoryRecord(for:))
    let fileRecords = filesByPath.values
      .filter { $0.path.isDescendant(of: root) && !isSkipped($0.path) }
      .sorted { $0.path < $1.path }
      .map(fileRecord(for:))
    return directoryRecords + fileRecords
  }

  private func fileRecord(for file: DuplicatesFakeFile) -> FileRecord {
    FileRecord(
      path: file.path,
      fileID: fileIDs[file.path] ?? 0,
      volumeID: 1,
      allocatedBytes: file.allocatedBytes,
      isDirectory: false,
      isExecutable: false,
      created: file.created,
      modified: file.modified,
      lastOpened: file.lastOpened
    )
  }

  private func directoryRecord(for path: AbsolutePath) -> FileRecord {
    FileRecord(
      path: path,
      fileID: directoryIDs[path] ?? 0,
      volumeID: 1,
      allocatedBytes: 0,
      isDirectory: true,
      isExecutable: false,
      created: duplicatesFileDate,
      modified: duplicatesFileDate,
      lastOpened: nil
    )
  }
}

// MARK: - Ownership policy

struct DuplicatesOwnershipPolicy: PathOwnershipPolicy {
  func ownership(
    of path: AbsolutePath,
    environment: OwnershipEnvironment
  ) -> PathOwnership {
    if path == environment.currentUserHome
      || path.isDescendant(of: environment.currentUserHome)
    {
      return .userDomain
    }
    return .systemDomain
  }
}

// MARK: - Contexts

func duplicatesSettings() -> Settings {
  var settings = Settings.defaults
  settings.largeFileThresholdBytes = 1 << 40
  settings.oldFileThresholdDays = 36_500
  return settings
}

func duplicatesRuleCatalog(denylistPatterns: [String] = []) -> RuleCatalog {
  RuleCatalog(
    version: RuleCatalogVersion(value: 1),
    signature: duplicatesSigningKeyBytes,
    cleanupRules: [],
    adwareRules: [],
    denylist: Denylist(patterns: denylistPatterns.map { PathPattern(pattern: $0) })
  )
}

func duplicatesScanContext(
  sessionID: UUID = UUID(),
  files: [DuplicatesFakeFile],
  denylistPatterns: [String] = []
) -> ScanContext {
  ScanContext(
    sessionID: sessionID,
    fileSystem: DuplicatesFakeFileSystem(files: files),
    rules: duplicatesRuleCatalog(denylistPatterns: denylistPatterns),
    settings: duplicatesSettings(),
    hasFullDiskAccess: true
  )
}

func duplicatesPlanContext(
  sessionID: UUID,
  denylistPatterns: [String] = []
) -> PlanContext {
  PlanContext(
    sessionID: sessionID,
    rules: duplicatesRuleCatalog(denylistPatterns: denylistPatterns),
    settings: duplicatesSettings(),
    ownership: DuplicatesOwnershipPolicy()
  )
}

func duplicatesEngine() -> LeftoversEngine {
  LeftoversEngine(userHome: duplicatesUserHome, referenceDate: duplicatesReferenceDate)
}

// MARK: - Scan collection

struct DuplicatesScanOutcome {
  var findings: [Finding] = []
  var phases: [ScanPhase] = []
  var counters: [ScanCounters] = []
  var degradedNotices: [String] = []
}

func duplicatesRunScan(context: ScanContext) async throws -> DuplicatesScanOutcome {
  let engine = duplicatesEngine()
  var outcome = DuplicatesScanOutcome()
  for try await event in engine.scan(context) {
    switch event {
    case .finding(let finding):
      outcome.findings.append(finding)
    case .phase(let phase):
      outcome.phases.append(phase)
    case .progress(let counters):
      outcome.counters.append(counters)
    case .degraded(let unavailable):
      outcome.degradedNotices.append(unavailable)
    }
  }
  return outcome
}

func duplicatesSetFindings(in outcome: DuplicatesScanOutcome) -> [Finding] {
  outcome.findings.filter { finding in
    if case .duplicateSet = finding.category { return true }
    return false
  }
}

func duplicatesKeptPath(of finding: Finding) -> AbsolutePath? {
  if case .duplicateSet(let kept) = finding.category { return kept }
  return nil
}

/// A duplicate set reduced to its comparable shape: which paths group together
/// and which one is kept. Identifiers are excluded on purpose so determinism
/// can be asserted across two scans.
struct DuplicatesSetShape: Hashable {
  let paths: Set<AbsolutePath>
  let kept: AbsolutePath?
}

func duplicatesSetShapes(in outcome: DuplicatesScanOutcome) -> Set<DuplicatesSetShape> {
  Set(
    duplicatesSetFindings(in: outcome).map { finding in
      DuplicatesSetShape(paths: Set(finding.paths), kept: duplicatesKeptPath(of: finding))
    })
}

// MARK: - Plan inspection

func duplicatesOperationTarget(_ operation: Operation) -> AbsolutePath? {
  switch operation.kind {
  case .moveToTrash(let target):
    return target
  case .deletePermanently(let target):
    return target
  case .quarantine(let target):
    return target
  case .archive(let target, _):
    return target
  case .setLaunchItemEnabled, .runMaintenance:
    return nil
  }
}

func duplicatesPhaseRank(_ phase: ScanPhase) -> Int {
  switch phase {
  case .indeterminate: return 0
  case .determinate: return 1
  case .settling: return 2
  }
}
