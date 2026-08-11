import Foundation
import GleamHub
import Testing

@Suite("Arrows and the ends of the rail")
struct HubKeyOutcomeRailTests {

  @Test(
    "down moves to the next destination in rail order",
    arguments: 0..<(railTopToBottom.count - 1), paneShapes
  )
  func downMovesToTheNextDestinationInRailOrder(row: Int, shape: PaneShape) {
    let state = makeNavigationState(selection: railTopToBottom[row])
    let outcome = HubKeyResolver.outcome(state, applying: .arrowDown, pane: shape.capabilities)
    #expect(outcome == .moved(makeNavigationState(selection: railTopToBottom[row + 1])))
    #expect(outcome.isHandled)
  }

  @Test(
    "up moves to the previous destination in rail order",
    arguments: 1..<railTopToBottom.count, paneShapes
  )
  func upMovesToThePreviousDestinationInRailOrder(row: Int, shape: PaneShape) {
    let state = makeNavigationState(selection: railTopToBottom[row])
    let outcome = HubKeyResolver.outcome(state, applying: .arrowUp, pane: shape.capabilities)
    #expect(outcome == .moved(makeNavigationState(selection: railTopToBottom[row - 1])))
    #expect(outcome.isHandled)
  }

  @Test("a move carries no intent for the pane", arguments: everyKeyScenario)
  func aMoveCarriesNoIntentForThePane(scenario: KeyScenario) {
    let outcome = HubKeyResolver.outcome(
      scenario.state, applying: scenario.key, pane: scenario.capabilities)
    guard case .moved = outcome else { return }
    #expect(outcome.intent == nil)
  }

  /// The end of the rail is where the old shell was worst: it clamped, nothing
  /// moved, and it claimed the key anyway, so the press vanished in silence.
  /// Ignored is what lets the press fall through and the person hear the beep
  /// that tells them they have run out of rail.
  @Test("up at the top of the rail is ignored, because nothing happened", arguments: paneShapes)
  func upAtTheTopOfTheRailIsIgnoredBecauseNothingHappened(shape: PaneShape) {
    let top = makeNavigationState(selection: railTopToBottom[0], slots: makeFullSlots())
    let outcome = HubKeyResolver.outcome(top, applying: .arrowUp, pane: shape.capabilities)
    #expect(outcome == .ignored)
    #expect(outcome.isHandled == false)
    #expect(outcome.nextState(from: top) == top)
  }

  @Test(
    "down at the bottom of the rail is ignored, because nothing happened",
    arguments: paneShapes)
  func downAtTheBottomOfTheRailIsIgnoredBecauseNothingHappened(shape: PaneShape) {
    let bottom = makeNavigationState(
      selection: railTopToBottom[railTopToBottom.count - 1], slots: makeFullSlots())
    let outcome = HubKeyResolver.outcome(bottom, applying: .arrowDown, pane: shape.capabilities)
    #expect(outcome == .ignored)
    #expect(outcome.isHandled == false)
    #expect(outcome.nextState(from: bottom) == bottom)
  }

  @Test("the top of the rail is the initial selection")
  func theTopOfTheRailIsTheInitialSelection() {
    #expect(HubNavigationState.initial.selection == railTopToBottom[0])
  }

  @Test("holding down from the top reaches the bottom and is then ignored")
  func holdingDownFromTheTopReachesTheBottomAndIsThenIgnored() {
    let pane = HubPaneCapabilities(hasPrimaryAction: true, hasDismissal: true)
    var state = HubNavigationState.initial
    var handledPresses = 0
    for _ in 0..<(railTopToBottom.count * 2) {
      let outcome = HubKeyResolver.outcome(state, applying: .arrowDown, pane: pane)
      if outcome.isHandled { handledPresses += 1 }
      state = outcome.nextState(from: state)
    }
    #expect(state.selection == railTopToBottom[railTopToBottom.count - 1])
    #expect(handledPresses == railTopToBottom.count - 1)
  }

  @Test("holding up from the bottom reaches the top and is then ignored")
  func holdingUpFromTheBottomReachesTheTopAndIsThenIgnored() {
    let pane = HubPaneCapabilities(hasPrimaryAction: true, hasDismissal: true)
    var state = makeNavigationState(selection: railTopToBottom[railTopToBottom.count - 1])
    var handledPresses = 0
    for _ in 0..<(railTopToBottom.count * 2) {
      let outcome = HubKeyResolver.outcome(state, applying: .arrowUp, pane: pane)
      if outcome.isHandled { handledPresses += 1 }
      state = outcome.nextState(from: state)
    }
    #expect(state.selection == railTopToBottom[0])
    #expect(handledPresses == railTopToBottom.count - 1)
  }

  @Test("walking the rail with arrows never leaves it", arguments: [UInt64(1), 7, 99, 4242])
  func walkingTheRailWithArrowsNeverLeavesIt(seed: UInt64) {
    let pane = HubPaneCapabilities(hasPrimaryAction: true, hasDismissal: true)
    var state = HubNavigationState.initial
    for key in makeKeySequence(seed: seed, length: 200, drawnFrom: arrowKeys) {
      let outcome = HubKeyResolver.outcome(state, applying: key, pane: pane)
      state = outcome.nextState(from: state)
      #expect(railTopToBottom.contains(state.selection))
    }
  }

  @Test("left is always ignored, whatever the pane can do", arguments: everyKeyScenario)
  func leftIsAlwaysIgnoredWhateverThePaneCanDo(scenario: KeyScenario) {
    guard scenario.key == .arrowLeft else { return }
    let state = scenario.state
    let outcome = HubKeyResolver.outcome(state, applying: .arrowLeft, pane: scenario.capabilities)
    #expect(outcome == .ignored)
    #expect(outcome.nextState(from: state) == state)
  }

  @Test("right is always ignored, whatever the pane can do", arguments: everyKeyScenario)
  func rightIsAlwaysIgnoredWhateverThePaneCanDo(scenario: KeyScenario) {
    guard scenario.key == .arrowRight else { return }
    let state = scenario.state
    let outcome = HubKeyResolver.outcome(state, applying: .arrowRight, pane: scenario.capabilities)
    #expect(outcome == .ignored)
    #expect(outcome.nextState(from: state) == state)
  }

  @Test("neither horizontal arrow ever carries an intent", arguments: everyKeyScenario)
  func neitherHorizontalArrowEverCarriesAnIntent(scenario: KeyScenario) {
    guard scenario.key == .arrowLeft || scenario.key == .arrowRight else { return }
    let outcome = HubKeyResolver.outcome(
      scenario.state, applying: scenario.key, pane: scenario.capabilities)
    #expect(outcome.intent == nil)
  }
}
