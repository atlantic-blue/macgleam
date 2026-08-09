import Foundation
import GleamCore
import Testing

@Suite("ScanCounters")
struct ScanCountersTests {

  @Test("zero has every counter at zero")
  func zeroHasEveryCounterAtZero() {
    #expect(ScanCounters.zero.filesSeen == 0)
    #expect(ScanCounters.zero.bytesReclaimable == 0)
    #expect(ScanCounters.zero.itemCount == 0)
  }

  @Test("round trips losslessly at the extremes")
  func roundTripsLosslesslyAtExtremes() throws {
    try expectLosslessRoundTrip(ScanCounters.zero)
    try expectLosslessRoundTrip(
      makeScanCounters(
        filesSeen: UInt64.max,
        bytesReclaimable: UInt64.max,
        itemCount: UInt32.max
      )
    )
  }
}

@Suite("ScanSession counter monotonicity")
struct ScanSessionCounterMonotonicityTests {

  @Test("increasing counters apply to a running session")
  func increasingCountersApply() {
    var session = makeScanSession(counters: ScanCounters.zero)
    let increased = makeScanCounters(filesSeen: 10, bytesReclaimable: 2048, itemCount: 3)
    session.counters = increased
    #expect(session.counters == increased)
  }

  @Test("counters never decrease when a wholly lower update arrives")
  func countersNeverDecreaseOnLowerUpdate() {
    let before = makeScanCounters(filesSeen: 100, bytesReclaimable: 4096, itemCount: 5)
    var session = makeScanSession(counters: before)
    session.counters = makeScanCounters(filesSeen: 10, bytesReclaimable: 512, itemCount: 1)
    #expect(session.counters.filesSeen >= before.filesSeen)
    #expect(session.counters.bytesReclaimable >= before.bytesReclaimable)
    #expect(session.counters.itemCount >= before.itemCount)
  }

  @Test("no counter decreases under a mixed update")
  func noCounterDecreasesUnderMixedUpdate() {
    let before = makeScanCounters(filesSeen: 100, bytesReclaimable: 4096, itemCount: 5)
    var session = makeScanSession(counters: before)
    session.counters = makeScanCounters(filesSeen: 50, bytesReclaimable: 8192, itemCount: 2)
    #expect(session.counters.filesSeen >= before.filesSeen)
    #expect(session.counters.bytesReclaimable >= before.bytesReclaimable)
    #expect(session.counters.itemCount >= before.itemCount)
  }

  @Test("no counter decreases across a sequence of updates")
  func noCounterDecreasesAcrossSequence() {
    var session = makeScanSession(counters: ScanCounters.zero)
    let updates: [ScanCounters] = [
      makeScanCounters(filesSeen: 5, bytesReclaimable: 100, itemCount: 1),
      makeScanCounters(filesSeen: 3, bytesReclaimable: 900, itemCount: 0),
      makeScanCounters(filesSeen: 40, bytesReclaimable: 400, itemCount: 9),
      makeScanCounters(filesSeen: 40, bytesReclaimable: 400, itemCount: 9),
    ]
    for update in updates {
      let before = session.counters
      session.counters = update
      #expect(session.counters.filesSeen >= before.filesSeen)
      #expect(session.counters.bytesReclaimable >= before.bytesReclaimable)
      #expect(session.counters.itemCount >= before.itemCount)
    }
  }
}

@Suite("ScanSession lifecycle")
struct ScanSessionLifecycleTests {

  @Test("a running session has no finish date")
  func runningSessionHasNoFinishDate() {
    let session = makeScanSession(state: .running)
    #expect(session.state == .running)
    #expect(session.finishedAt == nil)
  }

  static let terminalStates: [ScanSession.State] = [
    .completed,
    .cancelled,
    .failed(reason: "The disk went away before the scan finished."),
  ]

  @Test(
    "moving state off running sets the finish date in the same mutation",
    arguments: terminalStates
  )
  func leavingRunningSetsFinishDate(terminal: ScanSession.State) {
    var session = makeScanSession(state: .running)
    session.state = terminal
    #expect(session.finishedAt != nil)
  }

  @Test("a failed state carries its reason through coding")
  func failedStateCarriesReasonThroughCoding() throws {
    let reason = "The disk went away before the scan finished."
    try expectLosslessRoundTrip(ScanSession.State.failed(reason: reason))
  }

  @Test("a running session round trips losslessly")
  func runningSessionRoundTrips() throws {
    try expectLosslessRoundTrip(makeScanSession(state: .running))
  }

  @Test("a finished session round trips losslessly")
  func finishedSessionRoundTrips() throws {
    let session = makeScanSession(
      finishedAt: Fixture.laterDate,
      state: .completed,
      counters: makeScanCounters()
    )
    try expectLosslessRoundTrip(session)
  }
}

@Suite("ScanPhase")
struct ScanPhaseTests {

  static let phases: [ScanPhase] = [
    .indeterminate,
    .determinate(estimatedTotalFiles: 0),
    .determinate(estimatedTotalFiles: UInt64.max),
    .settling,
  ]

  @Test("every phase round trips losslessly", arguments: phases)
  func everyPhaseRoundTrips(phase: ScanPhase) throws {
    try expectLosslessRoundTrip(phase)
  }
}

@Suite("GleamModule")
struct GleamModuleTests {

  @Test("exactly seven modules exist")
  func exactlySevenModulesExist() {
    #expect(GleamModule.allCases.count == 7)
  }

  @Test("every module round trips losslessly", arguments: GleamModule.allCases)
  func everyModuleRoundTrips(module: GleamModule) throws {
    try expectLosslessRoundTrip(module)
  }
}
