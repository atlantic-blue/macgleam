import Foundation

/// The live memory and processor view, and confirmed process quit.
///
/// Guarantees:
/// - `samples` streams snapshots sorted heaviest first (by memory footprint)
///   at a steady cadence suitable for a live view; the stream never blocks
///   the main actor. Nothing is read before the first tick, one snapshot is
///   taken per tick, and the stream finishes when the cadence does, so a view
///   a person has closed leaves nothing sampling behind it.
/// - The ordering is total: heaviest first by memory footprint, and equal
///   footprints order by the lower process identifier. The tie rule is not a
///   tidy up. Two processes of equal footprint under a partial order may swap
///   places on every tick, and a row that moves while somebody is reaching
///   for it is a row nobody can aim a pointer at, which matters most for the
///   one control on it that ends a process. The order is therefore a function
///   of the snapshot alone: the same processes reported in any order produce
///   the same order on screen, whatever order the machine happened to answer
///   in. Sorting drops nothing, invents nothing and edits no field.
/// - Monitoring never quits, signals or otherwise affects any process. The
///   two boundaries are what make that structural rather than a promise the
///   sampling loop keeps: `ProcessListing` declares one method and it reads,
///   so the sampler holds a type with no way to end anything. A whole
///   sampling run sends no signal and does not even ask who holds an
///   identifier.
/// - A snapshot the machine refuses is skipped, and the view carries on. The
///   stream carries no error case, so a read that fails cannot be reported as
///   one; the only two answers left are to skip the sample or to emit the
///   previous list again, and emitting it again presents a stale list as
///   though it were current, which is the one answer a live view may not
///   give. The tick is still spent: the refused read was attempted, not
///   skipped over, and the next tick reads again.
/// - A machine with nothing running yields an empty snapshot, never no
///   snapshot. Showing nothing is an answer; showing the last list is not.
/// - The live view is not a scan (C23) and the monitor is not an engine: it
///   conforms to neither `GleamEngine` nor `PlanExecuting`, so nothing that
///   routes engines, Full Sweep included (C29), can route it. A
///   `ProcessSample` carries the five fields below and no path, so there is
///   nothing in the live view for a plan builder to turn into a removal,
///   which is C5's pathless rule holding here by the shape of the data rather
///   than by a rule somebody has to keep obeying.
/// - `quit` takes a `QuitConfirmation` and nothing else. The value is the
///   evidence that a person was shown a named process and answered; there is
///   no overload that takes a bare identifier, so a quit with no confirmation
///   behind it cannot be written down. A quit confirmation produces the
///   graceful signal and only that: no number of quit confirmations, in any
///   order, over any process, ever produces a force signal. A force quit is a
///   second, separate confirmation with its own value and its own full check,
///   never a shortcut earned by the first.
///
/// A recycled process identifier kills nothing. This is the safety property of
/// the slice, and it is why `quit` takes a name at all.
///
/// An operating system hands a process identifier back out once the process
/// holding it has gone, and a live view is a list of numbers a person read a
/// moment ago. Between the row being drawn and the confirmation being
/// answered, the number under `Xcode` can become somebody else's compile,
/// somebody else's export, somebody else's unsaved work. The monitor holds a
/// number; the person confirmed a name. So a monitor holding a stale
/// identifier can name one process on screen and signal a different one that
/// inherited the number.
///
/// - The confirmation carries the name the row was shown under, recorded at
///   the moment the question was asked.
/// - That name is read again from `ProcessTerminating` immediately before the
///   signal, and from nowhere else. Not from the sample the row was drawn
///   from, not from the monitor's last snapshot, not from a cache: a monitor
///   that trusts its own most recent listing satisfies every example and
///   fails the one case this exists for.
/// - Any difference aborts and signals nothing. `nameMismatch` carries both
///   names, because a person who confirmed one thing and nearly reached
///   another is owed both. There is no second attempt at a lower level: one
///   look, one refusal.
/// - Comparison is exact. Case, surrounding whitespace and prefixes are all
///   mismatches, and an empty confirmed name matches nothing, because a
///   confirmation with no name in it was never shown to anybody. A signal is
///   sent exactly when the confirmed name equals the live name, and the
///   process survives every other pairing.
/// - The check fails closed. A name the machine will not give up is
///   `notPermitted` and signals nothing: a check that could not be made is
///   not a check that passed. An identifier nothing holds is
///   `processNotFound` and signals nothing, whatever name was confirmed
///   against it; a missing name is never read as no objection.
/// - The name confirms the target; the identifier is the target. Two
///   processes sharing a name are two processes, and quitting one leaves the
///   other running.
///
/// What this does not guarantee. The window between the check and the signal
/// belongs to the operating system, and nothing can close it from here. The
/// name read and the terminate are two calls on one boundary and no
/// arrangement of them from this side makes them one: a process can end, and
/// its identifier be handed on, in between. The signalling boundary takes a
/// number, not a name, so there is nothing to hand it that would carry the
/// check with it. What is promised is that a mismatch which is visible at the
/// moment of the signal is refused and nothing is signalled. What is not
/// promised is that the race is impossible. Narrowing the window further
/// would be a change to what `ProcessTerminating` can express, not a stronger
/// reading of this clause.
///
/// Boundaries. The monitor reads nothing, signals nothing and keeps no time of
/// its own; it holds the three protocols below and is built from them. Reading
/// and signalling are two protocols rather than one with a terminate method,
/// so a sampler cannot signal by construction, and the name lookup sits with
/// the signal rather than with the listing so the check cannot be satisfied by
/// stale knowledge.
public protocol ProcessMonitoring: Sendable {
  func samples() -> AsyncStream<[ProcessSample]>
  func quit(_ confirmation: QuitConfirmation) async throws
}

/// What a person answered, and the only thing `quit` accepts. It carries the
/// identifier of the row, the name that row was shown under, and which of the
/// two questions was answered.
///
/// There is no path from one kind to the other. The memberwise initialiser is
/// not public, `kind` has no setter, and the two initialisers below are the
/// only ways to build one, so a force quit that nobody confirmed as a force
/// quit does not compile. That is a stronger statement than a rule about how
/// to call the API: it is the absence of any call that could express the
/// thing. A `force` flag would have made the two answers one value with a
/// switch on it, and one press could then stand for either.
///
/// Not `Decodable`, and deliberately. A confirmation is a fact about something
/// a person did a moment ago. One that could be revived from bytes could be
/// stored, replayed, or written by anything that can write a file, and the
/// force quit of an application would be one restore away from happening with
/// nobody having answered anything. A confirmation is minted where it is
/// answered, never restored.
public struct QuitConfirmation: Sendable, Equatable {
  /// Two ways to confirm and no third. A third case would be a door nobody
  /// has had to write a question for.
  public enum Kind: Sendable, Equatable, CaseIterable {
    case quit
    case forceQuit
  }

  public let processIdentifier: Int32
  /// The name the row was shown under when the question was asked. This is
  /// what the live name is checked against, exactly.
  public let name: String
  public let kind: Kind

  /// Not public, so the two questions below are the only ways in and neither
  /// can be turned into the other.
  private init(processIdentifier: Int32, name: String, kind: Kind) {
    self.processIdentifier = processIdentifier
    self.name = name
    self.kind = kind
  }

  /// Ask the process to end.
  public init(quitOf processIdentifier: Int32, named name: String) {
    self.init(processIdentifier: processIdentifier, name: name, kind: .quit)
  }

  /// Force the process to end. Its own question, answered on its own.
  public init(forceQuitOf processIdentifier: Int32, named name: String) {
    self.init(processIdentifier: processIdentifier, name: name, kind: .forceQuit)
  }
}

/// One row of the live view. Five fields and no path, so there is nothing here
/// a plan builder could turn into a removal.
public struct ProcessSample: Sendable, Equatable {
  public let processIdentifier: Int32
  public let name: String
  public let bundleID: String?
  public let memoryFootprintBytes: UInt64
  /// 0.0 to 1.0 per core aggregate.
  public let processorLoadFraction: Double

  public init(
    processIdentifier: Int32,
    name: String,
    bundleID: String?,
    memoryFootprintBytes: UInt64,
    processorLoadFraction: Double
  ) {
    self.processIdentifier = processIdentifier
    self.name = name
    self.bundleID = bundleID
    self.memoryFootprintBytes = memoryFootprintBytes
    self.processorLoadFraction = processorLoadFraction
  }
}

/// The reading side. Answers what is running and affects nothing. This is the
/// only boundary the sampling loop holds, which is what makes "monitoring
/// never signals" a property of a type rather than a habit.
public protocol ProcessListing: Sendable {
  func snapshot() async throws -> [ProcessSample]
}

/// The signalling side, and the only side that can say who holds an identifier
/// right now.
///
/// The name lookup lives here rather than on the listing side deliberately. A
/// name read anywhere else is already stale by the time the signal goes out.
/// Both calls landing on one boundary is also what makes the ordering
/// assertable: the check and the signal are two entries on one journal, so
/// "the name was read, then the process was signalled" is a fact about a
/// sequence rather than two counts that happen to both be one.
///
/// `name` answers nil when nothing holds the identifier and throws when the
/// machine will not say. The two are different answers and the contract keeps
/// them apart: nil is `processNotFound`, a throw is `notPermitted`, and
/// neither is a signal.
public protocol ProcessTerminating: Sendable {
  func name(ofProcessIdentifier processIdentifier: Int32) async throws -> String?
  func terminate(processIdentifier: Int32, force: Bool) async throws
}

/// When a sample is due: one tick, one snapshot. Production supplies a steady
/// cadence suitable for a live view; a test supplies the ticks it wants.
///
/// It is a boundary rather than a timer inside the monitor because a timer in
/// a test is a wall clock, and a suite that sleeps for a cadence reports on how
/// fast the machine running it happened to be that morning. Finishing the tick
/// stream is how the view says it has gone, and the sample stream finishes with
/// it.
public protocol ProcessSampleCadence: Sendable {
  func ticks() -> AsyncStream<Void>
}

public enum ProcessQuitError: Error, Sendable, Equatable {
  /// Nothing holds that identifier now. Signals nothing, whatever name was
  /// confirmed against it.
  case processNotFound(Int32)
  /// The identifier is held by something other than what was confirmed.
  /// Both names travel: the one the person answered and the one that is
  /// there now.
  case nameMismatch(expected: String, actual: String)
  /// The check could not be made, or the signal was refused by the machine.
  /// A plain sentence naming the process the person confirmed, and no path.
  case notPermitted(String)
}
