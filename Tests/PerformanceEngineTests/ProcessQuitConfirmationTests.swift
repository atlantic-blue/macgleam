import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// C25: "`quit` requires the caller to have shown a confirmation naming the
/// process; `force` is a second, separate confirmation", and DESIGN.md's safety
/// mechanisms: "explicit confirmation naming the process; force quit is a
/// second, separate confirmation".
///
/// Separate is the whole word. A boolean argument makes force an escalation of
/// the first confirmation: the same call, the same data, one flag flipped, and
/// a person who presses the only control twice arrives at a force quit having
/// answered one question. So the confirmation is a value with two constructors
/// and no way between them, and `quit` takes that value rather than a flag.
/// Three consequences are asserted below and one is asserted by the compiler:
/// a graceful signal is what a quit confirmation produces, a force signal is
/// what only a force confirmation produces, repeating the first confirmation
/// never escalates, and a force quit with no force confirmation cannot be
/// written down at all.
@Suite("Quitting: two confirmations, not one flag")
struct ProcessQuitConfirmationTests {

  // MARK: The confirmation itself

  @Test("a confirmation carries the identifier and the name it was shown against")
  func aConfirmationCarriesWhatWasShown() {
    let confirmation = QuitConfirmation(quitOf: 501, named: "Xcode")

    #expect(confirmation.processIdentifier == 501)
    #expect(confirmation.name == "Xcode")
    #expect(confirmation.kind == .quit)
  }

  @Test("quitting and force quitting the same process are different values")
  func theTwoConfirmationsAreDifferentValues() {
    let quit = QuitConfirmation(quitOf: 501, named: "Xcode")
    let force = QuitConfirmation(forceQuitOf: 501, named: "Xcode")

    #expect(force.kind == .forceQuit)
    #expect(
      quit != force,
      "if the two were one value with a flag, one press could stand for either answer")
  }

  @Test("there are two ways to confirm and no third")
  func thereAreExactlyTwoKinds() {
    #expect(
      QuitConfirmation.Kind.allCases.count == 2,
      "a third kind would be a door nobody has had to write a question for")
  }

  /// A confirmation is a fact about something a person did a moment ago. If one
  /// could be decoded from bytes, it could be stored, replayed, or built by
  /// anything that can write a file, and the force quit of an application would
  /// be one restore away from happening without anybody answering anything.
  @Test("a confirmation cannot be revived from stored bytes")
  func aConfirmationIsNotDecodable() {
    let decodable = QuitConfirmation.self as? any Decodable.Type

    #expect(decodable == nil, "a confirmation is minted where it is answered, never restored")
  }

  // MARK: What each confirmation sends

  @Test("a quit confirmation sends a graceful signal")
  func aQuitSendsAGracefulSignal() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)

    let outcome = await attemptQuit(
      monitor, QuitConfirmation(quitOf: ProcessFixture.xcode.processIdentifier, named: "Xcode"))

    #expect(outcome.didComplete)
    #expect(
      machine.signals == [
        Signal(processIdentifier: ProcessFixture.xcode.processIdentifier, force: false)
      ])
    #expect(machine.forceSignals.isEmpty, "asking is not forcing")
  }

  @Test("a force quit confirmation sends a force signal")
  func aForceQuitSendsAForceSignal() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)

    let outcome = await attemptQuit(
      monitor,
      QuitConfirmation(forceQuitOf: ProcessFixture.xcode.processIdentifier, named: "Xcode"))

    #expect(outcome.didComplete)
    #expect(
      machine.signals == [
        Signal(processIdentifier: ProcessFixture.xcode.processIdentifier, force: true)
      ])
  }

  // MARK: Pressing the same control again

  @Test("quitting the same process again never escalates to a force signal")
  func repeatingAQuitNeverEscalates() async {
    let machine = FakeMachine(
      ignoringGracefulSignals: [ProcessFixture.xcode.processIdentifier])
    let monitor = makeProcessMonitor(over: machine)
    let confirmation = QuitConfirmation(
      quitOf: ProcessFixture.xcode.processIdentifier, named: "Xcode")

    for _ in 0..<3 {
      let outcome = await attemptQuit(monitor, confirmation)
      #expect(outcome.didComplete)
    }

    #expect(machine.signals.count == 3)
    #expect(
      machine.forceSignals.isEmpty,
      "three answers to the same question are three of that answer, not a different one")
    #expect(
      machine.isRunning(ProcessFixture.xcode.processIdentifier),
      "the process that would not go is still there, which is what the second question is for")
  }

  /// The journey the contract describes, in one test. Ask, watch it not work,
  /// ask the other question, and the force signal goes out only after its own
  /// confirmation. Both halves check the name at the machine, so the second
  /// question is a second full check rather than a shortcut earned by the first.
  @Test("force quitting after a quit is a second confirmation with its own check")
  func forceQuittingIsASecondConfirmation() async {
    let machine = FakeMachine(
      ignoringGracefulSignals: [ProcessFixture.xcode.processIdentifier])
    let monitor = makeProcessMonitor(over: machine)
    let identifier = ProcessFixture.xcode.processIdentifier

    let asked = await attemptQuit(monitor, QuitConfirmation(quitOf: identifier, named: "Xcode"))
    let forced = await attemptQuit(
      monitor, QuitConfirmation(forceQuitOf: identifier, named: "Xcode"))

    #expect(asked.didComplete)
    #expect(forced.didComplete)
    #expect(
      machine.interactions == [
        .nameRead(identifier),
        .signalSent(Signal(processIdentifier: identifier, force: false)),
        .nameRead(identifier),
        .signalSent(Signal(processIdentifier: identifier, force: true)),
      ],
      "the second confirmation re reads the name; it does not inherit the first one's check")
    #expect(machine.isRunning(identifier) == false)
  }

  @Test("a force quit is refused on a name mismatch just as a quit is")
  func aForceQuitIsRefusedOnAMismatch() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)
    machine.recycle(ProcessFixture.xcode.processIdentifier, as: ProcessFixture.recycledName)

    let outcome = await attemptQuit(
      monitor,
      QuitConfirmation(forceQuitOf: ProcessFixture.xcode.processIdentifier, named: "Xcode"))

    #expect(
      outcome.refusal == .nameMismatch(expected: "Xcode", actual: ProcessFixture.recycledName),
      "force is a stronger signal, not a weaker check")
    expectNothingWasKilled(machine)
  }

  // MARK: No force without its own confirmation

  /// The property stated over the whole space rather than over the three
  /// journeys somebody thought of: whatever sequence of quit confirmations is
  /// presented, across every process on the machine and in any order, the
  /// signalling side never sees a force. There is no path through quitting that
  /// arrives at forcing.
  @Test("no sequence of quit confirmations ever produces a force signal")
  func noQuitSequenceEverForces() async {
    for selection in everySelection(of: ProcessFixture.machine) {
      let machine = FakeMachine(
        ignoringGracefulSignals: Set(ProcessFixture.identifiers(ProcessFixture.machine)))
      let monitor = makeProcessMonitor(over: machine)

      for sample in selection {
        for _ in 0..<2 {
          _ = await attemptQuit(
            monitor,
            QuitConfirmation(quitOf: sample.processIdentifier, named: sample.name))
        }
      }

      #expect(
        machine.forceSignals.isEmpty,
        "a force signal appeared with no force confirmation behind it")
      #expect(machine.signals.count == selection.count * 2)
      #expect(
        machine.running.count == ProcessFixture.machine.count,
        "these processes ignore the polite signal, so a quit that killed one forced it")
    }
  }

  @Test("a force quit of an identifier nobody holds signals nothing")
  func aForceQuitOfAVacantIdentifierSignalsNothing() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)

    let outcome = await attemptQuit(
      monitor, QuitConfirmation(forceQuitOf: ProcessFixture.vacantIdentifier, named: "Xcode"))

    #expect(outcome.refusal == .processNotFound(ProcessFixture.vacantIdentifier))
    expectNothingWasKilled(machine)
  }

  @Test("a confirmation for one process never reaches another")
  func aConfirmationReachesOnlyItsOwnProcess() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)

    _ = await attemptQuit(
      monitor,
      QuitConfirmation(forceQuitOf: ProcessFixture.mail.processIdentifier, named: "Mail"))

    #expect(
      machine.signals == [
        Signal(processIdentifier: ProcessFixture.mail.processIdentifier, force: true)
      ])
    #expect(
      machine.runningIdentifiers
        == ProcessFixture.identifiers(ProcessFixture.machine)
        .filter { $0 != ProcessFixture.mail.processIdentifier }.sorted())
  }
}
