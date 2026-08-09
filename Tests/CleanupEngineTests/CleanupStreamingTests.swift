import CleanupEngine
import Foundation
import GleamCore
import Testing

/// A tree built for the streaming clauses of C15: one rule with more matches
/// than `ScanStreamPolicy.maximumFindingEntries`, and a bystander count small
/// enough that a match is guaranteed inside the first checkpoint window
/// whatever order the file system enumerates in (C13 guarantees none).
enum StreamingTree {

  static let cacheDirectory = "/Users/test/Library/Caches/com.streaming.app/bulk"
  static let bystanderDirectory = "/Users/test/Documents/keep"

  /// C15's two numbers, written out rather than read off `ScanStreamPolicy`,
  /// so the structural expectations below are pinned to the contract instead
  /// of to whatever the constant currently says. `ScanStreamPolicyValueTests`
  /// in GleamCoreTests pins the constants themselves to these same literals,
  /// and is the one place either value is compared against the source.
  static let contractedEntryCap = 2_000
  static let contractedCheckpointFiles: UInt64 = 1_000

  /// Two and a half caps, so the category cannot fit in one finding and
  /// cannot fit in two either.
  static let matchesOverTheCap = 5_000

  /// 5,000 matches at 2,000 entries a finding need three findings at the
  /// absolute least, and take four if any batch flushes early.
  static let leastFindingsOverTheCap = 3

  /// Fewer than one checkpoint window of files no rule matches, so at least
  /// 200 of the first 1,000 files enumerated are matches however the walk
  /// orders them, and the first open batch holds between 200 and 1,000
  /// entries when the boundary arrives: a partial batch, well under the cap.
  static let checkpointMatches = 3_200
  static let checkpointBystanders = 800

  /// The bounds that follow from those two numbers and a 1,000 file
  /// checkpoint window. At the boundary the walk has seen 1,000 files, of
  /// which at most 800 can be bystanders, so the batch that flushes carries
  /// no fewer than 200 entries and no more than the 1,000 files seen.
  static let leastEntriesInTheFirstBatch = 200
  static let mostEntriesInTheFirstBatch = 1_000

  static func matchPath(_ index: Int) -> String {
    "\(cacheDirectory)/" + String(format: "file-%05d.bin", index)
  }

  static func bystanderPath(_ index: Int) -> String {
    "\(bystanderDirectory)/" + String(format: "note-%05d.txt", index)
  }

  static func matchingPaths(count: Int) -> Set<AbsolutePath> {
    Set((0..<count).map { CleanupFixture.path(matchPath($0)) })
  }

  static func seeded(matching: Int, bystanders: Int = 0) async -> InMemoryFileSystem {
    var files = (0..<matching).map { SeededFile(path: matchPath($0), length: 64) }
    files += (0..<bystanders).map { SeededFile(path: bystanderPath($0), length: 64) }
    return await makeSeededFileSystem(files)
  }

  static func catalog() throws -> RuleCatalog {
    try makeSignedCleanupCatalog(cleanupRules: [
      makeRule(
        identifier: "streaming-user-caches",
        category: .userCache,
        patterns: ["/Users/*/Library/Caches/com.streaming.app/**"],
        explanation: "Application caches the system rebuilds on demand."
      )
    ])
  }
}

/// The first progress counters the scan reported at or after its first
/// finding: the step C4 says carries that finding's entries.
func filesSeenWhenTheFirstFindingArrived(_ outcome: ScanOutcome) -> UInt64? {
  guard
    let firstFinding = outcome.orderedEvents.firstIndex(where: {
      if case .finding = $0 { return true }
      return false
    })
  else { return nil }
  for event in outcome.orderedEvents[firstFinding...] {
    if case .progress(let counters) = event { return counters.filesSeen }
  }
  return nil
}

@Suite("Cleanup scan: streaming shape")
struct CleanupStreamingTests {

  @Test("a category with more matches than the cap streams as several findings")
  func aCategoryOverTheCapStreamsAsSeveralFindings() async throws {
    let fileSystem = await StreamingTree.seeded(matching: StreamingTree.matchesOverTheCap)
    let outcome = try await runCleanupScan(rules: StreamingTree.catalog(), over: fileSystem)

    #expect(outcome.findings(in: .userCache).count > 1)
    #expect(outcome.findings(in: .userCache).count >= StreamingTree.leastFindingsOverTheCap)
  }

  @Test("no finding carries more than the entry cap")
  func noFindingExceedsTheEntryCap() async throws {
    let fileSystem = await StreamingTree.seeded(matching: StreamingTree.matchesOverTheCap)
    let outcome = try await runCleanupScan(rules: StreamingTree.catalog(), over: fileSystem)

    #expect(!outcome.findings.isEmpty)
    for finding in outcome.findings {
      #expect(!finding.entries.isEmpty)
      #expect(finding.entries.count <= ScanStreamPolicy.maximumFindingEntries)
      #expect(finding.entries.count <= StreamingTree.contractedEntryCap)
    }
  }

  @Test("the capped findings union to every match, with nothing repeated and nothing missing")
  func cappedFindingsUnionToTheWholeMatchSet() async throws {
    let fileSystem = await StreamingTree.seeded(matching: StreamingTree.matchesOverTheCap)
    let outcome = try await runCleanupScan(rules: StreamingTree.catalog(), over: fileSystem)

    let expected = StreamingTree.matchingPaths(count: StreamingTree.matchesOverTheCap)
    let cacheFindings = outcome.findings(in: .userCache)
    let union = cacheFindings.reduce(into: Set<AbsolutePath>()) { $0.formUnion($1.paths) }
    #expect(union == expected)

    let emitted = cacheFindings.reduce(0) { $0 + $1.entries.count }
    #expect(emitted == expected.count)
  }

  @Test("every capped finding's own entries are ordered by path")
  func cappedFindingEntriesAreOrderedByPath() async throws {
    let fileSystem = await StreamingTree.seeded(matching: StreamingTree.matchesOverTheCap)
    let outcome = try await runCleanupScan(rules: StreamingTree.catalog(), over: fileSystem)

    #expect(!outcome.findings.isEmpty)
    for finding in outcome.findings {
      #expect(finding.paths == finding.paths.sorted())
    }
  }

  @Test("the first finding arrives by the first checkpoint boundary, not at the end of the walk")
  func theFirstFindingArrivesByTheCheckpointBoundary() async throws {
    let fileSystem = await StreamingTree.seeded(
      matching: StreamingTree.checkpointMatches,
      bystanders: StreamingTree.checkpointBystanders
    )
    let outcome = try await runCleanupScan(rules: StreamingTree.catalog(), over: fileSystem)

    let atFirstFinding = try #require(filesSeenWhenTheFirstFindingArrived(outcome))
    #expect(atFirstFinding <= ScanStreamPolicy.firstFindingCheckpointFiles)
    #expect(atFirstFinding <= StreamingTree.contractedCheckpointFiles)

    let final = try #require(outcome.counters.last)
    #expect(final.filesSeen > atFirstFinding)
  }

  @Test("the first finding is a partial batch, flushed at the checkpoint rather than at the cap")
  func theFirstFindingIsAPartialBatch() async throws {
    let fileSystem = await StreamingTree.seeded(
      matching: StreamingTree.checkpointMatches,
      bystanders: StreamingTree.checkpointBystanders
    )
    let outcome = try await runCleanupScan(rules: StreamingTree.catalog(), over: fileSystem)

    let first = try #require(outcome.findings.first)
    #expect(first.entries.count < ScanStreamPolicy.maximumFindingEntries)
    #expect(first.entries.count >= StreamingTree.leastEntriesInTheFirstBatch)
    #expect(first.entries.count <= StreamingTree.mostEntriesInTheFirstBatch)
  }

  @Test("a finding is emitted before the scan's final phase event")
  func aFindingIsEmittedBeforeTheFinalPhaseEvent() async throws {
    let fileSystem = await StreamingTree.seeded(matching: StreamingTree.matchesOverTheCap)
    let outcome = try await runCleanupScan(rules: StreamingTree.catalog(), over: fileSystem)

    let firstFinding = try #require(
      outcome.orderedEvents.firstIndex {
        if case .finding = $0 { return true }
        return false
      })
    let finalPhase = try #require(
      outcome.orderedEvents.lastIndex {
        if case .phase = $0 { return true }
        return false
      })
    #expect(outcome.phases.last == .settling)
    #expect(firstFinding < finalPhase)
  }
}
