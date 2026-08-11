import Foundation
import GleamCore
import PerformanceEngine
import Testing
import os

/// Deterministic fixtures for the Performance module's live process view (C25).
///
/// Nothing here reads the machine's own process table, reads a wall clock,
/// sleeps for a cadence, or sends a signal to anything. Every process, byte
/// figure and identifier is fixed in this file, the cadence is driven by the
/// test rather than by a timer, and the only thing that can be quit is an entry
/// in a dictionary owned by `FakeMachine`.
///
/// Two boundaries, deliberately separate. `ProcessListing` reads and
/// `ProcessTerminating` reads a name and signals. They are two protocols rather
/// than one with a `kill` method, so a monitor built to sample cannot signal:
/// C25's "monitoring never quits, signals or otherwise affects any process" is
/// then a property of the type the sampler holds rather than a promise the
/// sampler keeps.
enum ProcessFixture {

  // MARK: The fixture machine

  /// The heaviest thing on the fixture machine.
  static let xcode = makeProcessSample(
    processIdentifier: 501,
    name: "Xcode",
    bundleID: "com.apple.dt.Xcode",
    memoryFootprintBytes: 8_589_934_592,
    processorLoadFraction: 0.62
  )

  static let chrome = makeProcessSample(
    processIdentifier: 733,
    name: "Google Chrome",
    bundleID: "com.google.Chrome",
    memoryFootprintBytes: 4_294_967_296,
    processorLoadFraction: 0.44
  )

  /// Two processes of one name, so a monitor that matches by name instead of by
  /// identifier kills the wrong one and the suite says so. Their memory
  /// footprints are equal, which is also the tie the ordering rule breaks.
  static let firstNode = makeProcessSample(
    processIdentifier: 1201,
    name: "Node",
    bundleID: nil,
    memoryFootprintBytes: 1_073_741_824,
    processorLoadFraction: 0.11
  )

  static let secondNode = makeProcessSample(
    processIdentifier: 1202,
    name: "Node",
    bundleID: nil,
    memoryFootprintBytes: 1_073_741_824,
    processorLoadFraction: 0.09
  )

  static let mail = makeProcessSample(
    processIdentifier: 902,
    name: "Mail",
    bundleID: "com.apple.mail",
    memoryFootprintBytes: 536_870_912,
    processorLoadFraction: 0.05
  )

  /// A daemon with no bundle, so the optional field is exercised by the
  /// ordinary path rather than only by a hostile one.
  static let updater = makeProcessSample(
    processIdentifier: 1104,
    name: "Example Updater",
    bundleID: nil,
    memoryFootprintBytes: 67_108_864,
    processorLoadFraction: 0.01
  )

  /// Deliberately not in memory order: the monitor sorts, the machine does not.
  static let machine: [ProcessSample] = [
    updater, mail, firstNode, secondNode, chrome, xcode,
  ]

  /// Heaviest first, ties broken by the lower identifier. The expected order of
  /// `machine`, written out by hand so the sort has something to be wrong
  /// against that was not produced by sorting.
  static let machineHeaviestFirst: [ProcessSample] = [
    xcode, chrome, firstNode, secondNode, mail, updater,
  ]

  /// An identifier no process on the fixture machine holds.
  static let vacantIdentifier: Int32 = 4242

  /// The name a recycled identifier ends up carrying in the dangerous case: the
  /// number survives, the process behind it is somebody else's work.
  static let recycledName = "Mail"

  static func identifiers(_ samples: [ProcessSample]) -> [Int32] {
    samples.map(\.processIdentifier)
  }
}

// MARK: - Building samples

func makeProcessSample(
  processIdentifier: Int32,
  name: String,
  bundleID: String? = nil,
  memoryFootprintBytes: UInt64,
  processorLoadFraction: Double
) -> ProcessSample {
  ProcessSample(
    processIdentifier: processIdentifier,
    name: name,
    bundleID: bundleID,
    memoryFootprintBytes: memoryFootprintBytes,
    processorLoadFraction: processorLoadFraction
  )
}

/// The same process under a different name, which is what the operating system
/// leaves behind when it hands a retired identifier to something new.
func processSample(_ sample: ProcessSample, renamed name: String) -> ProcessSample {
  makeProcessSample(
    processIdentifier: sample.processIdentifier,
    name: name,
    bundleID: sample.bundleID,
    memoryFootprintBytes: sample.memoryFootprintBytes,
    processorLoadFraction: sample.processorLoadFraction
  )
}

// MARK: - Generated sample sets

/// A fixed sequence of numbers. Generated cases need many shapes and no
/// surprises, so the sets a sweep runs over are produced by arithmetic seeded in
/// the test rather than by anything that could differ between two runs.
struct DeterministicNumbers {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
  }

  mutating func next(below bound: UInt64) -> UInt64 {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return (state >> 33) % bound
  }
}

/// A machine of `count` processes with distinct identifiers and heavily
/// repeated memory footprints, because ties are the part of an ordering rule
/// that a hand written list never covers.
func generatedProcessSamples(seed: UInt64, count: Int) -> [ProcessSample] {
  var numbers = DeterministicNumbers(seed: seed)
  let footprints: [UInt64] = [
    1_048_576, 33_554_432, 268_435_456, 1_073_741_824, 4_294_967_296,
  ]
  return (0..<count).map { index in
    let footprint = footprints[Int(numbers.next(below: UInt64(footprints.count)))]
    let load = Double(numbers.next(below: 101)) / 100.0
    return makeProcessSample(
      processIdentifier: Int32(100 + index),
      name: "Process \(index)",
      bundleID: index.isMultiple(of: 3) ? nil : "com.example.process\(index)",
      memoryFootprintBytes: footprint,
      processorLoadFraction: load
    )
  }
}

/// The same processes in a different order, so a sort can be asked to produce
/// one answer from many inputs.
func deterministicallyShuffled(_ samples: [ProcessSample], seed: UInt64) -> [ProcessSample] {
  var numbers = DeterministicNumbers(seed: seed)
  var remaining = samples
  var shuffled: [ProcessSample] = []
  while remaining.isEmpty == false {
    let index = Int(numbers.next(below: UInt64(remaining.count)))
    shuffled.append(remaining.remove(at: index))
  }
  return shuffled
}

// MARK: - Where the work happened

/// True when the caller is running on the main thread. `Thread.isMainThread` is
/// unavailable from an asynchronous context, and the question here is precisely
/// about asynchronous contexts, so this asks the same question of the platform
/// one layer down. Main actor work runs on the main thread and nothing else
/// does, so a boundary that records this reports where the monitor put its work.
func isOnTheMainThread() -> Bool {
  pthread_main_np() != 0
}

// MARK: - Gates

/// A one way gate two tasks can meet at. Every wait in this suite is a wait for
/// something another task has done, never a wait for a duration, so no test
/// depends on how fast the machine running it happens to be.
///
/// `wait` gives up when its task is cancelled, and that matters more than it
/// looks. These waits sit inside `completesPromptly`, which cancels its group
/// and then, like every task group, waits for its children before returning. A
/// wait that ignored cancellation would turn a test whose gate never opens from
/// a two second failure into a suite that never ends, which is the worst way for
/// a missing implementation to report itself.
actor Gate {
  private var isOpen = false
  private var waiting: [UUID: CheckedContinuation<Void, Never>] = [:]

  func open() {
    guard isOpen == false else { return }
    isOpen = true
    let resuming = waiting.values
    waiting = [:]
    for continuation in resuming {
      continuation.resume()
    }
  }

  func wait() async {
    if isOpen { return }
    let ticket = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if isOpen || Task.isCancelled {
          continuation.resume()
          return
        }
        waiting[ticket] = continuation
      }
    } onCancel: {
      Task { await self.abandon(ticket) }
    }
  }

  private func abandon(_ ticket: UUID) {
    waiting.removeValue(forKey: ticket)?.resume()
  }
}

// MARK: - The fixture machine

enum MachineFailure: Error, Sendable, Equatable {
  case theProcessListCouldNotBeRead
  case theNameCouldNotBeRead
  case theSignalWasRefused
}

struct Signal: Sendable, Equatable {
  let processIdentifier: Int32
  let force: Bool
}

/// One thing the monitor did to the machine, in the order it did it. The name
/// read and the signal are separate entries on one journal, which is how "the
/// name was checked at the moment of the kill" is asserted as an ordering rather
/// than as two independent counts.
enum MachineInteraction: Sendable, Equatable {
  case snapshotTaken
  case nameRead(Int32)
  case signalSent(Signal)
}

/// The machine's running processes, its journal of what the monitor did, and
/// the operating system's habit of handing a retired identifier to something
/// new. A terminated process leaves the table, so "nothing was killed" is a
/// statement about which processes are still running rather than only about
/// which calls were recorded.
final class FakeMachine: Sendable {
  private struct State {
    var processes: [Int32: ProcessSample]
    var interactions: [MachineInteraction] = []
    var callsOnTheMainThread = 0
    var snapshotCalls = 0
  }

  private let state: OSAllocatedUnfairLock<State>
  private let listingFailure: MachineFailure?
  private let nameFailures: Set<Int32>
  private let signalRefusals: Set<Int32>
  private let ignoringGracefulSignals: Set<Int32>

  /// `ignoringGracefulSignals` is the reason force quit exists at all: a process
  /// that will not go when asked politely. It receives the graceful signal and
  /// keeps running, so the second confirmation has something real to be for.
  init(
    processes: [ProcessSample] = ProcessFixture.machine,
    listingFailure: MachineFailure? = nil,
    nameFailures: Set<Int32> = [],
    signalRefusals: Set<Int32> = [],
    ignoringGracefulSignals: Set<Int32> = []
  ) {
    let table = Dictionary(uniqueKeysWithValues: processes.map { ($0.processIdentifier, $0) })
    self.state = OSAllocatedUnfairLock(initialState: State(processes: table))
    self.listingFailure = listingFailure
    self.nameFailures = nameFailures
    self.signalRefusals = signalRefusals
    self.ignoringGracefulSignals = ignoringGracefulSignals
  }

  // MARK: What is still running

  var running: [ProcessSample] {
    state.withLock { current in
      current.processes.values.sorted { $0.processIdentifier < $1.processIdentifier }
    }
  }

  var runningIdentifiers: [Int32] {
    running.map(\.processIdentifier)
  }

  func isRunning(_ processIdentifier: Int32) -> Bool {
    state.withLock { $0.processes[processIdentifier] != nil }
  }

  func current(_ processIdentifier: Int32) -> ProcessSample? {
    state.withLock { $0.processes[processIdentifier] }
  }

  // MARK: What the monitor did

  var interactions: [MachineInteraction] {
    state.withLock { $0.interactions }
  }

  var signals: [Signal] {
    interactions.compactMap { interaction in
      if case .signalSent(let signal) = interaction { return signal }
      return nil
    }
  }

  var forceSignals: [Signal] {
    signals.filter(\.force)
  }

  var sawNoSignal: Bool {
    signals.isEmpty
  }

  var nameReads: [Int32] {
    interactions.compactMap { interaction in
      if case .nameRead(let identifier) = interaction { return identifier }
      return nil
    }
  }

  var snapshotCalls: Int {
    state.withLock { $0.snapshotCalls }
  }

  var callsOnTheMainThread: Int {
    state.withLock { $0.callsOnTheMainThread }
  }

  // MARK: What the operating system did

  /// The identifier survives its process and is handed to a new one. This is
  /// the whole hazard in one line: a row on screen still says `Xcode` while the
  /// number under it now belongs to something else.
  func recycle(_ processIdentifier: Int32, as name: String) {
    state.withLock { current in
      guard let existing = current.processes[processIdentifier] else { return }
      current.processes[processIdentifier] = processSample(existing, renamed: name)
    }
  }

  /// The process ends of its own accord and nothing takes its number.
  func exit(_ processIdentifier: Int32) {
    state.withLock { $0.processes[processIdentifier] = nil }
  }

  // MARK: The boundaries

  var listing: MachineListing {
    MachineListing(machine: self)
  }

  var terminating: MachineTermination {
    MachineTermination(machine: self)
  }

  fileprivate func takeSnapshot() throws -> [ProcessSample] {
    recordThread()
    if let listingFailure {
      throw listingFailure
    }
    return state.withLock { current in
      current.snapshotCalls += 1
      current.interactions.append(.snapshotTaken)
      return current.processes.values.sorted { $0.processIdentifier < $1.processIdentifier }
    }
  }

  fileprivate func readName(of processIdentifier: Int32) throws -> String? {
    recordThread()
    state.withLock { $0.interactions.append(.nameRead(processIdentifier)) }
    if nameFailures.contains(processIdentifier) {
      throw MachineFailure.theNameCouldNotBeRead
    }
    return state.withLock { $0.processes[processIdentifier]?.name }
  }

  fileprivate func send(_ signal: Signal) throws {
    recordThread()
    state.withLock { $0.interactions.append(.signalSent(signal)) }
    if signalRefusals.contains(signal.processIdentifier) {
      throw MachineFailure.theSignalWasRefused
    }
    if signal.force == false && ignoringGracefulSignals.contains(signal.processIdentifier) {
      return
    }
    state.withLock { $0.processes[signal.processIdentifier] = nil }
  }

  private func recordThread() {
    guard isOnTheMainThread() else { return }
    state.withLock { $0.callsOnTheMainThread += 1 }
  }
}

/// Conforms to the reading side and nothing else. Handing this to the sampler is
/// the compile time proof that watching a process cannot end one.
struct MachineListing: ProcessListing {
  let machine: FakeMachine

  func snapshot() async throws -> [ProcessSample] {
    try machine.takeSnapshot()
  }
}

/// The side that can end a process, and the only side that can say who holds an
/// identifier right now. The name lookup lives here rather than on the reading
/// side deliberately: a name read anywhere else is already stale by the time the
/// signal goes out, which is the defect this whole boundary exists to prevent.
struct MachineTermination: ProcessTerminating {
  let machine: FakeMachine

  func name(ofProcessIdentifier processIdentifier: Int32) async throws -> String? {
    try machine.readName(of: processIdentifier)
  }

  func terminate(processIdentifier: Int32, force: Bool) async throws {
    try machine.send(Signal(processIdentifier: processIdentifier, force: force))
  }
}

// MARK: - Scripted listings

/// A listing that answers from a script rather than from a machine, so a
/// sampling test can change what the machine holds between one tick and the
/// next. It also records which thread it was called on, which is what the
/// isolation assertions read.
final class ScriptedProcessListing: ProcessListing, Sendable {
  private struct State {
    var tables: [[ProcessSample]]
    var calls = 0
    var callsOnTheMainThread = 0
  }

  private let state: OSAllocatedUnfairLock<State>
  private let failingCalls: Set<Int>

  /// `tables` is consumed one per call; once it runs out the last table is
  /// answered again, so a test that ticks more than it scripted gets a stable
  /// machine rather than a crash.
  init(tables: [[ProcessSample]], failingCalls: Set<Int> = []) {
    self.state = OSAllocatedUnfairLock(initialState: State(tables: tables))
    self.failingCalls = failingCalls
  }

  convenience init(table: [ProcessSample] = ProcessFixture.machine, failingCalls: Set<Int> = []) {
    self.init(tables: [table], failingCalls: failingCalls)
  }

  var calls: Int {
    state.withLock { $0.calls }
  }

  var callsOnTheMainThread: Int {
    state.withLock { $0.callsOnTheMainThread }
  }

  func snapshot() async throws -> [ProcessSample] {
    if isOnTheMainThread() {
      state.withLock { $0.callsOnTheMainThread += 1 }
    }
    let index = state.withLock { current -> Int in
      let index = current.calls
      current.calls += 1
      return index
    }
    if failingCalls.contains(index) {
      throw MachineFailure.theProcessListCouldNotBeRead
    }
    return state.withLock { current in
      guard current.tables.isEmpty == false else { return [] }
      return current.tables[min(index, current.tables.count - 1)]
    }
  }
}

/// A listing that stops inside a snapshot until the test lets it go. It is how
/// "a snapshot in flight" is expressed without a sleep: the test knows the
/// snapshot has started because the boundary said so, and knows it has not
/// finished because it has not been released.
final class GatedProcessListing: ProcessListing, Sendable {
  let entered = Gate()
  let release = Gate()
  private let table: [ProcessSample]
  private let callCount = OSAllocatedUnfairLock(initialState: 0)

  init(table: [ProcessSample] = ProcessFixture.machine) {
    self.table = table
  }

  var calls: Int {
    callCount.withLock { $0 }
  }

  func snapshot() async throws -> [ProcessSample] {
    callCount.withLock { $0 += 1 }
    await entered.open()
    await release.wait()
    return table
  }
}

/// A listing that does its reading on the main actor: the one implementation
/// C25 forbids, written down here so the test that discriminates has something
/// to be wrong against. Its only use is as a negative control. A sampler built
/// over this cannot answer a tick while the main actor is in a loop, because
/// the read is queued behind the loop.
final class MainActorProcessListing: ProcessListing, Sendable {
  private let callCount = OSAllocatedUnfairLock(initialState: 0)
  private let table: [ProcessSample]

  init(table: [ProcessSample] = ProcessFixture.machine) {
    self.table = table
  }

  var calls: Int {
    callCount.withLock { $0 }
  }

  /// The hop comes first and the call is counted after it, so the count moves
  /// when the main actor lets the read happen and at no other moment.
  func snapshot() async throws -> [ProcessSample] {
    let counter = callCount
    await MainActor.run { counter.withLock { $0 += 1 } }
    return table
  }
}

// MARK: - Occupying the main actor

/// How many turns of the loop the main actor is held for at most. It bounds a
/// deadlock rather than deciding a result: a sampler running off the main actor
/// answers a tick in a tiny fraction of this, and a sampler running on it
/// cannot answer within any budget at all, so raising or lowering the number
/// changes how long a failing run takes and nothing else. An iteration count
/// rather than a duration, so nothing in this suite reads a clock.
let mainActorOccupationBudget = 20_000_000

/// Holds the calling actor in synchronous work until `progressWasMade` reports
/// some, or until the budget runs out. Nothing in here suspends, so an actor
/// running this loop is running nothing else, which is the whole point: it is
/// "the main actor is busy" expressed as something a test can hold open and
/// then ask a question inside.
///
/// Call this only once the work being measured is already under way. A loop
/// entered before the other task has been scheduled measures which task the
/// cooperative pool happened to start first.
@discardableResult
func occupyTheMainActor(until progressWasMade: () -> Bool) -> Bool {
  var spins = 0
  while spins < mainActorOccupationBudget {
    if progressWasMade() { return true }
    spins += 1
  }
  return progressWasMade()
}

// MARK: - Cadence

/// The cadence the test drives by hand. C25 asks for a steady cadence suitable
/// for a live view; what makes it steady is a timer in production, and a timer
/// in a test is a wall clock, so the cadence is a boundary and every tick in
/// this suite is one the test decided to send.
final class ManualCadence: ProcessSampleCadence, Sendable {
  private let stream: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation

  init() {
    let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .unbounded)
    self.stream = stream
    self.continuation = continuation
  }

  func ticks() -> AsyncStream<Void> {
    stream
  }

  /// One sample is due.
  func tick(_ count: Int = 1) {
    for _ in 0..<count {
      continuation.yield(())
    }
  }

  /// The view has gone and no further sample is due.
  func finish() {
    continuation.finish()
  }
}

/// A fixed number of ticks and then the end, for the suites that want the whole
/// run collected in one line.
struct ScriptedCadence: ProcessSampleCadence {
  let count: Int

  init(ticks count: Int) {
    self.count = count
  }

  func ticks() -> AsyncStream<Void> {
    let count = count
    return AsyncStream { continuation in
      for _ in 0..<count {
        continuation.yield(())
      }
      continuation.finish()
    }
  }
}

// MARK: - The monitor under test

func makeProcessMonitor(
  listing: any ProcessListing,
  terminating: any ProcessTerminating,
  cadence: any ProcessSampleCadence = ScriptedCadence(ticks: 0)
) -> ProcessMonitor {
  ProcessMonitor(listing: listing, terminating: terminating, cadence: cadence)
}

func makeProcessMonitor(
  over machine: FakeMachine,
  cadence: any ProcessSampleCadence = ScriptedCadence(ticks: 0)
) -> ProcessMonitor {
  ProcessMonitor(
    listing: machine.listing,
    terminating: machine.terminating,
    cadence: cadence
  )
}

// MARK: - Collecting samples

/// Drains a monitor's stream to its end. Every sampling suite uses a cadence
/// that finishes, so this returns rather than waiting on a live view.
func collectSnapshots(from monitor: ProcessMonitor) async -> [[ProcessSample]] {
  var snapshots: [[ProcessSample]] = []
  for await snapshot in monitor.samples() {
    snapshots.append(snapshot)
  }
  return snapshots
}

/// Somewhere for a task that is not the test's own to put what it saw.
actor SnapshotRecorder {
  private(set) var snapshots: [[ProcessSample]] = []

  func record(_ snapshot: [ProcessSample]) {
    snapshots.append(snapshot)
  }

  var count: Int {
    snapshots.count
  }
}

// MARK: - Quitting

enum QuitOutcome: Sendable {
  case completed
  case refused(ProcessQuitError)
  case failedWithSomethingElse(String)

  var refusal: ProcessQuitError? {
    if case .refused(let error) = self { return error }
    return nil
  }

  var didComplete: Bool {
    if case .completed = self { return true }
    return false
  }
}

/// Runs a quit and reports what came back, so a test can assert on a refusal and
/// on the machine in the same breath. A throw that is not a `ProcessQuitError`
/// is reported as itself rather than folded into a refusal, because a monitor
/// leaking another module's error type is a defect and not a contract answer.
func attemptQuit(
  _ monitor: ProcessMonitor,
  _ confirmation: QuitConfirmation
) async -> QuitOutcome {
  do {
    try await monitor.quit(confirmation)
    return .completed
  } catch let error as ProcessQuitError {
    return .refused(error)
  } catch {
    return .failedWithSomethingElse(String(describing: type(of: error)))
  }
}

// MARK: - Assertions

/// C25's ordering, asserted as a property of the whole snapshot rather than by
/// comparing against a list somebody sorted by hand: heaviest first by memory
/// footprint, ties broken by the lower identifier, nothing dropped, nothing
/// invented, and every field of every sample carried through untouched.
func expectHeaviestFirst(
  _ emitted: [ProcessSample],
  from source: [ProcessSample],
  sourceLocation: SourceLocation = #_sourceLocation
) {
  let byIdentifier = { (samples: [ProcessSample]) in
    samples.sorted { $0.processIdentifier < $1.processIdentifier }
  }
  #expect(
    emitted.count == source.count,
    "the live view shows every process the machine reported, and no more",
    sourceLocation: sourceLocation)
  #expect(
    byIdentifier(emitted) == byIdentifier(source),
    "sorting reorders processes; it never drops one, invents one or edits a field",
    sourceLocation: sourceLocation)
  for (heavier, lighter) in zip(emitted, emitted.dropFirst()) {
    let ordered =
      heavier.memoryFootprintBytes > lighter.memoryFootprintBytes
      || (heavier.memoryFootprintBytes == lighter.memoryFootprintBytes
        && heavier.processIdentifier < lighter.processIdentifier)
    #expect(
      ordered,
      """
      C25: heaviest first by memory footprint, ties by the lower identifier. \
      \(heavier.name) at \(heavier.memoryFootprintBytes) bytes came before \
      \(lighter.name) at \(lighter.memoryFootprintBytes) bytes
      """,
      sourceLocation: sourceLocation)
  }
}

/// The machine as it was, whichever process the test was aiming at. Every
/// refusal in the quit suites ends with this: the point of a refusal is that
/// the machine is exactly as it was before anybody pressed anything.
func expectNothingWasKilled(
  _ machine: FakeMachine,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(
    machine.sawNoSignal,
    "nothing reached the signalling side, so no process was asked to end",
    sourceLocation: sourceLocation)
  #expect(
    machine.runningIdentifiers
      == ProcessFixture.identifiers(ProcessFixture.machine).sorted(),
    "every process the fixture machine started with is still running",
    sourceLocation: sourceLocation)
}
