import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// C4 and C15's scan mechanics, one representative each. The Performance
/// scan reads no files, so these pin the shape of the stream rather than the
/// cost of the walk: the status scene and the progress choreography observe
/// this module exactly as they observe Cleanup, and a module that skips a
/// phase or reports a counter backwards breaks the animation for everybody.
@Suite("Performance scan: session mechanics")
struct MaintenanceSessionMechanicsTests {

  @Test("phases only ever advance and the scan ends settling")
  func phasesAdvanceAndEndSettling() async throws {
    let outcome = try await runPerformanceScan()

    let ordinals = outcome.phases.map(phaseOrdinal)
    #expect(outcome.phases.first == .indeterminate)
    #expect(zip(ordinals, ordinals.dropFirst()).allSatisfy { $0 <= $1 })
    #expect(outcome.phases.last == .settling)
  }

  @Test("counters only count up, and maintenance adds nothing reclaimable to them")
  func countersOnlyCountUp() async throws {
    let outcome = try await runPerformanceScan()

    #expect(outcome.counters.isEmpty == false, "C15: a scan reports progress")
    #expect(countersAreMonotonic(outcome.counters))
    let final = try #require(outcome.counters.last)
    #expect(
      final.bytesReclaimable == 0,
      "Performance disables and maintains; it never promises space back")
  }

  @Test("every finding rides the session the scan was given")
  func findingsRideTheSession() async throws {
    let outcome = try await runPerformanceScan(sessionID: PerformanceFixture.otherSessionID)

    #expect(outcome.findings.isEmpty == false)
    #expect(outcome.findings.allSatisfy { $0.sessionID == PerformanceFixture.otherSessionID })
  }

  @Test("cancelling the consuming task ends the stream promptly with only well formed findings")
  func cancellationEndsTheStreamPromptly() async throws {
    let context = makeScanContext(
      over: await makeFixtureFileSystem(), rules: try makeSignedPerformanceCatalog())
    let engine = PerformanceEngine()

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
      expectPlainSentence(finding.explanation)
      #expect(finding.sessionID == PerformanceFixture.sessionID)
    }
  }

  @Test("the whole scan completes against a value that conforms to the reading side only")
  func scanNeedsOnlyTheReadingSide() async throws {
    let readingOnly = ReadingOnlyFileSystem(backing: await makeFixtureFileSystem())
    #expect(!((readingOnly as Any) is any FileSystemMutating))

    // ScanContext.fileSystem is typed `any FileSystemReading`, so this
    // construction compiling is the property under test: nothing in the scan
    // path can demand the mutating side.
    let context = ScanContext(
      sessionID: PerformanceFixture.sessionID,
      fileSystem: readingOnly,
      rules: try makeSignedPerformanceCatalog(),
      settings: makePerformanceSettings(),
      hasFullDiskAccess: true
    )
    let outcome = try await collectScan(PerformanceEngine().scan(context))

    #expect(outcome.maintenanceFindings.isEmpty == false)
  }
}
