import GleamHub
import Testing

@Suite("Walking the rail")
struct HubNavigationWalkingTests {

  @Test(
    "down moves to the next destination in rail order", arguments: 0..<(railTopToBottom.count - 1))
  func downMovesToTheNextDestinationInRailOrder(row: Int) {
    let transition = HubNavigationResolver.transition(
      makeNavigationState(selection: railTopToBottom[row]),
      applying: .arrowDown
    )
    #expect(transition.next.selection == railTopToBottom[row + 1])
  }

  @Test("up moves to the previous destination in rail order", arguments: 1..<railTopToBottom.count)
  func upMovesToThePreviousDestinationInRailOrder(row: Int) {
    let transition = HubNavigationResolver.transition(
      makeNavigationState(selection: railTopToBottom[row]),
      applying: .arrowUp
    )
    #expect(transition.next.selection == railTopToBottom[row - 1])
  }

  @Test("up at the top of the rail stays put")
  func upAtTheTopOfTheRailStaysPut() {
    let top = makeNavigationState(selection: railTopToBottom[0])
    #expect(HubNavigationResolver.transition(top, applying: .arrowUp).next == top)
  }

  @Test("down at the bottom of the rail stays put")
  func downAtTheBottomOfTheRailStaysPut() {
    let bottom = makeNavigationState(selection: railTopToBottom[railTopToBottom.count - 1])
    #expect(HubNavigationResolver.transition(bottom, applying: .arrowDown).next == bottom)
  }

  @Test("holding down from the top reaches the bottom and stops there")
  func holdingDownFromTheTopReachesTheBottomAndStops() {
    var state = HubNavigationState.initial
    for _ in 0..<(railTopToBottom.count * 2) {
      state = HubNavigationResolver.transition(state, applying: .arrowDown).next
    }
    #expect(state.selection == railTopToBottom[railTopToBottom.count - 1])
  }

  @Test("every destination is reachable from the top with down alone")
  func everyDestinationIsReachableFromTheTopWithDownAlone() {
    var visited: [HubDestination] = [HubNavigationState.initial.selection]
    var state = HubNavigationState.initial
    for _ in 0..<railTopToBottom.count {
      state = HubNavigationResolver.transition(state, applying: .arrowDown).next
      if visited.last != state.selection {
        visited.append(state.selection)
      }
    }
    #expect(visited == railTopToBottom)
  }

  @Test(
    "walking the rail with arrows never leaves the rail",
    arguments: [UInt64(1), 7, 99, 4242]
  )
  func walkingTheRailWithArrowsNeverLeavesTheRail(seed: UInt64) {
    var state = HubNavigationState.initial
    for key in makeKeySequence(seed: seed, length: 200, drawnFrom: arrowKeys) {
      state = HubNavigationResolver.transition(state, applying: key).next
      #expect(railTopToBottom.contains(state.selection))
    }
  }
}

/// The rail replaced a hexagon of six cards driven by all four arrows and a
/// matched geometry zoom. These are the tests for the way off that interface:
/// the old moves must be gone, not merely unused.
@Suite("The hexagon is gone")
struct HexagonRetirementTests {

  @Test("left never moves the selection", arguments: railTopToBottom)
  func leftNeverMovesTheSelection(destination: HubDestination) {
    let state = makeNavigationState(selection: destination)
    #expect(HubNavigationResolver.transition(state, applying: .arrowLeft).next == state)
  }

  @Test("right never moves the selection", arguments: railTopToBottom)
  func rightNeverMovesTheSelection(destination: HubDestination) {
    let state = makeNavigationState(selection: destination)
    #expect(HubNavigationResolver.transition(state, applying: .arrowRight).next == state)
  }

  @Test("down walks past the old column boundary instead of clamping at it")
  func downWalksPastTheOldColumnBoundary() {
    // Protection ended the left column of the hexagon, so down clamped there.
    let transition = HubNavigationResolver.transition(
      makeNavigationState(selection: .module(.protection)),
      applying: .arrowDown
    )
    #expect(transition.next.selection == .module(.performance))
  }

  @Test("return no longer enters a module, it asks the pane to act")
  func returnNoLongerEntersAModule() {
    let state = makeNavigationState(selection: .module(.cleanup))
    let transition = HubNavigationResolver.transition(state, applying: .return)
    #expect(transition.next == state)
    #expect(transition.intent == .activatePrimaryAction)
  }

  @Test("escape no longer backs out to a hub, it asks the pane to dismiss")
  func escapeNoLongerBacksOutToAHub() {
    let state = makeNavigationState(selection: .module(.cleanup))
    let transition = HubNavigationResolver.transition(state, applying: .escape)
    #expect(transition.next == state)
    #expect(transition.intent == .dismiss)
  }
}
