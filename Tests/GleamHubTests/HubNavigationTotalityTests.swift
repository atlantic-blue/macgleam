import Foundation
import GleamHub
import Testing

@Suite("Hub navigation totality and determinism")
struct HubNavigationTotalityTests {

  @Test(
    "every position, key and enabled set returns a transition and equal inputs return equal outputs",
    arguments: makeAllPositions(), HubKeyEvent.allCases
  )
  func everyPositionKeyAndEnabledSetReturnsATransitionAndEqualInputsReturnEqualOutputs(
    position: HubNavigationState.Position,
    key: HubKeyEvent
  ) {
    for enabledModules in makeEnabledVariants() {
      let state = makeNavigationState(position: position, slots: makeFullSlots())
      let first = HubNavigationResolver.transition(
        state, applying: key, enabledModules: enabledModules
      )
      let second = HubNavigationResolver.transition(
        state, applying: key, enabledModules: enabledModules
      )
      #expect(first == second)
    }
  }

  @Test(
    "separately constructed equal states produce equal transitions",
    arguments: makeAllPositions(), HubKeyEvent.allCases
  )
  func separatelyConstructedEqualStatesProduceEqualTransitions(
    position: HubNavigationState.Position,
    key: HubKeyEvent
  ) {
    let first = HubNavigationResolver.transition(
      makeNavigationState(position: position, slots: makeFullSlots()),
      applying: key,
      enabledModules: allModulesEnabled
    )
    let second = HubNavigationResolver.transition(
      makeNavigationState(position: position, slots: makeFullSlots()),
      applying: key,
      enabledModules: allModulesEnabled
    )
    #expect(first == second)
  }

  @Test(
    "an identity transition stays the identity on repeated presses of the same key",
    arguments: makeAllPositions(), HubKeyEvent.allCases
  )
  func anIdentityTransitionStaysTheIdentityOnRepeatedPressesOfTheSameKey(
    position: HubNavigationState.Position,
    key: HubKeyEvent
  ) {
    let state = makeNavigationState(position: position, slots: makeFullSlots())
    let first = HubNavigationResolver.transition(
      state, applying: key, enabledModules: allModulesEnabled
    )
    guard first.next == state else { return }
    let second = HubNavigationResolver.transition(
      first.next, applying: key, enabledModules: allModulesEnabled
    )
    #expect(second.next == state)
    #expect(second.zoom == nil)
  }

  @Test(
    "pressing one arrow three times settles at a card where a fourth press changes nothing",
    arguments: HubModule.allCases, [HubKeyEvent.arrowUp, .arrowDown, .arrowLeft, .arrowRight]
  )
  func pressingOneArrowThreeTimesSettlesAtACardWhereAFourthPressChangesNothing(
    start: HubModule,
    key: HubKeyEvent
  ) {
    var state = makeNavigationState(position: .hub(focus: start), slots: makeFullSlots())
    for _ in 0..<3 {
      state =
        HubNavigationResolver.transition(
          state, applying: key, enabledModules: allModulesEnabled
        ).next
    }
    let fourth = HubNavigationResolver.transition(
      state, applying: key, enabledModules: allModulesEnabled
    )
    #expect(fourth.next == state)
    #expect(fourth.zoom == nil)
  }
}
