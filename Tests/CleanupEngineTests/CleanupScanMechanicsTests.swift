import CleanupEngine
import Foundation
import GleamCore
import Testing

@Suite("Cleanup scan: session mechanics")
struct CleanupScanMechanicsTests {

  @Test("the engine declares the cleanup module")
  func engineDeclaresTheCleanupModule() {
    #expect(CleanupEngine().module == .cleanup)
  }

  @Test("the first phase is indeterminate and it arrives before any finding")
  func firstPhaseIsIndeterminateBeforeAnyFinding() async throws {
    let fileSystem = await JunkTree.seeded()
    let outcome = try await runCleanupScan(rules: JunkTree.catalog(), over: fileSystem)

    let firstPhaseIndex = outcome.orderedEvents.firstIndex {
      if case .phase = $0 { return true }
      return false
    }
    let firstFindingIndex = outcome.orderedEvents.firstIndex {
      if case .finding = $0 { return true }
      return false
    }
    let phaseIndex = try #require(firstPhaseIndex)
    let findingIndex = try #require(firstFindingIndex)
    #expect(phaseIndex < findingIndex)
    #expect(outcome.phases.first == .indeterminate)
  }

  @Test("phases only ever advance and the scan ends settling")
  func phasesAdvanceInOrderAndEndSettling() async throws {
    let fileSystem = await JunkTree.seeded()
    let outcome = try await runCleanupScan(rules: JunkTree.catalog(), over: fileSystem)

    let ordinals = outcome.phases.map(phaseOrdinal)
    #expect(zip(ordinals, ordinals.dropFirst()).allSatisfy { $0 <= $1 })
    #expect(outcome.phases.last == .settling)
  }

  @Test("counters only count up across the whole stream")
  func countersOnlyCountUp() async throws {
    let fileSystem = await JunkTree.seeded()
    let outcome = try await runCleanupScan(rules: JunkTree.catalog(), over: fileSystem)

    #expect(!outcome.counters.isEmpty)
    #expect(countersAreMonotonic(outcome.counters))
  }

  @Test("the final counters equal the sum of the yielded findings")
  func finalCountersEqualTheYieldedFindings() async throws {
    let fileSystem = await JunkTree.seeded()
    let outcome = try await runCleanupScan(rules: JunkTree.catalog(), over: fileSystem)

    let final = try #require(outcome.counters.last)
    #expect(final.bytesReclaimable == outcome.reclaimableByteTotal)
    #expect(final.findingCount == UInt32(outcome.findings.count))
    #expect(final.filesSeen >= UInt64(outcome.itemisedPaths.count))
  }

  @Test("cancelling the consuming task ends the stream promptly with only well formed findings")
  func cancellationEndsTheStreamPromptly() async throws {
    let fileSystem = await JunkTree.seeded(extraUserCacheFiles: 400)
    let context = makeScanContext(over: fileSystem, rules: try JunkTree.catalog())
    let engine = CleanupEngine()

    let (firstEventSeen, firstEventContinuation) = AsyncStream.makeStream(of: Void.self)
    let consumer = Task { () -> [Finding] in
      var received: [Finding] = []
      do {
        for try await event in engine.scan(context) {
          firstEventContinuation.yield(())
          if case .finding(let finding) = event {
            received.append(finding)
          }
        }
      } catch {}
      return received
    }

    var iterator = firstEventSeen.makeAsyncIterator()
    _ = await iterator.next()
    consumer.cancel()

    let endedPromptly = await completesPromptly {
      _ = await consumer.value
    }
    #expect(endedPromptly)

    for finding in await consumer.value {
      #expect(!finding.paths.isEmpty)
      #expect(!finding.explanation.isEmpty)
      #expect(finding.byteSize > 0)
    }
  }

  @Test("the whole scan completes against a value that conforms to the reading side only")
  func scanNeedsOnlyTheReadingSide() async throws {
    let fileSystem = await JunkTree.seeded()
    let readingOnly = ReadingOnlyFileSystem(backing: fileSystem)
    #expect(!((readingOnly as Any) is any FileSystemMutating))

    // ScanContext.fileSystem is typed `any FileSystemReading`, so this
    // construction compiling is the property under test: nothing in the
    // scan path can demand the mutating side.
    let context = ScanContext(
      sessionID: CleanupFixture.sessionID,
      fileSystem: readingOnly,
      rules: try JunkTree.catalog(),
      settings: makeSettings(),
      hasFullDiskAccess: true
    )
    let outcome = try await collectScan(CleanupEngine().scan(context))
    #expect(!outcome.findings.isEmpty)
  }
}
