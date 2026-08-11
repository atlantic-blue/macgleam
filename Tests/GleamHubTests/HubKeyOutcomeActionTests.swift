import Foundation
import GleamHub
import Testing

@Suite("Return and escape reach the pane")
struct HubKeyOutcomeActionTests {

  @Test("return asks a pane with a primary action to run it", arguments: railTopToBottom)
  func returnAsksAPaneWithAPrimaryActionToRunIt(destination: HubDestination) {
    let state = makeNavigationState(selection: destination)
    let pane = HubPaneCapabilities(hasPrimaryAction: true, hasDismissal: false)
    let outcome = HubKeyResolver.outcome(state, applying: .return, pane: pane)
    #expect(outcome == .acted(.activatePrimaryAction))
    #expect(outcome.isHandled)
  }

  @Test("return is ignored by a pane with no primary action", arguments: railTopToBottom)
  func returnIsIgnoredByAPaneWithNoPrimaryAction(destination: HubDestination) {
    let state = makeNavigationState(selection: destination)
    let pane = HubPaneCapabilities(hasPrimaryAction: false, hasDismissal: true)
    let outcome = HubKeyResolver.outcome(state, applying: .return, pane: pane)
    #expect(outcome == .ignored)
    #expect(outcome.isHandled == false)
  }

  @Test("return never moves the selection", arguments: everyKeyScenario)
  func returnNeverMovesTheSelection(scenario: KeyScenario) {
    guard scenario.key == .return else { return }
    let state = scenario.state
    let outcome = HubKeyResolver.outcome(state, applying: .return, pane: scenario.capabilities)
    #expect(outcome.nextState(from: state) == state)
  }

  @Test("escape asks a pane with a dismissal to dismiss", arguments: railTopToBottom)
  func escapeAsksAPaneWithADismissalToDismiss(destination: HubDestination) {
    let state = makeNavigationState(selection: destination)
    let pane = HubPaneCapabilities(hasPrimaryAction: false, hasDismissal: true)
    let outcome = HubKeyResolver.outcome(state, applying: .escape, pane: pane)
    #expect(outcome == .acted(.dismiss))
    #expect(outcome.isHandled)
  }

  @Test("escape is ignored by a pane with no dismissal", arguments: railTopToBottom)
  func escapeIsIgnoredByAPaneWithNoDismissal(destination: HubDestination) {
    let state = makeNavigationState(selection: destination)
    let pane = HubPaneCapabilities(hasPrimaryAction: true, hasDismissal: false)
    let outcome = HubKeyResolver.outcome(state, applying: .escape, pane: pane)
    #expect(outcome == .ignored)
    #expect(outcome.isHandled == false)
  }

  /// Escape is the key a person presses to get out of the way. It must never be
  /// the key that starts work, and it must never be the key that destroys any.
  /// Dismiss is the only thing it is ever allowed to ask for, at every
  /// destination and under every pane shape.
  @Test(
    "escape only ever asks for a dismissal, never anything else",
    arguments: everyKeyScenario)
  func escapeOnlyEverAsksForADismissalNeverAnythingElse(scenario: KeyScenario) {
    guard scenario.key == .escape else { return }
    let outcome = HubKeyResolver.outcome(
      scenario.state, applying: .escape, pane: scenario.capabilities)
    for intent in HubIntent.allCases where intent != .dismiss {
      #expect(outcome.intent != intent)
    }
    #expect(outcome.intent == nil || outcome.intent == .dismiss)
  }

  @Test("escape never moves the selection", arguments: everyKeyScenario)
  func escapeNeverMovesTheSelection(scenario: KeyScenario) {
    guard scenario.key == .escape else { return }
    let state = scenario.state
    let outcome = HubKeyResolver.outcome(state, applying: .escape, pane: scenario.capabilities)
    #expect(outcome.nextState(from: state) == state)
  }

  @Test(
    "only return ever asks a pane to run its primary action",
    arguments: everyKeyScenario)
  func onlyReturnEverAsksAPaneToRunItsPrimaryAction(scenario: KeyScenario) {
    let outcome = HubKeyResolver.outcome(
      scenario.state, applying: scenario.key, pane: scenario.capabilities)
    guard outcome.intent == .activatePrimaryAction else { return }
    #expect(scenario.key == .return)
  }

  @Test("only escape ever asks a pane to dismiss", arguments: everyKeyScenario)
  func onlyEscapeEverAsksAPaneToDismiss(scenario: KeyScenario) {
    let outcome = HubKeyResolver.outcome(
      scenario.state, applying: scenario.key, pane: scenario.capabilities)
    guard outcome.intent == .dismiss else { return }
    #expect(scenario.key == .escape)
  }
}

/// The two capabilities are read separately. A pane offering one of them does
/// not thereby claim the other's key.
@Suite("The two pane capabilities are independent")
struct HubPaneCapabilityIndependenceTests {

  @Test("a pane with a dismissal but no primary action ignores return and handles escape")
  func aPaneWithADismissalButNoPrimaryActionIgnoresReturnAndHandlesEscape() {
    let pane = HubPaneCapabilities(hasPrimaryAction: false, hasDismissal: true)
    let state = makeNavigationState(selection: .module(.cleanup))
    #expect(HubKeyResolver.outcome(state, applying: .return, pane: pane) == .ignored)
    #expect(HubKeyResolver.outcome(state, applying: .escape, pane: pane) == .acted(.dismiss))
  }

  @Test("a pane with a primary action but no dismissal handles return and ignores escape")
  func aPaneWithAPrimaryActionButNoDismissalHandlesReturnAndIgnoresEscape() {
    let pane = HubPaneCapabilities(hasPrimaryAction: true, hasDismissal: false)
    let state = makeNavigationState(selection: .module(.cleanup))
    #expect(
      HubKeyResolver.outcome(state, applying: .return, pane: pane) == .acted(.activatePrimaryAction)
    )
    #expect(HubKeyResolver.outcome(state, applying: .escape, pane: pane) == .ignored)
  }

  @Test("a pane offering both runs both keys")
  func aPaneOfferingBothRunsBothKeys() {
    let pane = HubPaneCapabilities(hasPrimaryAction: true, hasDismissal: true)
    let state = makeNavigationState(selection: .module(.cleanup))
    #expect(
      HubKeyResolver.outcome(state, applying: .return, pane: pane) == .acted(.activatePrimaryAction)
    )
    #expect(HubKeyResolver.outcome(state, applying: .escape, pane: pane) == .acted(.dismiss))
  }

  @Test("a pane offering neither ignores both keys")
  func aPaneOfferingNeitherIgnoresBothKeys() {
    let pane = HubPaneCapabilities(hasPrimaryAction: false, hasDismissal: false)
    let state = makeNavigationState(selection: .module(.cleanup))
    #expect(HubKeyResolver.outcome(state, applying: .return, pane: pane) == .ignored)
    #expect(HubKeyResolver.outcome(state, applying: .escape, pane: pane) == .ignored)
  }

  @Test("what a pane offers never changes where an arrow goes", arguments: railTopToBottom)
  func whatAPaneOffersNeverChangesWhereAnArrowGoes(destination: HubDestination) {
    let state = makeNavigationState(selection: destination)
    for key in [HubKeyEvent.arrowUp, .arrowDown, .arrowLeft, .arrowRight] {
      let outcomes = paneShapes.map {
        HubKeyResolver.outcome(state, applying: key, pane: $0.capabilities)
      }
      #expect(Set(outcomes.map(\.isHandled)).count == 1)
      #expect(outcomes.allSatisfy { $0 == outcomes[0] })
    }
  }
}
