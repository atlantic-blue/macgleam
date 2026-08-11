import Foundation
import GleamHub
import Testing

/// Six keys, four pane shapes, every destination in the rail including both
/// ends. Every one of those cells has to answer, and answer the same way twice.
@Suite("Key outcome totality and determinism")
struct HubKeyOutcomeTotalityTests {

  @Test("the matrix is every key against every pane shape at every destination")
  func theMatrixIsEveryKeyAgainstEveryPaneShapeAtEveryDestination() {
    let shapes = paneShapes.map(\.capabilities)
    #expect(Set(shapes.map { [$0.hasPrimaryAction, $0.hasDismissal] }).count == 4)
    #expect(everyKeyScenario.count == railTopToBottom.count * HubKeyEvent.allCases.count * 4)
  }

  @Test("every cell of the matrix returns an outcome")
  func everyCellOfTheMatrixReturnsAnOutcome() {
    let outcomes = everyKeyScenario.map { scenario in
      HubKeyResolver.outcome(scenario.state, applying: scenario.key, pane: scenario.capabilities)
    }
    #expect(outcomes.count == everyKeyScenario.count)
  }

  @Test("the same inputs return the same outcome twice", arguments: everyKeyScenario)
  func theSameInputsReturnTheSameOutcomeTwice(scenario: KeyScenario) {
    let state = scenario.state
    let first = HubKeyResolver.outcome(state, applying: scenario.key, pane: scenario.capabilities)
    let second = HubKeyResolver.outcome(state, applying: scenario.key, pane: scenario.capabilities)
    #expect(first == second)
  }

  @Test("separately constructed equal inputs return equal outcomes", arguments: everyKeyScenario)
  func separatelyConstructedEqualInputsReturnEqualOutcomes(scenario: KeyScenario) {
    let capabilities = HubPaneCapabilities(
      hasPrimaryAction: scenario.capabilities.hasPrimaryAction,
      hasDismissal: scenario.capabilities.hasDismissal
    )
    let first = HubKeyResolver.outcome(
      scenario.state, applying: scenario.key, pane: scenario.capabilities)
    let second = HubKeyResolver.outcome(scenario.state, applying: scenario.key, pane: capabilities)
    #expect(first == second)
  }

  @Test("the outcome is the one the contract describes", arguments: everyKeyScenario)
  func theOutcomeIsTheOneTheContractDescribes(scenario: KeyScenario) {
    let outcome = HubKeyResolver.outcome(
      scenario.state, applying: scenario.key, pane: scenario.capabilities)
    #expect(outcome == contractedOutcome(for: scenario))
  }

  @Test("no key press creates, drops or alters a module state slot", arguments: everyKeyScenario)
  func noKeyPressCreatesDropsOrAltersAModuleStateSlot(scenario: KeyScenario) {
    let state = scenario.state
    let outcome = HubKeyResolver.outcome(state, applying: scenario.key, pane: scenario.capabilities)
    #expect(outcome.nextState(from: state).moduleStateSlots == state.moduleStateSlots)
  }

  @Test("a state carrying no slots at all is answered the same way", arguments: everyKeyScenario)
  func aStateCarryingNoSlotsAtAllIsAnsweredTheSameWay(scenario: KeyScenario) {
    let bare = makeNavigationState(selection: scenario.destination)
    let outcome = HubKeyResolver.outcome(bare, applying: scenario.key, pane: scenario.capabilities)
    let contracted = contractedOutcome(for: scenario)
    #expect(outcome.isHandled == contracted.isHandled)
    #expect(outcome.intent == contracted.intent)
    #expect(outcome.nextState(from: bare).moduleStateSlots.isEmpty)
  }

  @Test("isHandled is false only for an ignored press", arguments: everyKeyScenario)
  func isHandledIsFalseOnlyForAnIgnoredPress(scenario: KeyScenario) {
    let outcome = HubKeyResolver.outcome(
      scenario.state, applying: scenario.key, pane: scenario.capabilities)
    #expect(outcome.isHandled == (outcome != .ignored))
  }

  @Test("an intent is carried only by an acted outcome", arguments: everyKeyScenario)
  func anIntentIsCarriedOnlyByAnActedOutcome(scenario: KeyScenario) {
    let outcome = HubKeyResolver.outcome(
      scenario.state, applying: scenario.key, pane: scenario.capabilities)
    switch outcome {
    case .acted(let intent): #expect(outcome.intent == intent)
    case .moved, .ignored: #expect(outcome.intent == nil)
    }
  }
}
