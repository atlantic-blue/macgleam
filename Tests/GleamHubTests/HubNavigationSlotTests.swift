import Foundation
import GleamHub
import Testing

@Suite("Module state slots")
struct ModuleStateSlotTests {

  @Test(
    "storingSlot round trips the exact payload for the module",
    arguments: HubModule.allCases
  )
  func storingSlotRoundTripsTheExactPayloadForTheModule(module: HubModule) {
    let payload = Data("the module's own encoded state".utf8)
    let stored = HubNavigationState.initial.storingSlot(
      ModuleStateSlot(payload: payload), for: module
    )
    #expect(stored.moduleStateSlots[module]?.payload == payload)
  }

  @Test(
    "storingSlot leaves the position and every other slot identical",
    arguments: HubModule.allCases
  )
  func storingSlotLeavesThePositionAndEveryOtherSlotIdentical(module: HubModule) {
    let original = makeNavigationState(
      position: .hub(focus: .protection), slots: makeFullSlots()
    )
    let replacement = makeSlot("replacement payload")
    let stored = original.storingSlot(replacement, for: module)
    #expect(stored.position == original.position)
    #expect(stored.moduleStateSlots[module] == replacement)
    for other in HubModule.allCases where other != module {
      #expect(stored.moduleStateSlots[other] == original.moduleStateSlots[other])
    }
  }

  @Test("storingSlot replaces an existing slot for the same module")
  func storingSlotReplacesAnExistingSlotForTheSameModule() {
    let first = makeSlot("first payload")
    let second = makeSlot("second payload")
    let state = HubNavigationState.initial
      .storingSlot(first, for: .cleanup)
      .storingSlot(second, for: .cleanup)
    #expect(state.moduleStateSlots[.cleanup] == second)
  }

  @Test(
    "every transition passes the module state slots through untouched",
    arguments: makeAllPositions(), HubKeyEvent.allCases
  )
  func everyTransitionPassesTheModuleStateSlotsThroughUntouched(
    position: HubNavigationState.Position,
    key: HubKeyEvent
  ) {
    for enabledModules in makeEnabledVariants() {
      let slots = makeFullSlots()
      let state = makeNavigationState(position: position, slots: slots)
      let transition = HubNavigationResolver.transition(
        state, applying: key, enabledModules: enabledModules
      )
      #expect(transition.next.moduleStateSlots == slots)
    }
  }

  @Test(
    "a slot survives enter, leave and re entry byte for byte",
    arguments: HubModule.allCases
  )
  func aSlotSurvivesEnterLeaveAndReEntryByteForByte(module: HubModule) {
    let payload = Data("scroll offset 42, selection three".utf8)
    let seeded = HubNavigationState.initial.storingSlot(
      ModuleStateSlot(payload: payload), for: module
    )
    var state = makeNavigationState(
      position: .hub(focus: module), slots: seeded.moduleStateSlots
    )
    for key in [HubKeyEvent.return, .escape, .return] {
      state =
        HubNavigationResolver.transition(
          state, applying: key, enabledModules: allModulesEnabled
        ).next
    }
    #expect(state.position == .module(module))
    #expect(state.moduleStateSlots[module]?.payload == payload)
  }

  @Test(
    "slots survive arbitrary key sequences at every step",
    arguments: UInt64(0)..<UInt64(16)
  )
  func slotsSurviveArbitraryKeySequencesAtEveryStep(seed: UInt64) {
    let slots = makeFullSlots()
    var state = makeNavigationState(slots: slots)
    for key in makeKeySequence(seed: seed, length: 200, drawnFrom: HubKeyEvent.allCases) {
      state =
        HubNavigationResolver.transition(
          state, applying: key, enabledModules: allModulesEnabled
        ).next
      #expect(state.moduleStateSlots == slots)
    }
  }
}
