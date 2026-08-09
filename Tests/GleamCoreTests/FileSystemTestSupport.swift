import Foundation
import GleamCore
import Testing

/// Fixed values for the file system suites. The in memory implementation can
/// echo seeded dates exactly; the real disk sets its own timestamps, so the
/// shared conformance suite asserts only relations between dates, never
/// absolute values.
enum FileSystemFixture {

  static let createdDate = Fixture.referenceDate
  static let modifiedDate = Fixture.laterDate
  static let lastOpenedDate = Fixture.farFutureDate

  static let attributeName = "com.macgleam.test.marker"
  static let attributeValue = Fixture.attributeBytes

  /// Deterministic, seed dependent bytes. Written through ordinary file
  /// writes these are never transparently compressed, so allocated bytes on
  /// disk always cover the logical length.
  static func contents(_ seed: UInt8, length: Int = 32) -> Data {
    Data((0..<length).map { UInt8((Int($0) + Int(seed)) % 251) })
  }
}

/// One file in a fixture tree, addressed relative to the harness root.
struct FixtureFile: Sendable {
  var relativePath: String
  var contents: Data
  var isExecutable = false
  var extendedAttributes: [String: Data] = [:]
}

/// A deterministic tree of directories and files a harness materialises
/// before a test runs. Parent directories of every entry are implied.
struct FixtureTree: Sendable {
  var directories: [String] = []
  var files: [FixtureFile] = []

  /// Every directory in the tree, implied parents included, shallowest
  /// first so a harness can create them in order.
  var allDirectories: [String] {
    var seen = Set<String>()
    var ordered: [String] = []
    let explicit = directories + files.compactMap { Self.parent(of: $0.relativePath) }
    for path in explicit {
      for ancestor in Self.ancestorsIncludingSelf(of: path) where seen.insert(ancestor).inserted {
        ordered.append(ancestor)
      }
    }
    return ordered.sorted {
      $0.split(separator: "/").count < $1.split(separator: "/").count
    }
  }

  /// The absolute path of every entry, directories and files alike, when
  /// the tree is rooted at the given path. The root itself is not included.
  func allPaths(under root: AbsolutePath) -> Set<AbsolutePath> {
    var paths = Set(allDirectories.map { root.appending($0) })
    for file in files {
      paths.insert(root.appending(file.relativePath))
    }
    return paths
  }

  private static func parent(of relativePath: String) -> String? {
    let components = relativePath.split(separator: "/").dropLast()
    return components.isEmpty ? nil : components.joined(separator: "/")
  }

  private static func ancestorsIncludingSelf(of relativePath: String) -> [String] {
    let components = relativePath.split(separator: "/")
    guard !components.isEmpty else { return [] }
    return (1...components.count).map { components.prefix($0).joined(separator: "/") }
  }
}

extension AbsolutePath {
  /// Joins a relative fixture path onto this path.
  func appending(_ relativePath: String) -> AbsolutePath {
    AbsolutePath(normalising: value + "/" + relativePath)
  }
}

/// The (volumeID, fileID) pair the deduplication guarantee is keyed on.
struct FileIdentity: Hashable, Sendable {
  let volumeID: UInt64
  let fileID: UInt64

  init(volumeID: UInt64, fileID: UInt64) {
    self.volumeID = volumeID
    self.fileID = fileID
  }

  init(_ record: FileRecord) {
    self.init(volumeID: record.volumeID, fileID: record.fileID)
  }
}

/// Everything one enumeration produced, split by event kind.
struct EnumerationOutcome {
  var records: [FileRecord] = []
  var inaccessible: [(path: AbsolutePath, reason: String)] = []

  var recordPaths: Set<AbsolutePath> { Set(records.map(\.path)) }
  var identities: [FileIdentity] { records.map(FileIdentity.init) }

  func record(at path: AbsolutePath) -> FileRecord? {
    records.first { $0.path == path }
  }
}

/// Drains an enumeration stream to completion. Order is deliberately kept
/// out of every assertion because the contract guarantees none.
func collectEnumeration(
  _ stream: AsyncThrowingStream<EnumerationEvent, Error>
) async throws -> EnumerationOutcome {
  var outcome = EnumerationOutcome()
  for try await event in stream {
    switch event {
    case .record(let record):
      outcome.records.append(record)
    case .inaccessible(let path, let reason):
      outcome.inaccessible.append((path, reason))
    }
  }
  return outcome
}

/// True when the body finishes inside the allowance. Bounds "cancellation
/// stops promptly"; the contract states no latency figure, so two seconds is
/// the generous ceiling. No assertion reads the clock.
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

/// Copies the contract's default options and overrides only what a test
/// names, so tests never depend on unspecified default values.
func makeEnumerationOptions(
  includesHiddenFiles: Bool? = nil,
  descendsIntoPackages: Bool? = nil,
  skipSubtrees: [AbsolutePath]? = nil
) -> EnumerationOptions {
  var options = EnumerationOptions.default
  if let includesHiddenFiles {
    options.includesHiddenFiles = includesHiddenFiles
  }
  if let descendsIntoPackages {
    options.descendsIntoPackages = descendsIntoPackages
  }
  if let skipSubtrees {
    options.skipSubtrees = skipSubtrees
  }
  return options
}

// MARK: - Record factories for enumeration engine tests

func makeFileRecord(
  path: AbsolutePath,
  fileID: UInt64,
  volumeID: UInt64 = 1,
  allocatedBytes: UInt64 = 4096
) -> FileRecord {
  FileRecord(
    path: path,
    fileID: fileID,
    volumeID: volumeID,
    allocatedBytes: allocatedBytes,
    isDirectory: false,
    isExecutable: false,
    created: FileSystemFixture.createdDate,
    modified: FileSystemFixture.modifiedDate,
    lastOpened: nil
  )
}

func makeDirectoryRecord(
  path: AbsolutePath,
  fileID: UInt64,
  volumeID: UInt64 = 1
) -> FileRecord {
  FileRecord(
    path: path,
    fileID: fileID,
    volumeID: volumeID,
    allocatedBytes: 0,
    isDirectory: true,
    isExecutable: false,
    created: FileSystemFixture.createdDate,
    modified: FileSystemFixture.modifiedDate,
    lastOpened: nil
  )
}
