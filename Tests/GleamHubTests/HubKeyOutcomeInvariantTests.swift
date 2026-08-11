import Foundation
import GleamHub
import Testing

/// The shell used to report every key press as handled while acting on none of
/// them, so return and escape were swallowed: no action, and no beep either.
/// These are the tests for that property rather than for the happy paths. They
/// run over the whole matrix so a key added later cannot claim a press and then
/// do nothing with it.
@Suite("A handled press did something")
struct HubKeyOutcomeInvariantTests {

  @Test(
    "a press is handled if and only if it moved the rail or carried an intent the pane can run",
    arguments: everyKeyScenario
  )
  func aPressIsHandledIfAndOnlyIfItMovedTheRailOrCarriedARunnableIntent(scenario: KeyScenario) {
    let state = scenario.state
    let outcome = HubKeyResolver.outcome(state, applying: scenario.key, pane: scenario.capabilities)
    let moved = outcome.nextState(from: state) != state
    let ranSomething = outcome.intent.map(scenario.capabilities.canRun) ?? false
    #expect(outcome.isHandled == (moved || ranSomething))
  }

  @Test(
    "nothing is handled without either a move or a runnable intent", arguments: everyKeyScenario)
  func nothingIsHandledWithoutEitherAMoveOrARunnableIntent(scenario: KeyScenario) {
    let state = scenario.state
    let outcome = HubKeyResolver.outcome(state, applying: scenario.key, pane: scenario.capabilities)
    guard outcome.isHandled else { return }
    let moved = outcome.nextState(from: state) != state
    let ranSomething = outcome.intent.map(scenario.capabilities.canRun) ?? false
    #expect(moved || ranSomething)
  }

  @Test("a moved outcome really moved the selection", arguments: everyKeyScenario)
  func aMovedOutcomeReallyMovedTheSelection(scenario: KeyScenario) {
    let state = scenario.state
    let outcome = HubKeyResolver.outcome(state, applying: scenario.key, pane: scenario.capabilities)
    guard case .moved(let next) = outcome else { return }
    #expect(next.selection != state.selection)
    #expect(railTopToBottom.contains(next.selection))
  }

  @Test("an acted outcome carries an intent the pane can run", arguments: everyKeyScenario)
  func anActedOutcomeCarriesAnIntentThePaneCanRun(scenario: KeyScenario) {
    let outcome = HubKeyResolver.outcome(
      scenario.state, applying: scenario.key, pane: scenario.capabilities)
    guard case .acted(let intent) = outcome else { return }
    #expect(scenario.capabilities.canRun(intent))
  }

  @Test("a pane that can do nothing at all never has a press claimed for it")
  func aPaneThatCanDoNothingAtAllNeverHasAPressClaimedForIt() {
    let deadPane = HubPaneCapabilities(hasPrimaryAction: false, hasDismissal: false)
    for destination in railTopToBottom {
      let state = makeNavigationState(selection: destination)
      for key in [HubKeyEvent.return, .escape, .arrowLeft, .arrowRight] {
        let outcome = HubKeyResolver.outcome(state, applying: key, pane: deadPane)
        #expect(outcome == .ignored)
      }
    }
  }

  @Test("an ignored press changes nothing and asks for nothing", arguments: everyKeyScenario)
  func anIgnoredPressChangesNothingAndAsksForNothing(scenario: KeyScenario) {
    let state = scenario.state
    let outcome = HubKeyResolver.outcome(state, applying: scenario.key, pane: scenario.capabilities)
    guard outcome == .ignored else { return }
    #expect(outcome.isHandled == false)
    #expect(outcome.intent == nil)
    #expect(outcome.nextState(from: state) == state)
  }

  @Test(
    "nextState returns the moved state for a move and the input otherwise",
    arguments: everyKeyScenario)
  func nextStateReturnsTheMovedStateForAMoveAndTheInputOtherwise(scenario: KeyScenario) {
    let state = scenario.state
    let outcome = HubKeyResolver.outcome(state, applying: scenario.key, pane: scenario.capabilities)
    switch outcome {
    case .moved(let next):
      #expect(outcome.nextState(from: state) == next)
      #expect(outcome.nextState(from: state) != state)
    case .acted, .ignored:
      #expect(outcome.nextState(from: state) == state)
    }
  }

  @Test("nextState carries an unrelated state through untouched", arguments: everyKeyScenario)
  func nextStateCarriesAnUnrelatedStateThroughUntouched(scenario: KeyScenario) {
    let outcome = HubKeyResolver.outcome(
      scenario.state, applying: scenario.key, pane: scenario.capabilities)
    guard case .acted = outcome else { return }
    let elsewhere = makeNavigationState(selection: .settings, slots: makeFullSlots())
    #expect(outcome.nextState(from: elsewhere) == elsewhere)
  }
}
