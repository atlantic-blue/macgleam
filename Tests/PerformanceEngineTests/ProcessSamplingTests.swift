import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// C25's live view: "`samples` streams snapshots sorted heaviest first (by
/// memory footprint) at a steady cadence suitable for a live view", and
/// "monitoring never quits, signals or otherwise affects any process".
///
/// Two things this suite refuses to do, both of them for the same reason. It
/// never reads the machine's own process table, so a run tells you about the
/// monitor rather than about whatever happened to be open; and it never sleeps
/// for a cadence, so a tick is something the test decided rather than something
/// the machine was fast enough to deliver. Both are only possible because the
/// listing and the cadence are boundaries the monitor is handed.
@Suite("Process sampling: the live view")
struct ProcessSamplingTests {

  // MARK: Cadence

  /// Both halves in one test on purpose. A monitor that reads nothing ever would
  /// satisfy the first assertion, so the same fixture is asked for one tick and
  /// has to answer.
  @Test("no sample is due until the first tick, so nothing is read on the way in")
  func nothingIsReadBeforeTheFirstTick() async {
    let idle = ScriptedProcessListing()
    let asked = ScriptedProcessListing()
    let machine = FakeMachine()

    let nothing = await collectSnapshots(
      from: makeProcessMonitor(
        listing: idle, terminating: machine.terminating, cadence: ScriptedCadence(ticks: 0)))
    let something = await collectSnapshots(
      from: makeProcessMonitor(
        listing: asked, terminating: machine.terminating, cadence: ScriptedCadence(ticks: 1)))

    #expect(nothing.isEmpty, "a view nobody has asked for a sample from reads nothing")
    #expect(idle.calls == 0)
    #expect(something.count == 1, "and one that has been asked answers")
    #expect(asked.calls == 1)
  }

  @Test("one snapshot arrives per tick")
  func oneSnapshotPerTick() async {
    let listing = ScriptedProcessListing()
    let machine = FakeMachine()

    let snapshots = await collectSnapshots(
      from: makeProcessMonitor(
        listing: listing, terminating: machine.terminating, cadence: ScriptedCadence(ticks: 4)))

    #expect(snapshots.count == 4)
    #expect(listing.calls == 4, "one read of the machine per sample due, and no speculative reads")
  }

  @Test("the stream finishes when the cadence does, so the view lets go")
  func theStreamFinishesWithTheCadence() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(
      listing: ScriptedProcessListing(), terminating: machine.terminating,
      cadence: ScriptedCadence(ticks: 2))

    let recorder = SnapshotRecorder()
    let finished = await completesPromptly {
      for await snapshot in monitor.samples() {
        await recorder.record(snapshot)
      }
    }
    let delivered = await recorder.count

    #expect(finished, "a stream that never ends keeps the machine awake after the view has gone")
    #expect(delivered == 2, "it finished after delivering the samples, not instead of them")
  }

  @Test("a snapshot arrives while the cadence is still open, so nothing waits for the end")
  func aSnapshotArrivesWhileTheCadenceIsStillOpen() async {
    let listing = ScriptedProcessListing()
    let machine = FakeMachine()
    let cadence = ManualCadence()
    let monitor = makeProcessMonitor(
      listing: listing, terminating: machine.terminating, cadence: cadence)
    let recorder = SnapshotRecorder()

    let arrived = await completesPromptly {
      var iterator = monitor.samples().makeAsyncIterator()
      cadence.tick()
      guard let first = await iterator.next() else { return }
      await recorder.record(first)
    }
    let received = await recorder.count
    cadence.finish()

    #expect(arrived, "the first snapshot must not wait on a cadence that has not finished")
    #expect(received == 1)
  }

  // MARK: Ordering

  @Test("the fixture machine arrives heaviest first")
  func theFixtureMachineArrivesHeaviestFirst() async throws {
    let machine = FakeMachine()

    let snapshots = await collectSnapshots(
      from: makeProcessMonitor(over: machine, cadence: ScriptedCadence(ticks: 1)))

    let snapshot = try #require(snapshots.first)
    #expect(snapshot == ProcessFixture.machineHeaviestFirst)
  }

  @Test("every snapshot of a run is sorted heaviest first")
  func everySnapshotIsSortedHeaviestFirst() async {
    let machine = FakeMachine()

    let snapshots = await collectSnapshots(
      from: makeProcessMonitor(over: machine, cadence: ScriptedCadence(ticks: 3)))

    #expect(snapshots.count == 3)
    for snapshot in snapshots {
      expectHeaviestFirst(snapshot, from: ProcessFixture.machine)
    }
  }

  /// The generated case the brief asks for. One hand written list can only be
  /// wrong in the ways somebody thought of; forty machines of forty processes,
  /// drawn from five footprint buckets, are mostly ties.
  @Test("every generated machine arrives heaviest first, ties and all")
  func everyGeneratedMachineArrivesHeaviestFirst() async {
    for seed in UInt64(1)...40 {
      let source = generatedProcessSamples(seed: seed, count: 40)
      let listing = ScriptedProcessListing(table: source)
      let machine = FakeMachine()

      let snapshots = await collectSnapshots(
        from: makeProcessMonitor(
          listing: listing, terminating: machine.terminating, cadence: ScriptedCadence(ticks: 1)))

      #expect(snapshots.count == 1, "seed \(seed)")
      for snapshot in snapshots {
        expectHeaviestFirst(snapshot, from: source)
      }
    }
  }

  /// Ties are the part of an ordering rule that decides whether a live view is
  /// readable. Two processes of equal footprint that swap places every second
  /// make a list nobody can aim at, so the rule is total: equal footprints order
  /// by the lower process identifier.
  @Test("two processes of equal footprint order by the lower process identifier")
  func equalFootprintsOrderByIdentifier() async throws {
    let machine = FakeMachine(processes: [ProcessFixture.secondNode, ProcessFixture.firstNode])

    let snapshots = await collectSnapshots(
      from: makeProcessMonitor(over: machine, cadence: ScriptedCadence(ticks: 1)))

    let snapshot = try #require(snapshots.first)
    #expect(
      snapshot.map(\.processIdentifier) == [
        ProcessFixture.firstNode.processIdentifier, ProcessFixture.secondNode.processIdentifier,
      ],
      "C25 as amended: equal footprints order by the lower identifier, so rows do not swap")
  }

  @Test("the same processes in any order produce the same order on screen")
  func theOrderDoesNotDependOnTheOrderTheMachineReported() async {
    let source = generatedProcessSamples(seed: 7, count: 24)
    let machine = FakeMachine()
    var orders: [[Int32]] = []

    for seed in UInt64(1)...8 {
      let listing = ScriptedProcessListing(table: deterministicallyShuffled(source, seed: seed))
      let snapshots = await collectSnapshots(
        from: makeProcessMonitor(
          listing: listing, terminating: machine.terminating, cadence: ScriptedCadence(ticks: 1)))
      orders.append(snapshots.first?.map(\.processIdentifier) ?? [])
    }

    #expect(orders.count == 8)
    #expect(
      orders.allSatisfy { $0.count == source.count },
      "every run showed the whole machine, so the comparison below is over real lists")
    #expect(
      Set(orders.map { $0.map(String.init).joined(separator: ",") }).count == 1,
      "the order the machine happens to report in must not reach the screen")
  }

  @Test("sorting drops nothing, invents nothing and edits no field")
  func sortingPreservesEveryField() async throws {
    let machine = FakeMachine()

    let snapshots = await collectSnapshots(
      from: makeProcessMonitor(over: machine, cadence: ScriptedCadence(ticks: 1)))

    let snapshot = try #require(snapshots.first)
    expectHeaviestFirst(snapshot, from: ProcessFixture.machine)
    let updater = try #require(
      snapshot.first { $0.processIdentifier == ProcessFixture.updater.processIdentifier })
    #expect(updater == ProcessFixture.updater, "a daemon with no bundle survives the sort intact")
    #expect(updater.bundleID == nil)
    let chrome = try #require(
      snapshot.first { $0.processIdentifier == ProcessFixture.chrome.processIdentifier })
    #expect(chrome == ProcessFixture.chrome)
  }

  // MARK: What the snapshot says

  @Test("a snapshot is the machine at that tick rather than the first one taken")
  func eachSnapshotIsTakenFresh() async {
    let firstTable = [ProcessFixture.xcode, ProcessFixture.mail]
    let secondTable = [ProcessFixture.chrome]
    let thirdTable = [ProcessFixture.chrome, ProcessFixture.mail, ProcessFixture.updater]
    let listing = ScriptedProcessListing(tables: [firstTable, secondTable, thirdTable])
    let machine = FakeMachine()

    let snapshots = await collectSnapshots(
      from: makeProcessMonitor(
        listing: listing, terminating: machine.terminating, cadence: ScriptedCadence(ticks: 3)))

    #expect(snapshots.count == 3)
    #expect(snapshots.first == [ProcessFixture.xcode, ProcessFixture.mail])
    #expect(snapshots.dropFirst().first == [ProcessFixture.chrome])
    #expect(
      snapshots.last == [ProcessFixture.chrome, ProcessFixture.mail, ProcessFixture.updater],
      "a live view that repeats its first answer is a screenshot")
  }

  @Test("a machine with nothing on it yields an empty snapshot rather than no snapshot")
  func anEmptyMachineYieldsAnEmptySnapshot() async {
    let listing = ScriptedProcessListing(table: [])
    let machine = FakeMachine()

    let snapshots = await collectSnapshots(
      from: makeProcessMonitor(
        listing: listing, terminating: machine.terminating, cadence: ScriptedCadence(ticks: 1)))

    #expect(snapshots == [[]], "showing nothing is an answer; showing the last list is a lie")
  }

  /// The stream carries no error case, so a read that fails cannot be reported
  /// as one. The two remaining answers are to skip the sample or to repeat the
  /// last one, and repeating presents a stale list as current, which is the one
  /// answer a live view may not give.
  @Test("a sample the machine refuses is skipped and the view carries on")
  func aFailedReadSkipsThatSampleAndKeepsGoing() async {
    let listing = ScriptedProcessListing(
      tables: [
        [ProcessFixture.xcode], [ProcessFixture.chrome], [ProcessFixture.mail],
      ],
      failingCalls: [1]
    )
    let machine = FakeMachine()

    let snapshots = await collectSnapshots(
      from: makeProcessMonitor(
        listing: listing, terminating: machine.terminating, cadence: ScriptedCadence(ticks: 3)))

    #expect(snapshots == [[ProcessFixture.xcode], [ProcessFixture.mail]])
    #expect(listing.calls == 3, "the failed tick was attempted, not skipped over")
  }

  // MARK: The boundary, and what monitoring may not do

  @Test("sampling reads the listing it was given and nothing else")
  func samplingReadsOnlyTheInjectedListing() async {
    let listing = ScriptedProcessListing()
    let machine = FakeMachine()

    _ = await collectSnapshots(
      from: makeProcessMonitor(
        listing: listing, terminating: machine.terminating, cadence: ScriptedCadence(ticks: 5)))

    #expect(listing.calls == 5)
    #expect(
      machine.snapshotCalls == 0,
      "the machine handed over for signalling is not a second way to list processes")
  }

  @Test("a whole sampling run signals nothing")
  func samplingSignalsNothing() async {
    let machine = FakeMachine()

    let snapshots = await collectSnapshots(
      from: makeProcessMonitor(over: machine, cadence: ScriptedCadence(ticks: 10)))

    #expect(snapshots.count == 10)
    #expect(
      machine.sawNoSignal,
      "C25: monitoring never quits, signals or otherwise affects any process")
    #expect(machine.nameReads.isEmpty, "monitoring does not even ask who holds an identifier")
    #expect(machine.running.count == ProcessFixture.machine.count)
  }

  @Test("cancelling the consumer ends the sampling loop, and later ticks read nothing")
  func cancellingTheConsumerEndsTheLoop() async {
    let listing = GatedProcessListing()
    let machine = FakeMachine()
    let cadence = ManualCadence()
    let monitor = makeProcessMonitor(
      listing: listing, terminating: machine.terminating, cadence: cadence)
    let stopped = Gate()
    let consumer = Task.detached {
      for await _ in monitor.samples() {}
      await stopped.open()
    }

    cadence.tick()
    let started = await completesPromptly { await listing.entered.wait() }
    #expect(started, "a tick has to reach the machine before cancelling it can mean anything")
    consumer.cancel()
    await listing.release.open()
    let ended = await completesPromptly { await stopped.wait() }
    cadence.tick(10)

    #expect(ended, "a cancelled view stops sampling instead of polling on")
    #expect(listing.calls == 1, "ten ticks after the loop ended read the machine no further times")
    cadence.finish()
  }
}
