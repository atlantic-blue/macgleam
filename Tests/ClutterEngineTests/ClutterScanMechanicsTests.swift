import ClutterEngine
import Foundation
import GleamCore
import Testing

/// One representative test per C15 session mechanic. The full matrix lives
/// with the shared session machinery; these prove the clutter engine speaks
/// the same protocol.
@Suite("Clutter scan: session mechanics")
struct ClutterScanMechanicsTests {

  @Test("the engine declares the clutter module")
  func engineDeclaresTheClutterModule() {
    #expect(makeClutterEngine().module == .clutter)
  }

  @Test("phases only ever advance, starting indeterminate and ending settling")
  func phasesAdvanceInOrderAndEndSettling() async throws {
    let fileSystem = await ClutterTree.seeded()
    let outcome = try await runClutterScan(rules: ClutterTree.catalog(), over: fileSystem)

    #expect(outcome.phases.first == .indeterminate)
    let ordinals = outcome.phases.map(phaseOrdinal)
    #expect(zip(ordinals, ordinals.dropFirst()).allSatisfy { $0 <= $1 })
    #expect(outcome.phases.last == .settling)
  }

  @Test("counters only count up and the final counters equal the yielded findings")
  func countersCountUpAndReconcileWithFindings() async throws {
    let fileSystem = await ClutterTree.seeded()
    let outcome = try await runClutterScan(rules: ClutterTree.catalog(), over: fileSystem)

    #expect(!outcome.counters.isEmpty)
    #expect(countersAreMonotonic(outcome.counters))
    let final = try #require(outcome.counters.last)
    #expect(final.bytesReclaimable == outcome.reclaimableByteTotal)
    #expect(final.itemCount == UInt32(outcome.entryCount))
    #expect(final.filesSeen >= UInt64(outcome.itemisedPaths.count))
  }

  @Test("cancelling the consuming task ends the stream promptly with only well formed findings")
  func cancellationEndsTheStreamPromptly() async throws {
    let fileSystem = await ClutterTree.seeded(extraOldDocuments: 400)
    let context = makeScanContext(
      fileSystem: ReadingOnlyFileSystem(backing: fileSystem),
      rules: try ClutterTree.catalog()
    )
    let engine = makeClutterEngine()

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
}
