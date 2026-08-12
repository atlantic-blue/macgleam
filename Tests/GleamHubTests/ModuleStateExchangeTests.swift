import Foundation
import GleamHub
import Testing

/// A module surface driven by the tests: it hands out whatever slot it is
/// told to, and records every slot handed back to it.
@MainActor
final class RecordingPreserver: ModuleStatePreserving {
  var slotToGive: ModuleStateSlot?
  private(set) var restored: [ModuleStateSlot] = []
  private(set) var slotRequestCount = 0

  init(giving slot: ModuleStateSlot?) {
    slotToGive = slot
  }

  func stateSlot() -> ModuleStateSlot? {
    slotRequestCount += 1
    return slotToGive
  }

  func restoreState(from slot: ModuleStateSlot) {
    restored.append(slot)
  }
}

@MainActor
@Suite("Module state exchange")
struct ModuleStateExchangeTests {

  @Test(
    "leaving a module stores exactly the bytes that module gave",
    arguments: HubModule.allCases
  )
  func leavingAModuleStoresExactlyTheBytesThatModuleGave(module: HubModule) {
    let slot = makeSlot("collapsed: caches, logs")
    let preserver = RecordingPreserver(giving: slot)
    let next = ModuleStateExchange.navigate(
      makeNavigationState(selection: .module(module)),
      to: .settings,
      preservers: [module: preserver]
    )
    #expect(next.moduleStateSlots[module] == slot)
    #expect(next.selection == .settings)
  }

  @Test("leaving a module leaves every other module's slot untouched")
  func leavingAModuleLeavesEveryOtherModulesSlotUntouched() {
    let existing = makeFullSlots()
    let replacement = makeSlot("the newest state")
    let next = ModuleStateExchange.navigate(
      makeNavigationState(selection: .module(.cleanup), slots: existing),
      to: .diskMap,
      preservers: [.cleanup: RecordingPreserver(giving: replacement)]
    )
    #expect(next.moduleStateSlots[.cleanup] == replacement)
    for other in HubModule.allCases where other != .cleanup {
      #expect(next.moduleStateSlots[other] == existing[other])
    }
  }

  @Test("a module with nothing to preserve stores nothing and is unaffected")
  func aModuleWithNothingToPreserveStoresNothingAndIsUnaffected() {
    let existing = makeFullSlots()
    let preserver = RecordingPreserver(giving: nil)
    let state = makeNavigationState(selection: .module(.performance), slots: existing)
    let next = ModuleStateExchange.navigate(
      state, to: .settings, preservers: [.performance: preserver])
    #expect(preserver.slotRequestCount == 1)
    #expect(next.moduleStateSlots == existing)
  }

  @Test("a module with no preserver at all is left alone")
  func aModuleWithNoPreserverAtAllIsLeftAlone() {
    let existing = makeFullSlots()
    let next = ModuleStateExchange.navigate(
      makeNavigationState(selection: .module(.leftovers), slots: existing),
      to: .settings,
      preservers: [:]
    )
    #expect(next.moduleStateSlots == existing)
    #expect(next.selection == .settings)
  }

  @Test(
    "arriving at a module hands back exactly what it left, byte for byte",
    arguments: HubModule.allCases
  )
  func arrivingAtAModuleHandsBackExactlyWhatItLeft(module: HubModule) {
    let slot = makeSlot("the state the module wrote on the way out")
    let preserver = RecordingPreserver(giving: nil)
    let state = makeNavigationState(selection: .settings)
      .storingSlot(slot, for: module)
    _ = ModuleStateExchange.navigate(
      state, to: .module(module), preservers: [module: preserver])
    #expect(preserver.restored == [slot])
  }

  @Test("arriving at a module with no stored slot restores nothing")
  func arrivingAtAModuleWithNoStoredSlotRestoresNothing() {
    let preserver = RecordingPreserver(giving: nil)
    _ = ModuleStateExchange.navigate(
      makeNavigationState(selection: .settings),
      to: .module(.cleanup),
      preservers: [.cleanup: preserver]
    )
    #expect(preserver.restored.isEmpty)
  }

  @Test("navigating to the destination already selected changes and asks nothing")
  func navigatingToTheDestinationAlreadySelectedChangesAndAsksNothing() {
    let preserver = RecordingPreserver(giving: makeSlot("would be stored"))
    let state = makeNavigationState(selection: .module(.cleanup), slots: makeFullSlots())
    let next = ModuleStateExchange.navigate(
      state, to: .module(.cleanup), preservers: [.cleanup: preserver])
    #expect(next == state)
    #expect(preserver.slotRequestCount == 0)
    #expect(preserver.restored.isEmpty)
  }

  @Test("leaving a destination that is not a module stores nothing")
  func leavingADestinationThatIsNotAModuleStoresNothing() {
    let preserver = RecordingPreserver(giving: makeSlot("never asked for"))
    for chrome in [HubDestination.diskMap, .settings] {
      let existing = makeFullSlots()
      let next = ModuleStateExchange.navigate(
        makeNavigationState(selection: chrome, slots: existing),
        to: .module(.protection),
        preservers: [.cleanup: preserver]
      )
      #expect(next.moduleStateSlots == existing)
    }
    #expect(preserver.slotRequestCount == 0)
  }

  @Test("a slot survives a walk through every destination and back")
  func aSlotSurvivesAWalkThroughEveryDestinationAndBack() {
    let slot = makeSlot("three categories collapsed")
    let preserver = RecordingPreserver(giving: slot)
    var state = makeNavigationState(selection: .module(.cleanup))
    for destination in HubDestination.allCases where destination != .module(.cleanup) {
      state = ModuleStateExchange.navigate(
        state, to: destination, preservers: [.cleanup: preserver])
    }
    preserver.slotToGive = nil
    state = ModuleStateExchange.navigate(
      state, to: .module(.cleanup), preservers: [.cleanup: preserver])
    #expect(state.selection == .module(.cleanup))
    #expect(preserver.restored == [slot])
  }

  @Test("the exchange never invents a slot for a module it did not visit")
  func theExchangeNeverInventsASlotForAModuleItDidNotVisit() {
    let preserver = RecordingPreserver(giving: makeSlot("cleanup only"))
    var state = HubNavigationState.initial
    for destination in HubDestination.allCases {
      state = ModuleStateExchange.navigate(
        state, to: destination, preservers: [.cleanup: preserver])
    }
    #expect(Set(state.moduleStateSlots.keys) == [.cleanup])
  }
}
