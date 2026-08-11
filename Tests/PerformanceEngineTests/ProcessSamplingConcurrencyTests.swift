import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// C25: "the stream never blocks the main actor". That sentence is a hope until
/// something can fail it, so this suite turns it into three properties that can.
///
/// Every test here consumes the view the way the app will, from the main actor,
/// because that is the only place the promise is worth anything. What the
/// boundaries record is where the work actually happened.
///
/// The load bearing one is `theSamplerRunsWhileTheMainActorIsBusy`. It occupies
/// the main actor with synchronous work and waits for the sampler to get
/// somewhere. A sampler isolated to the main actor cannot, because the main
/// actor is in the loop, so that test fails against exactly the implementation
/// the contract forbids and passes against one that samples off it. The test
/// under it holds that claim to its word.
@Suite("Process sampling: the main actor")
struct ProcessSamplingConcurrencyTests {

  @MainActor
  @Test("the machine is never read on the main actor, even when the view consumes on it")
  func theMachineIsNeverReadOnTheMainActor() async {
    let listing = ScriptedProcessListing()
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(
      listing: listing, terminating: machine.terminating, cadence: ScriptedCadence(ticks: 3))

    var snapshots: [[ProcessSample]] = []
    for await snapshot in monitor.samples() {
      snapshots.append(snapshot)
    }

    #expect(snapshots.count == 3)
    #expect(listing.calls == 3)
    #expect(
      listing.callsOnTheMainThread == 0,
      "reading the process table is the slow part, and it may not happen where the interface draws")
  }

  /// The one that discriminates, and the whole test is in the order of its
  /// lines. Two things are established before the main actor is taken over,
  /// rather than hoped for: the consumer task is running, and the sampling
  /// pipeline has already produced a snapshot off the main actor and delivered
  /// it. The first tick buys both, and the handshake the consumer opens from
  /// inside the stream is what the test waits on before it spins.
  ///
  /// Without that wait the loop can begin before the cooperative pool has
  /// scheduled the consumer at all, and then the answer is which task started
  /// first rather than where sampling runs. That is not a smaller version of
  /// the same question, it is a different question, and it is the one this test
  /// used to ask about one run in eight under the full parallel suite.
  ///
  /// So by the time the second tick goes out, the only thing left between it
  /// and a read of the machine is the sampler, which is already alive and
  /// suspended on the cadence. The budget bounds a deadlock; it does not decide
  /// the result. `aSamplerOnTheMainActorIsCaught` is what holds that to its
  /// word.
  @MainActor
  @Test("the sampler makes progress while the main actor is busy")
  func theSamplerRunsWhileTheMainActorIsBusy() async {
    let listing = ScriptedProcessListing()
    let machine = FakeMachine()
    let cadence = ManualCadence()
    let monitor = makeProcessMonitor(
      listing: listing, terminating: machine.terminating, cadence: cadence)
    let sampling = Gate()
    let consumer = Task.detached {
      for await _ in monitor.samples() {
        await sampling.open()
      }
    }

    cadence.tick()
    let isSampling = await completesPromptly { await sampling.wait() }
    let readsBeforeTheMainActorWasBusy = listing.calls
    cadence.tick()
    occupyTheMainActor(until: { listing.calls > readsBeforeTheMainActorWasBusy })
    let readsWhileTheMainActorWasBusy = listing.calls - readsBeforeTheMainActorWasBusy

    cadence.finish()
    consumer.cancel()

    #expect(
      isSampling,
      "a snapshot has to have reached the consumer before the main actor takes itself away")
    #expect(
      readsBeforeTheMainActorWasBusy >= 1,
      "the handshake means a sample was taken, so there is something for the second tick to repeat")
    #expect(
      readsWhileTheMainActorWasBusy >= 1,
      "the main actor held a loop and the sample never happened, so sampling runs on it")
  }

  /// The negative control, and the reason the test above can be believed. Same
  /// shape, same handshake, same budget, over a listing that does its reading on
  /// the main actor: precisely the implementation C25 forbids. It gets nowhere
  /// while the loop holds the main actor, so a harness weakened into something
  /// that passes whatever the sampler does fails here instead.
  ///
  /// The first tick still lands, because the main actor is free while the test
  /// waits on the handshake. It is the second one, sent into a busy main actor,
  /// that never reaches the machine.
  @MainActor
  @Test("a sampler that reads on the main actor gets nowhere while it is busy")
  func aSamplerOnTheMainActorIsCaught() async {
    let listing = MainActorProcessListing()
    let machine = FakeMachine()
    let cadence = ManualCadence()
    let monitor = makeProcessMonitor(
      listing: listing, terminating: machine.terminating, cadence: cadence)
    let sampling = Gate()
    let consumer = Task.detached {
      for await _ in monitor.samples() {
        await sampling.open()
      }
    }

    cadence.tick()
    let isSampling = await completesPromptly { await sampling.wait() }
    let readsBeforeTheMainActorWasBusy = listing.calls
    cadence.tick()
    occupyTheMainActor(until: { listing.calls > readsBeforeTheMainActorWasBusy })
    let readsWhileTheMainActorWasBusy = listing.calls - readsBeforeTheMainActorWasBusy

    cadence.finish()
    consumer.cancel()

    #expect(isSampling, "the first tick lands, because the main actor was free for it")
    #expect(readsBeforeTheMainActorWasBusy >= 1)
    #expect(
      readsWhileTheMainActorWasBusy == 0,
      """
      a read that hops to the main actor cannot happen while the main actor is in a loop. \
      If this passed, the test above would pass against a sampler that blocks the interface
      """)
  }

  @MainActor
  @Test("the main actor keeps running while a snapshot is outstanding")
  func theMainActorKeepsRunningWhileASnapshotIsOutstanding() async {
    let listing = GatedProcessListing()
    let machine = FakeMachine()
    let cadence = ManualCadence()
    let monitor = makeProcessMonitor(
      listing: listing, terminating: machine.terminating, cadence: cadence)
    let recorder = SnapshotRecorder()
    let stopped = Gate()
    let consumer = Task.detached {
      for await snapshot in monitor.samples() {
        await recorder.record(snapshot)
      }
      await stopped.open()
    }

    cadence.tick()
    let started = await completesPromptly { await listing.entered.wait() }
    #expect(started, "a tick has to reach the machine before anything else here means much")
    let deliveredWhileWaiting = await recorder.count
    await listing.release.open()
    cadence.finish()
    let ended = await completesPromptly { await stopped.wait() }
    let deliveredAfterwards = await recorder.count
    consumer.cancel()

    #expect(
      deliveredWhileWaiting == 0,
      "a snapshot that has not come back yet is not a snapshot, and nothing invents one")
    #expect(ended, "the sample completed once the machine answered")
    #expect(deliveredAfterwards == 1)
  }

  @MainActor
  @Test("snapshots reach a main actor consumer in the order they were taken")
  func snapshotsReachTheMainActorInOrder() async {
    let listing = ScriptedProcessListing(tables: [
      [ProcessFixture.xcode], [ProcessFixture.chrome], [ProcessFixture.mail],
    ])
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(
      listing: listing, terminating: machine.terminating, cadence: ScriptedCadence(ticks: 3))

    var names: [String] = []
    for await snapshot in monitor.samples() {
      names.append(snapshot.first?.name ?? "nothing")
    }

    #expect(names == ["Xcode", "Google Chrome", "Mail"], "the view is a sequence, not a set")
  }

  /// The same promise on the other half of the contract. A signal to a process
  /// that is not answering can take its time, and a person who has just
  /// confirmed a quit is watching the window it was sent from.
  @MainActor
  @Test("quitting from the main actor does not reach the machine on it")
  func quittingDoesNotReachTheMachineOnTheMainActor() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)

    let outcome = await attemptQuit(
      monitor,
      QuitConfirmation(quitOf: ProcessFixture.chrome.processIdentifier, named: "Google Chrome"))

    #expect(outcome.didComplete)
    #expect(machine.callsOnTheMainThread == 0)
  }
}
