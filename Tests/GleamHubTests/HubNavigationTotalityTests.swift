import Foundation
import GleamHub
import Testing

@Suite("Hub navigation totality and determinism")
struct HubNavigationTotalityTests {

  @Test(
    "every destination and key returns a transition, and equal inputs return equal outputs",
    arguments: railTopToBottom, HubKeyEvent.allCases
  )
  func everyDestinationAndKeyReturnsATransitionAndEqualInputsReturnEqualOutputs(
    destination: HubDestination,
    key: HubKeyEvent
  ) {
    let state = makeNavigationState(selection: destination, slots: makeFullSlots())
    let first = HubNavigationResolver.transition(state, applying: key)
    let second = HubNavigationResolver.transition(state, applying: key)
    #expect(first == second)
  }

  @Test(
    "separately constructed equal states produce equal transitions",
    arguments: railTopToBottom, HubKeyEvent.allCases
  )
  func separatelyConstructedEqualStatesProduceEqualTransitions(
    destination: HubDestination,
    key: HubKeyEvent
  ) {
    let first = HubNavigationResolver.transition(
      makeNavigationState(selection: destination, slots: makeFullSlots()), applying: key)
    let second = HubNavigationResolver.transition(
      makeNavigationState(selection: destination, slots: makeFullSlots()), applying: key)
    #expect(first == second)
  }

  @Test(
    "an identity transition stays the identity on repeated presses of the same key",
    arguments: railTopToBottom, HubKeyEvent.allCases
  )
  func anIdentityTransitionStaysTheIdentityOnRepeatedPressesOfTheSameKey(
    destination: HubDestination,
    key: HubKeyEvent
  ) {
    let state = makeNavigationState(selection: destination, slots: makeFullSlots())
    let first = HubNavigationResolver.transition(state, applying: key)
    guard first.next == state else { return }
    let second = HubNavigationResolver.transition(first.next, applying: key)
    #expect(second.next == state)
  }

  @Test(
    "holding one arrow settles where a further press changes nothing",
    arguments: railTopToBottom, [HubKeyEvent.arrowUp, .arrowDown, .arrowLeft, .arrowRight]
  )
  func holdingOneArrowSettlesWhereAFurtherPressChangesNothing(
    start: HubDestination,
    key: HubKeyEvent
  ) {
    var state = makeNavigationState(selection: start, slots: makeFullSlots())
    for _ in 0..<railTopToBottom.count {
      state = HubNavigationResolver.transition(state, applying: key).next
    }
    let further = HubNavigationResolver.transition(state, applying: key)
    #expect(further.next == state)
  }

  @Test(
    "only return and escape carry an intent, and each carries exactly its own",
    arguments: railTopToBottom, HubKeyEvent.allCases
  )
  func onlyReturnAndEscapeCarryAnIntent(destination: HubDestination, key: HubKeyEvent) {
    let transition = HubNavigationResolver.transition(
      makeNavigationState(selection: destination), applying: key)
    switch key {
    case .return: #expect(transition.intent == .activatePrimaryAction)
    case .escape: #expect(transition.intent == .dismiss)
    case .arrowUp, .arrowDown, .arrowLeft, .arrowRight: #expect(transition.intent == nil)
    }
  }
}
