import CryptoKit
import Darwin
import Foundation
import GleamCore

/// SplitMix64, seeded with a fixed constant so the tree has an identical
/// shape and identical contents on every run and every machine.
struct SplitMix64 {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var mixed = state
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
    return mixed ^ (mixed >> 31)
  }
}

enum PerformanceFixtureError: Error, CustomStringConvertible {
  case fileCreationFailed(path: String, code: Int32)
  case writeFailed(path: String)
  case builtTreeWrongSize(built: Int, intended: Int)
  case recountMismatch(counted: Int, intended: Int)

  var description: String {
    switch self {
    case .fileCreationFailed(let path, let code):
      return "Could not create fixture file at \(path) (errno \(code))."
    case .writeFailed(let path):
      return "Could not write fixture file at \(path)."
    case .builtTreeWrongSize(let built, let intended):
      return
        "The fixture generator built \(built) files where \(intended) were intended. "
        + "A partial fixture must never pass as a fast scan."
    case .recountMismatch(let counted, let intended):
      return
        "The on disk recount found \(counted) regular files where \(intended) were intended. "
        + "The tree on disk does not match what the generator reported building."
    }
  }
}

/// The path the atexit handler removes. A global because that handler cannot
/// capture.
nonisolated(unsafe) private var performanceFixtureCleanupPath: String?

/// A deterministic tree of typical home shape on the real disk: cache bundles
/// holding many small files, per application logs, a downloads folder, deep
/// application support chains, a derived data area no rule covers, and a few
/// large sparse capture files.
///
/// Sized in file count, not bytes. Contents are 1 to 64 bytes and the large
/// files are sparse, so generating 120,000 files costs seconds rather than
/// gigabytes, and generation time is measured and printed separately: it is
/// never part of a gate's budget.
struct PerformanceFixture: Sendable {

  /// 60,000 cache + 25,000 application support + 15,000 log
  /// + 10,000 download + 3 sparse capture files.
  static let coveredFileCount = 110_003

  /// 9,997 derived data files no rule in the fixture catalogue matches. They
  /// exist so the scan does real matching work over files it then discards,
  /// which is what a real scan spends most of its time doing, and so the
  /// entry count assertion can be exact rather than a lower bound.
  static let bystanderFileCount = 9_997

  static let intendedFileCount = coveredFileCount + bystanderFileCount

  static let sparseFileCount = 3
  static let sparseFileBytes: Int64 = 4 << 30

  let root: AbsolutePath
  let fileCount: Int

  static func build() throws -> PerformanceFixture {
    // The temporary directory sits behind a symbolic link (/var), so the root
    // is resolved up front and the rule patterns match canonical paths.
    let base = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
    let rootURL = base.appendingPathComponent(
      "macgleam-performance-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    registerCleanup(of: rootURL.path)
    sweepStaleFixtures(besides: rootURL, in: base)

    var generator = SplitMix64(seed: 0x4D61_6347_6C65_616D)
    var built = 0
    built += try buildCacheBundles(under: rootURL, generator: &generator)
    built += try buildApplicationSupportTrees(under: rootURL, generator: &generator)
    built += try buildLogs(under: rootURL, generator: &generator)
    built += try buildDownloads(under: rootURL, generator: &generator)
    built += try buildDerivedData(under: rootURL, generator: &generator)
    built += try buildSparseCaptures(under: rootURL)

    guard built == intendedFileCount else {
      throw PerformanceFixtureError.builtTreeWrongSize(built: built, intended: intendedFileCount)
    }
    let counted = try recountRegularFiles(under: rootURL)
    guard counted == intendedFileCount else {
      throw PerformanceFixtureError.recountMismatch(counted: counted, intended: intendedFileCount)
    }
    return PerformanceFixture(root: AbsolutePath(normalising: rootURL.path), fileCount: built)
  }

  // MARK: - Areas

  /// 200 cache bundles, three subdirectories each, 100 small files per
  /// subdirectory: 60,000 files. The shape a browser and a dozen chatty
  /// applications leave behind.
  private static func buildCacheBundles(
    under root: URL,
    generator: inout SplitMix64
  ) throws -> Int {
    var built = 0
    let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
    for bundle in 0..<200 {
      for subdirectory in ["data", "blobs", "tmp"] {
        let directory = caches.appendingPathComponent(
          "com.fixture.app\(bundle)/\(subdirectory)",
          isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for index in 0..<100 {
          try createSmallFile(
            at: directory.appendingPathComponent("chunk-\(index).bin").path,
            generator: &generator
          )
          built += 1
        }
      }
    }
    return built
  }

  /// 50 application suites, each an eight level deep chain carrying files at
  /// every level: 500 files per suite, 25,000 files. Depth is the point here,
  /// so a walker that degrades with nesting shows up.
  private static func buildApplicationSupportTrees(
    under root: URL,
    generator: inout SplitMix64
  ) throws -> Int {
    var built = 0
    let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
    for suite in 0..<50 {
      var directory = support.appendingPathComponent("com.fixture.suite\(suite)", isDirectory: true)
      for depth in 0..<8 {
        directory = directory.appendingPathComponent("level-\(depth)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filesAtThisDepth = depth == 7 ? 66 : 62
        for index in 0..<filesAtThisDepth {
          try createSmallFile(
            at: directory.appendingPathComponent("state-\(index).dat").path,
            generator: &generator
          )
          built += 1
        }
      }
    }
    return built
  }

  /// 150 log directories of 100 files: 15,000 files.
  private static func buildLogs(under root: URL, generator: inout SplitMix64) throws -> Int {
    var built = 0
    let logs = root.appendingPathComponent("Library/Logs", isDirectory: true)
    for application in 0..<150 {
      let directory = logs.appendingPathComponent(
        "com.fixture.logger\(application)",
        isDirectory: true
      )
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for index in 0..<100 {
        try createSmallFile(
          at: directory.appendingPathComponent("run-\(index).log").path,
          generator: &generator
        )
        built += 1
      }
    }
    return built
  }

  /// 100 download batches of 100 files: 10,000 files.
  private static func buildDownloads(under root: URL, generator: inout SplitMix64) throws -> Int {
    var built = 0
    let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
    for batch in 0..<100 {
      let directory = downloads.appendingPathComponent("batch-\(batch)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for index in 0..<100 {
        try createSmallFile(
          at: directory.appendingPathComponent("item-\(index).partial").path,
          generator: &generator
        )
        built += 1
      }
    }
    return built
  }

  /// 97 build directories of 103 files plus 6 loose products: 9,997 files
  /// that no fixture rule matches. The scan must walk and reject every one.
  private static func buildDerivedData(under root: URL, generator: inout SplitMix64) throws -> Int {
    var built = 0
    let derived = root.appendingPathComponent(
      "Library/Developer/Xcode/DerivedData",
      isDirectory: true
    )
    for project in 0..<97 {
      let directory = derived.appendingPathComponent(
        "Fixture-\(project)/Build/Intermediates",
        isDirectory: true
      )
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for index in 0..<103 {
        try createSmallFile(
          at: directory.appendingPathComponent("object-\(index).o").path,
          generator: &generator
        )
        built += 1
      }
    }
    for index in 0..<6 {
      try createSmallFile(
        at: derived.appendingPathComponent("manifest-\(index).plist").path,
        generator: &generator
      )
      built += 1
    }
    return built
  }

  /// Three 4 gigabyte sparse files: large logical sizes without the disk cost
  /// or the generation time of real bytes. Allocated bytes stay near zero,
  /// which is exactly what C5 asks a reclaimable estimate to report.
  private static func buildSparseCaptures(under root: URL) throws -> Int {
    let movies = root.appendingPathComponent("Movies", isDirectory: true)
    try FileManager.default.createDirectory(at: movies, withIntermediateDirectories: true)
    for index in 0..<sparseFileCount {
      let path = movies.appendingPathComponent("capture-\(index).mov").path
      let descriptor = open(path, O_CREAT | O_WRONLY, 0o644)
      guard descriptor >= 0 else {
        throw PerformanceFixtureError.fileCreationFailed(path: path, code: errno)
      }
      defer { close(descriptor) }
      guard ftruncate(descriptor, sparseFileBytes) == 0 else {
        throw PerformanceFixtureError.writeFailed(path: path)
      }
    }
    return sparseFileCount
  }

  // MARK: - Mechanics

  private static func createSmallFile(at path: String, generator: inout SplitMix64) throws {
    let descriptor = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
    guard descriptor >= 0 else {
      throw PerformanceFixtureError.fileCreationFailed(path: path, code: errno)
    }
    defer { close(descriptor) }
    let word = generator.next()
    let length = Int(word % 64) + 1
    var buffer = [UInt8](repeating: UInt8(truncatingIfNeeded: word), count: length)
    guard write(descriptor, &buffer, length) == length else {
      throw PerformanceFixtureError.writeFailed(path: path)
    }
  }

  /// An independent recount straight off the disk through Foundation, so the
  /// generator's own bookkeeping cannot vouch for itself and a tree that
  /// failed to materialise can never reach a gate.
  private static func recountRegularFiles(under root: URL) throws -> Int {
    guard
      let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey]
      )
    else {
      throw PerformanceFixtureError.recountMismatch(counted: 0, intended: intendedFileCount)
    }
    var counted = 0
    for case let url as URL in enumerator {
      if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
        counted += 1
      }
    }
    return counted
  }

  /// A run killed part way through leaves its tree behind: the exit handler
  /// never fires on a signal. So each run clears any fixture older than half
  /// an hour, which is litter by definition and cannot be a run in flight.
  private static func sweepStaleFixtures(besides current: URL, in base: URL) {
    let manager = FileManager.default
    let cutoff = Date().addingTimeInterval(-30 * 60)
    let contents = try? manager.contentsOfDirectory(
      at: base,
      includingPropertiesForKeys: [.contentModificationDateKey]
    )
    for url in contents ?? [] {
      guard url.lastPathComponent.hasPrefix("macgleam-performance-"),
        url.lastPathComponent != current.lastPathComponent,
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
          .contentModificationDate,
        modified < cutoff
      else { continue }
      try? manager.removeItem(at: url)
    }
  }

  private static func registerCleanup(of path: String) {
    performanceFixtureCleanupPath = path
    atexit {
      if let path = performanceFixtureCleanupPath {
        try? FileManager.default.removeItem(atPath: path)
      }
    }
  }
}

// MARK: - Rules over the fixture

/// The rules key derives from fixed bytes owned by this suite alone. The
/// production rules key never appears here.
private let performanceRulesPrivateKey = try! Curve25519.Signing.PrivateKey(
  rawRepresentation: Data(repeating: 0x51, count: 32)
)

extension PerformanceFixture {

  /// One rule per covered area, each pattern rooted inside the fixture. The
  /// derived data area is deliberately uncovered, so the union of finding
  /// entries is exactly `coveredFileCount` and a scan that walked a fraction
  /// of the tree cannot pass however quickly it finished.
  func catalog() throws -> RuleCatalog {
    let rules = [
      makePerformanceRule(
        identifier: "performance-caches",
        category: .userCache,
        pattern: "\(root.value)/Library/Caches/**",
        explanation: "Application caches the system rebuilds on demand."
      ),
      makePerformanceRule(
        identifier: "performance-application-support",
        category: .applicationCache,
        pattern: "\(root.value)/Library/Application Support/**",
        explanation: "Sandboxed application caches rebuilt on next launch."
      ),
      makePerformanceRule(
        identifier: "performance-logs",
        category: .log,
        pattern: "\(root.value)/Library/Logs/**",
        explanation: "Log files applications write for diagnostics."
      ),
      makePerformanceRule(
        identifier: "performance-downloads",
        category: .brokenDownload,
        pattern: "\(root.value)/Downloads/**",
        explanation: "Partial downloads that never completed."
      ),
      makePerformanceRule(
        identifier: "performance-captures",
        category: .temporaryFile,
        pattern: "\(root.value)/Movies/**",
        explanation: "Scratch captures left behind by a finished export."
      ),
    ]
    let unsigned = RuleCatalog(
      version: RuleCatalogVersion(value: 2),
      signature: Data(),
      cleanupRules: rules,
      adwareRules: [],
      denylist: Denylist(patterns: [])
    )
    let signature = try performanceRulesPrivateKey.signature(
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
}

private func makePerformanceRule(
  identifier: String,
  category: FindingCategory,
  pattern: String,
  explanation: String
) -> CleanupRule {
  CleanupRule(
    identifier: identifier,
    category: category,
    pathPatterns: [PathPattern(pattern: pattern)],
    risk: .safe,
    preselectable: true,
    explanation: explanation
  )
}

/// Built once and shared read only across the gates. Every scan in this suite
/// is read only, and regenerating 120,000 files per test would put generation
/// time into the suite's wall clock five times over.
enum SharedPerformanceFixture {

  static let built: Result<PerformanceFixture, Error> = Result {
    let clock = ContinuousClock()
    let start = clock.now
    let fixture = try PerformanceFixture.build()
    let elapsed = durationSeconds(start.duration(to: clock.now))
    print(
      "PERFORMANCE FIXTURE generated: \(fixture.fileCount) files "
        + "(\(PerformanceFixture.coveredFileCount) covered by rules, "
        + "\(PerformanceFixture.bystanderFileCount) bystanders) in "
        + String(format: "%.1f", elapsed)
        + " s at \(fixture.root.value). Generation is outside every measured budget."
    )
    return fixture
  }

  static func get() throws -> PerformanceFixture {
    try built.get()
  }
}

func durationSeconds(_ duration: Duration) -> Double {
  let components = duration.components
  return Double(components.seconds) + Double(components.attoseconds) / 1e18
}
