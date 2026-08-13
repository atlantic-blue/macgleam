import CleanupEngine
import DiskMapEngine
import Foundation
import GleamCore
import Testing

// MARK: - Budgets
//
// These gates are the deliberate exception to the suite wide no wall clock
// rule: elapsed time and resident memory are the behaviour under test, and
// they run against the real disk through DiskFileSystem over a generated tree
// in a temporary directory the suite creates and removes.

/// C20 gives a full Cleanup scan of a typical 512 gigabyte system disk 60
/// seconds. Such a disk carries on the order of a million files; this fixture
/// is 120,000, roughly an eighth of that surface, so linear behaviour should
/// land near a tenth of the contract budget. 30 seconds is half the contract
/// figure over an eighth of the work: wide enough that a loaded continuous
/// integration runner never trips it, tight enough that a regression to
/// quadratic walking or per file rule rescanning sails past it by orders of
/// magnitude rather than percentages.
private let cleanupScanBudgetSeconds = 30.0

/// C22 gives a full volume map 30 seconds, and the same scaling argument
/// applies: half the contract budget over a fraction of the volume.
private let diskMapBudgetSeconds = 15.0

/// The DESIGN.md ceiling itself, not scaled down. Holding the full disk
/// figure on a smaller fixture is the least a streaming design must manage,
/// and the sample covers the whole test process, so the harness's own
/// allocations count against the engine, which only tightens the gate.
private let residentFootprintCeilingBytes: UInt64 = 500 * 1024 * 1024

/// Streaming means results arrive while the scan runs. The first matching
/// file in a 120,000 file tree is found almost immediately, so two seconds is
/// roomy for honest streaming.
private let firstEventBudgetSeconds = 2.0

/// The absolute bound above cannot fail an implementation that buffers
/// everything and then emits, if the whole scan happens to finish inside two
/// seconds on fast hardware. So the first event must also arrive inside this
/// fraction of the run it belongs to. Buffering puts the first event at
/// essentially 1.0; honest streaming sits near zero.
private let firstEventFractionOfRun = 0.5

// MARK: - Gates

/// Serialised so no gate's disk or processor load leaks into another gate's
/// measurement.
///
/// Every gate asserts the coverage it saw, so an empty or partial run fails
/// loudly rather than reporting a fast scan: the generator throws unless it
/// built exactly 120,000 files and an independent recount off the disk agrees,
/// the Cleanup gates assert the exact covered entry count and that the walk
/// saw the whole tree, and the map gates assert a node per file and a single
/// completion.
@Suite("Performance gates against the real disk", .serialized)
struct PerformanceGateTests {

  // MARK: Cleanup scan

  @Test("the full cleanup scan of the typical fixture completes inside its budget")
  func cleanupScanCompletesInsideItsBudget() async throws {
    let fixture = try SharedPerformanceFixture.get()
    let recorder = EnumerationRecorder()
    let context = try makeScopedScanContext(for: fixture, recorder: recorder)
    let clock = ContinuousClock()

    // The floor this budget sits on: what the same tree costs to walk through
    // DiskFileSystem with no engine above it. Printed, never asserted against,
    // so a future failure says straight away whether the disk got slower or
    // the engine did.
    let enumerationFloor = try await measureRawEnumeration(of: fixture.root)

    let start = clock.now
    var entryCount = 0
    var findingCount = 0
    var finalCounters: ScanCounters?
    for try await event in CleanupEngine().scan(context) {
      switch event {
      case .finding(let finding):
        findingCount += 1
        entryCount += finding.entries.count
      case .progress(let counters):
        finalCounters = counters
      case .phase, .degraded, .reading:
        break
      }
    }
    let elapsed = durationSeconds(start.duration(to: clock.now))
    let filesSeen = finalCounters?.filesSeen ?? 0

    print(
      "PERFORMANCE REFERENCE raw enumeration seconds: "
        + String(format: "%.2f", enumerationFloor.seconds)
        + " for \(enumerationFloor.records) records straight through DiskFileSystem ("
        + String(
          format: "%.0f", Double(enumerationFloor.records) / max(enumerationFloor.seconds, 0.001))
        + " records per second, no engine above it)"
    )
    print(
      "PERFORMANCE GATE cleanup scan seconds: " + String(format: "%.2f", elapsed)
        + " (budget \(cleanupScanBudgetSeconds)) over \(fixture.fileCount) fixture files, "
        + "\(filesSeen) files seen, \(findingCount) findings, \(entryCount) entries, "
        + String(format: "%.0f", Double(filesSeen) / max(elapsed, 0.001)) + " files per second"
    )

    // One enumeration of one root: proof the elapsed figure is a single pass
    // over the fixture rather than the same tree walked several times.
    #expect(enumerationFloor.records >= PerformanceFixture.intendedFileCount)
    #expect(recorder.requestedRoots.count == 1)
    #expect(entryCount == PerformanceFixture.coveredFileCount)
    #expect(filesSeen >= UInt64(PerformanceFixture.intendedFileCount))
    #expect(elapsed < cleanupScanBudgetSeconds)
  }

  // MARK: Progress cadence

  @Test("a scan reports progress on a cadence rather than once for every file")
  func aScanReportsProgressOnACadence() async throws {
    let fixture = try SharedPerformanceFixture.get()
    let context = try makeScopedScanContext(for: fixture, recorder: EnumerationRecorder())

    var progressEvents = 0
    var finalCounters: ScanCounters?
    for try await event in CleanupEngine().scan(context) {
      if case .progress(let counters) = event {
        progressEvents += 1
        finalCounters = counters
      }
    }
    let filesSeen = finalCounters?.filesSeen ?? 0
    let ceiling = Int(filesSeen / ProgressCadence.step) + ProgressCadence.allowedExtraReports

    print(
      "PERFORMANCE GATE progress events: \(progressEvents) (ceiling \(ceiling)) "
        + "over \(filesSeen) files seen"
    )

    #expect(filesSeen >= UInt64(PerformanceFixture.intendedFileCount))
    #expect(
      progressEvents <= ceiling,
      """
      every progress event crosses to the interface and redraws it, so one per \
      file costs more than the walk and takes the whole machine down with it
      """)
    #expect(
      filesSeen >= UInt64(PerformanceFixture.intendedFileCount),
      "and the figure somebody is left looking at is still the true one")
  }

  // MARK: Disk Map

  @Test("the full disk map of the typical fixture converges inside its budget")
  func diskMapConvergesInsideItsBudget() async throws {
    let fixture = try SharedPerformanceFixture.get()
    let context = try makeRealDiskScanContext(for: fixture)
    let clock = ContinuousClock()

    let start = clock.now
    var nodeCount = 0
    var revisionCount = 0
    var completions = 0
    var rootTotalBytes: UInt64 = 0
    for try await update in DiskMapEngine().map(volume: fixture.root, context: context) {
      switch update {
      case .node(let node):
        nodeCount += 1
        if node.path == fixture.root { rootTotalBytes = node.subtreeBytes }
      case .sizeRevision(let path, let subtreeBytes):
        revisionCount += 1
        if path == fixture.root { rootTotalBytes = subtreeBytes }
      case .completed:
        completions += 1
      }
    }
    let elapsed = durationSeconds(start.duration(to: clock.now))

    print(
      "PERFORMANCE GATE disk map seconds: " + String(format: "%.2f", elapsed)
        + " (budget \(diskMapBudgetSeconds)) over \(fixture.fileCount) fixture files, "
        + "\(nodeCount) nodes, \(revisionCount) size revisions, root total \(rootTotalBytes) bytes"
    )

    #expect(nodeCount >= PerformanceFixture.intendedFileCount)
    #expect(rootTotalBytes > 0)
    #expect(completions == 1)
    #expect(elapsed < diskMapBudgetSeconds)
  }

  // MARK: Memory

  @Test("peak resident footprint stays under the ceiling through the largest scans")
  func peakResidentFootprintStaysUnderTheCeiling() async throws {
    let fixture = try SharedPerformanceFixture.get()

    let recorder = EnumerationRecorder()
    let scanContext = try makeScopedScanContext(for: fixture, recorder: recorder)
    let scanSampler = FootprintSampler()
    await scanSampler.start(every: .milliseconds(50))
    // Counted, never collected: the figure has to reflect the engine's own
    // memory behaviour, not a test side accumulation of 110,003 findings.
    var entryCount = 0
    for try await event in CleanupEngine().scan(scanContext) {
      if case .finding(let finding) = event {
        entryCount += finding.entries.count
      }
    }
    let scanFootprint = await scanSampler.stop()

    let mapContext = try makeRealDiskScanContext(for: fixture)
    let mapSampler = FootprintSampler()
    await mapSampler.start(every: .milliseconds(50))
    var nodeCount = 0
    for try await update in DiskMapEngine().map(volume: fixture.root, context: mapContext) {
      if case .node = update { nodeCount += 1 }
    }
    let mapFootprint = await mapSampler.stop()

    print(
      "PERFORMANCE GATE peak resident megabytes, cleanup scan: "
        + String(format: "%.0f", FootprintMeasurement.megabytes(scanFootprint.peakBytes))
        + " (ceiling 500, baseline "
        + String(format: "%.0f", FootprintMeasurement.megabytes(scanFootprint.baselineBytes))
        + ", growth "
        + String(format: "%.0f", FootprintMeasurement.megabytes(scanFootprint.growthBytes))
        + ") over \(entryCount) entries"
    )
    print(
      "PERFORMANCE GATE peak resident megabytes, disk map: "
        + String(format: "%.0f", FootprintMeasurement.megabytes(mapFootprint.peakBytes))
        + " (ceiling 500, baseline "
        + String(format: "%.0f", FootprintMeasurement.megabytes(mapFootprint.baselineBytes))
        + ", growth "
        + String(format: "%.0f", FootprintMeasurement.megabytes(mapFootprint.growthBytes))
        + ") over \(nodeCount) nodes"
    )

    #expect(entryCount == PerformanceFixture.coveredFileCount)
    #expect(nodeCount >= PerformanceFixture.intendedFileCount)
    #expect(scanFootprint.peakBytes > 0)
    #expect(scanFootprint.peakBytes < residentFootprintCeilingBytes)
    #expect(mapFootprint.peakBytes < residentFootprintCeilingBytes)
  }

  // MARK: Streaming

  @Test("cleanup findings stream while the scan runs rather than arriving in one burst")
  func cleanupFindingsStreamWhileTheScanRuns() async throws {
    let fixture = try SharedPerformanceFixture.get()
    let recorder = EnumerationRecorder()
    let context = try makeScopedScanContext(for: fixture, recorder: recorder)
    let clock = ContinuousClock()

    let start = clock.now
    var firstFindingSeconds: Double?
    var entryCount = 0
    for try await event in CleanupEngine().scan(context) {
      if case .finding(let finding) = event {
        if firstFindingSeconds == nil {
          firstFindingSeconds = durationSeconds(start.duration(to: clock.now))
        }
        entryCount += finding.entries.count
      }
    }
    let totalSeconds = durationSeconds(start.duration(to: clock.now))
    let latency = try #require(
      firstFindingSeconds,
      "The scan completed without a single finding, so nothing streamed."
    )
    let fraction = latency / max(totalSeconds, 0.001)

    print(
      "PERFORMANCE GATE first cleanup finding seconds: " + String(format: "%.3f", latency)
        + " (budget \(firstEventBudgetSeconds)) after scan start, "
        + String(format: "%.1f", fraction * 100) + " per cent into a "
        + String(format: "%.2f", totalSeconds) + " s scan"
    )

    #expect(entryCount == PerformanceFixture.coveredFileCount)
    #expect(latency < firstEventBudgetSeconds)
    #expect(fraction < firstEventFractionOfRun)
  }

  @Test("map updates stream while the map builds rather than arriving in one burst")
  func mapUpdatesStreamWhileTheMapBuilds() async throws {
    let fixture = try SharedPerformanceFixture.get()
    let context = try makeRealDiskScanContext(for: fixture)
    let clock = ContinuousClock()

    let start = clock.now
    var firstNodeSeconds: Double?
    var nodeCount = 0
    for try await update in DiskMapEngine().map(volume: fixture.root, context: context) {
      if case .node = update {
        if firstNodeSeconds == nil {
          firstNodeSeconds = durationSeconds(start.duration(to: clock.now))
        }
        nodeCount += 1
      }
    }
    let totalSeconds = durationSeconds(start.duration(to: clock.now))
    let latency = try #require(
      firstNodeSeconds,
      "The map completed without a single node, so nothing streamed."
    )
    let fraction = latency / max(totalSeconds, 0.001)

    print(
      "PERFORMANCE GATE first map node seconds: " + String(format: "%.3f", latency)
        + " (budget \(firstEventBudgetSeconds)) after map start, "
        + String(format: "%.1f", fraction * 100) + " per cent into a "
        + String(format: "%.2f", totalSeconds) + " s map"
    )

    #expect(nodeCount >= PerformanceFixture.intendedFileCount)
    #expect(latency < firstEventBudgetSeconds)
    #expect(fraction < firstEventFractionOfRun)
  }
}

// MARK: - Contexts

/// A Cleanup scan takes no scope: the engine enumerates the whole volume from
/// its root, so the reading side is a real DiskFileSystem with that one root
/// redirected to the fixture (see FixtureScopedDiskFileSystem). Every record,
/// byte size and volume lookup still comes from the kernel.
private func makeScopedScanContext(
  for fixture: PerformanceFixture,
  recorder: EnumerationRecorder
) throws -> ScanContext {
  ScanContext(
    sessionID: performanceSessionID,
    fileSystem: FixtureScopedDiskFileSystem(fixtureRoot: fixture.root, recorder: recorder),
    rules: try fixture.catalog(),
    settings: performanceSettings,
    hasFullDiskAccess: true
  )
}

/// The map takes its volume as an argument, so it needs no redirect at all:
/// DiskFileSystem straight through, pointed at the fixture root.
private func makeRealDiskScanContext(for fixture: PerformanceFixture) throws -> ScanContext {
  ScanContext(
    sessionID: performanceSessionID,
    fileSystem: DiskFileSystem(),
    rules: try fixture.catalog(),
    settings: performanceSettings,
    hasFullDiskAccess: true
  )
}

/// Walks the fixture through DiskFileSystem alone, counting records. The
/// reference figure the Cleanup budget is judged against.
private func measureRawEnumeration(
  of root: AbsolutePath
) async throws -> (records: Int, seconds: Double) {
  var options = EnumerationOptions.default
  options.includesHiddenFiles = true
  options.descendsIntoPackages = true
  let clock = ContinuousClock()
  let start = clock.now
  var records = 0
  for try await event in DiskFileSystem().enumerate(root: root, options: options) {
    if case .record = event { records += 1 }
  }
  return (records, durationSeconds(start.duration(to: clock.now)))
}

private let performanceSessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!

private let performanceSettings = Settings(
  deletionMode: .trash,
  largeFileThresholdBytes: 1_073_741_824,
  oldFileThresholdDays: 180,
  menuBar: MenuBarPreferences(
    showsStorage: true,
    showsMemory: false,
    showsProcessorLoad: true
  ),
  motion: MotionPreferences(reduceMotionOverride: nil)
)
