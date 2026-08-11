import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// The safety property of C25, and the reason `quit` takes a name at all: "the
/// API takes the process identifier and name together and throws `nameMismatch`
/// if the identifier now belongs to a different process, so a recycled process
/// identifier can never kill the wrong process."
///
/// The hazard is not exotic. An operating system hands a process identifier back
/// out once the process holding it has gone, and a live view is a list of
/// numbers a person read a moment ago. Between the row being drawn and the
/// confirmation being answered, the number under `Xcode` can become somebody
/// else's compile, somebody else's export, somebody else's unsaved work. The
/// monitor holds a number; the person confirmed a name.
///
/// So the check is structural rather than an example. Three things are pinned:
/// the confirmation carries the name the row was shown under, the name is read
/// again from the machine at the moment of the kill rather than from the sample
/// the row came from, and any difference between the two aborts before anything
/// is signalled. The sweep at the end asserts the whole of it in one shape: a
/// signal is sent exactly when the two names are equal, and never otherwise.
@Suite("Quitting: a recycled process identifier kills nothing")
struct RecycledProcessIdentifierTests {

  // MARK: The check happens, and it happens at the kill

  @Test("the live name is read before anything is signalled")
  func theNameIsReadBeforeTheSignal() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)

    let outcome = await attemptQuit(
      monitor, QuitConfirmation(quitOf: ProcessFixture.xcode.processIdentifier, named: "Xcode"))

    #expect(outcome.didComplete)
    #expect(
      machine.interactions == [
        .nameRead(ProcessFixture.xcode.processIdentifier),
        .signalSent(
          Signal(processIdentifier: ProcessFixture.xcode.processIdentifier, force: false)),
      ],
      "the check is not a check if the signal has already gone")
  }

  @Test("a quit whose name still matches ends that process and nothing else")
  func aMatchingQuitEndsThatProcess() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)

    let outcome = await attemptQuit(
      monitor,
      QuitConfirmation(quitOf: ProcessFixture.chrome.processIdentifier, named: "Google Chrome"))

    #expect(outcome.didComplete)
    #expect(machine.isRunning(ProcessFixture.chrome.processIdentifier) == false)
    #expect(
      machine.runningIdentifiers
        == ProcessFixture.identifiers(ProcessFixture.machine)
        .filter { $0 != ProcessFixture.chrome.processIdentifier }.sorted(),
      "one confirmation ends one process")
  }

  // MARK: The identifier now belongs to somebody else

  @Test("an identifier that now belongs to a different process is refused, and nothing is killed")
  func aRecycledIdentifierIsRefused() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)
    machine.recycle(ProcessFixture.xcode.processIdentifier, as: ProcessFixture.recycledName)

    let outcome = await attemptQuit(
      monitor, QuitConfirmation(quitOf: ProcessFixture.xcode.processIdentifier, named: "Xcode"))

    #expect(
      outcome.refusal
        == .nameMismatch(expected: "Xcode", actual: ProcessFixture.recycledName))
    expectNothingWasKilled(machine)
  }

  @Test("the process that inherited the identifier is still running afterwards")
  func theInheritingProcessSurvives() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)
    machine.recycle(ProcessFixture.xcode.processIdentifier, as: ProcessFixture.recycledName)

    _ = await attemptQuit(
      monitor, QuitConfirmation(quitOf: ProcessFixture.xcode.processIdentifier, named: "Xcode"))

    #expect(machine.isRunning(ProcessFixture.xcode.processIdentifier))
    #expect(
      machine.current(ProcessFixture.xcode.processIdentifier)?.name
        == ProcessFixture.recycledName,
      "the work that inherited the number is exactly what a stale kill would have taken")
  }

  @Test("the mismatch names both what was confirmed and what is there now")
  func theMismatchNamesBothProcesses() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)
    machine.recycle(ProcessFixture.chrome.processIdentifier, as: "Final Cut Pro")

    let outcome = await attemptQuit(
      monitor,
      QuitConfirmation(quitOf: ProcessFixture.chrome.processIdentifier, named: "Google Chrome"))

    #expect(
      outcome.refusal == .nameMismatch(expected: "Google Chrome", actual: "Final Cut Pro"),
      "a person who confirmed one thing and nearly hit another is owed both names")
  }

  @Test("after a refusal nothing is retried and no signal follows")
  func nothingIsRetriedAfterARefusal() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)
    machine.recycle(ProcessFixture.xcode.processIdentifier, as: ProcessFixture.recycledName)

    _ = await attemptQuit(
      monitor, QuitConfirmation(quitOf: ProcessFixture.xcode.processIdentifier, named: "Xcode"))

    #expect(
      machine.interactions == [.nameRead(ProcessFixture.xcode.processIdentifier)],
      "one look, one refusal, no second attempt at a lower level")
  }

  // MARK: The identifier is gone entirely

  @Test("an identifier that no longer exists is refused with processNotFound")
  func aVacantIdentifierIsRefused() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)
    machine.exit(ProcessFixture.mail.processIdentifier)

    let outcome = await attemptQuit(
      monitor, QuitConfirmation(quitOf: ProcessFixture.mail.processIdentifier, named: "Mail"))

    #expect(outcome.refusal == .processNotFound(ProcessFixture.mail.processIdentifier))
    #expect(machine.sawNoSignal, "there is nothing at that number, so nothing is signalled")
  }

  @Test("an identifier no process has ever held is refused with processNotFound")
  func anIdentifierNobodyHoldsIsRefused() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)

    let outcome = await attemptQuit(
      monitor, QuitConfirmation(quitOf: ProcessFixture.vacantIdentifier, named: "Xcode"))

    #expect(outcome.refusal == .processNotFound(ProcessFixture.vacantIdentifier))
    expectNothingWasKilled(machine)
  }

  // MARK: The check is against the machine, not against the row

  /// The end to end shape of the hazard: a real sample produces the row, the
  /// operating system recycles the identifier underneath it, and the
  /// confirmation carries exactly what the row said. A monitor that trusts its
  /// own last snapshot passes every test above and fails this one.
  @Test("the check reads the machine now, not the sample the row was drawn from")
  func theCheckReadsTheMachineRatherThanTheSample() async throws {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine, cadence: ScriptedCadence(ticks: 1))
    let snapshots = await collectSnapshots(from: monitor)
    let row = try #require(snapshots.first?.first)
    #expect(row.name == "Xcode", "the heaviest row is the one a person reaches for")

    machine.recycle(row.processIdentifier, as: ProcessFixture.recycledName)
    let outcome = await attemptQuit(
      monitor, QuitConfirmation(quitOf: row.processIdentifier, named: row.name))

    #expect(
      outcome.refusal == .nameMismatch(expected: "Xcode", actual: ProcessFixture.recycledName))
    #expect(machine.sawNoSignal)
    #expect(machine.isRunning(row.processIdentifier))
  }

  @Test("two processes share a name: quitting one leaves the other running")
  func quittingByIdentifierNotByName() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)

    let outcome = await attemptQuit(
      monitor,
      QuitConfirmation(quitOf: ProcessFixture.secondNode.processIdentifier, named: "Node"))

    #expect(outcome.didComplete)
    #expect(machine.isRunning(ProcessFixture.secondNode.processIdentifier) == false)
    #expect(
      machine.isRunning(ProcessFixture.firstNode.processIdentifier),
      "the name confirms the target; the identifier is the target")
    #expect(
      machine.signals == [
        Signal(processIdentifier: ProcessFixture.secondNode.processIdentifier, force: false)
      ])
  }

  // MARK: Near misses

  @Test("a name that differs only in case is a different process and is not killed")
  func aCaseDifferenceIsAMismatch() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)

    let outcome = await attemptQuit(
      monitor, QuitConfirmation(quitOf: ProcessFixture.xcode.processIdentifier, named: "xcode"))

    #expect(outcome.refusal == .nameMismatch(expected: "xcode", actual: "Xcode"))
    expectNothingWasKilled(machine)
  }

  @Test("a name that differs by surrounding whitespace is not killed")
  func aWhitespaceDifferenceIsAMismatch() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)

    let outcome = await attemptQuit(
      monitor, QuitConfirmation(quitOf: ProcessFixture.xcode.processIdentifier, named: "Xcode "))

    #expect(outcome.refusal == .nameMismatch(expected: "Xcode ", actual: "Xcode"))
    expectNothingWasKilled(machine)
  }

  @Test("a name that is a prefix of the live name is not killed")
  func aPrefixIsAMismatch() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)

    let outcome = await attemptQuit(
      monitor,
      QuitConfirmation(quitOf: ProcessFixture.chrome.processIdentifier, named: "Google"))

    #expect(outcome.refusal == .nameMismatch(expected: "Google", actual: "Google Chrome"))
    expectNothingWasKilled(machine)
  }

  @Test("a confirmation that names nothing kills nothing")
  func anEmptyNameKillsNothing() async {
    let machine = FakeMachine()
    let monitor = makeProcessMonitor(over: machine)

    let outcome = await attemptQuit(
      monitor, QuitConfirmation(quitOf: ProcessFixture.xcode.processIdentifier, named: ""))

    #expect(
      outcome.refusal == .nameMismatch(expected: "", actual: "Xcode"),
      "a confirmation with no name in it was never shown to anybody")
    expectNothingWasKilled(machine)
  }

  // MARK: Failing closed

  @Test("a name the machine will not give up refuses the quit and signals nothing")
  func anUnreadableNameFailsClosed() async {
    let machine = FakeMachine(nameFailures: [ProcessFixture.xcode.processIdentifier])
    let monitor = makeProcessMonitor(over: machine)

    let outcome = await attemptQuit(
      monitor, QuitConfirmation(quitOf: ProcessFixture.xcode.processIdentifier, named: "Xcode"))

    #expect(outcome.refusal != nil, "a check that could not be made is not a check that passed")
    #expect(outcome.didComplete == false)
    expectNothingWasKilled(machine)
  }

  @Test("a signal the machine refuses surfaces as notPermitted and leaves the process running")
  func aRefusedSignalSurfacesAsNotPermitted() async throws {
    let machine = FakeMachine(signalRefusals: [ProcessFixture.xcode.processIdentifier])
    let monitor = makeProcessMonitor(over: machine)

    let outcome = await attemptQuit(
      monitor, QuitConfirmation(quitOf: ProcessFixture.xcode.processIdentifier, named: "Xcode"))

    let refusal = try #require(outcome.refusal)
    guard case .notPermitted(let sentence) = refusal else {
      Issue.record("a refusal by the machine is notPermitted, got \(refusal)")
      return
    }
    expectPlainSentence(sentence)
    #expect(sentence.contains("Xcode"), "the sentence names the process the person confirmed")
    #expect(machine.isRunning(ProcessFixture.xcode.processIdentifier))
  }

  // MARK: The whole matrix

  /// Every pairing of a confirmed name against a live name, for both kinds of
  /// confirmation. The property is one sentence with no exceptions in it: the
  /// machine is signalled exactly when the two names are equal, and the process
  /// survives every other pairing. Near misses are in the pool on purpose, since
  /// a comparison that trims, folds case or matches a prefix passes a hand
  /// written case and fails here.
  @Test("a signal is sent exactly when the confirmed name equals the live name")
  func theSignalFollowsTheNameCheckExactly() async {
    let names = [
      "Xcode", "xcode", "XCODE", " Xcode", "Xcode ", "Xcode Beta", "Mail", "Node",
    ]
    let identifier: Int32 = 501

    for liveName in names {
      for confirmedName in names {
        for isForce in [false, true] {
          let machine = FakeMachine(processes: [
            makeProcessSample(
              processIdentifier: identifier,
              name: liveName,
              memoryFootprintBytes: 1_048_576,
              processorLoadFraction: 0.1)
          ])
          let monitor = makeProcessMonitor(over: machine)
          let confirmation =
            isForce
            ? QuitConfirmation(forceQuitOf: identifier, named: confirmedName)
            : QuitConfirmation(quitOf: identifier, named: confirmedName)

          let outcome = await attemptQuit(monitor, confirmation)

          let shouldHaveSignalled = liveName == confirmedName
          #expect(
            outcome.didComplete == shouldHaveSignalled,
            "live \(liveName), confirmed \(confirmedName), force \(isForce)")
          #expect(
            machine.signals
              == (shouldHaveSignalled
                ? [Signal(processIdentifier: identifier, force: isForce)] : []),
            "live \(liveName), confirmed \(confirmedName), force \(isForce)")
          #expect(
            machine.isRunning(identifier) == (shouldHaveSignalled == false),
            "live \(liveName), confirmed \(confirmedName), force \(isForce)")
          if shouldHaveSignalled == false {
            #expect(
              outcome.refusal == .nameMismatch(expected: confirmedName, actual: liveName),
              "live \(liveName), confirmed \(confirmedName), force \(isForce)")
          }
        }
      }
    }
  }

  /// The same sweep against an identifier nobody holds. A monitor that treats a
  /// missing name as "no objection" would kill on every one of these, which is
  /// the failure mode an optional return type invites.
  @Test("a vacant identifier is refused whatever name is confirmed against it")
  func aVacantIdentifierIsRefusedForEveryName() async {
    let names = ["Xcode", "", "Mail", "Node", " "]

    for confirmedName in names {
      for isForce in [false, true] {
        let machine = FakeMachine(processes: [])
        let monitor = makeProcessMonitor(over: machine)
        let confirmation =
          isForce
          ? QuitConfirmation(forceQuitOf: ProcessFixture.vacantIdentifier, named: confirmedName)
          : QuitConfirmation(quitOf: ProcessFixture.vacantIdentifier, named: confirmedName)

        let outcome = await attemptQuit(monitor, confirmation)

        #expect(
          outcome.refusal == .processNotFound(ProcessFixture.vacantIdentifier),
          "confirmed \(confirmedName), force \(isForce)")
        #expect(machine.sawNoSignal, "confirmed \(confirmedName), force \(isForce)")
      }
    }
  }
}
