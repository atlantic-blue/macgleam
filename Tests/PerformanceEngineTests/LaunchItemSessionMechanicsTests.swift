import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// C4 and C15's scan mechanics for the login item half, one representative
/// each. The maintenance half pins the same shape in its own suite; these
/// exist because a scan that also lists login items is a longer stream with a
/// second source in it, and the status scene and the progress choreography
/// observe this module exactly as they observe Cleanup. A module that skips a
/// phase, reports a counter backwards or keeps yielding after the person
/// walked away breaks the same animation for everybody.
@Suite("Performance login items: session mechanics")
struct LaunchItemSessionMechanicsTests {

  @Test("phases only ever advance and a scan that lists login items still ends settling")
  func phasesAdvanceAndEndSettling() async throws {
    let world = LaunchItemWorld()

    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)

    let ordinals = outcome.phases.map(phaseOrdinal)
    #expect(outcome.phases.first == .indeterminate)
    #expect(zip(ordinals, ordinals.dropFirst()).allSatisfy { $0 <= $1 })
    #expect(outcome.phases.last == .settling)
  }

  @Test("counters only count up while the login items are listed")
  func countersOnlyCountUp() async throws {
    let world = LaunchItemWorld()

    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)

    #expect(outcome.counters.isEmpty == false, "C15: a scan reports progress")
    #expect(countersAreMonotonic(outcome.counters))
    let final = try #require(outcome.counters.last)
    #expect(
      final.bytesReclaimable == 0,
      "Performance disables and maintains; it never promises space back")
  }

  @Test("every login item finding rides the session the scan was given")
  func findingsRideTheSession() async throws {
    let world = LaunchItemWorld()

    let outcome = try await runPerformanceScan(
      inventory: world.inventoryOnly, sessionID: PerformanceFixture.otherSessionID)

    #expect(outcome.launchItemFindings.isEmpty == false)
    #expect(
      outcome.launchItemFindings.allSatisfy { $0.sessionID == PerformanceFixture.otherSessionID })
  }

  @Test("a login item finding from another session is refused, naming the finding")
  func aFindingFromAnotherSessionIsRefused() throws {
    let context = makePlanContext(rules: try makeSignedPerformanceCatalog())
    let stray = makeLaunchItemFinding(
      item: LaunchItemFixture.updaterAgent,
      id: PerformanceFixture.uuid(0xA9),
      sessionID: PerformanceFixture.otherSessionID)

    #expect(throws: PlanningError.findingFromDifferentSession(stray.id)) {
      _ = try PerformanceEngine().plan(selection: [stray], context: context)
    }
  }

  @Test("cancelling the consuming task ends the stream promptly with only well formed findings")
  func cancellationEndsTheStreamPromptly() async throws {
    let world = LaunchItemWorld()
    let context = makeScanContext(
      over: await makeFixtureFileSystem(), rules: try makeSignedPerformanceCatalog())
    let engine = PerformanceEngine(launchItems: world.inventoryOnly)

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
      #expect(finding.paths.isEmpty, "a partial scan still yields no path to remove")
    }
    #expect(
      world.source.sawNoAttempt, "a cancelled scan changed \(world.source.attempts)")
  }
}
