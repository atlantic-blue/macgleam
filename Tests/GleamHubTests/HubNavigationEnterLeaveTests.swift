import Foundation
import GleamHub
import Testing

@Suite("Hub enter and leave")
struct HubEnterAndLeaveTests {

  @Test(
    "return on an enabled focused card enters that module with a zoom in for it",
    arguments: HubModule.allCases
  )
  func returnOnAnEnabledFocusedCardEntersThatModuleWithAZoomInForIt(module: HubModule) {
    let state = makeNavigationState(position: .hub(focus: module), slots: makeFullSlots())
    let transition = HubNavigationResolver.transition(
      state, applying: .return, enabledModules: allModulesEnabled
    )
    #expect(transition.next.position == .module(module))
    #expect(transition.zoom == HubZoom(module: module, direction: .zoomIn))
  }

  @Test(
    "return on a disabled focused card changes nothing and emits no zoom",
    arguments: HubModule.allCases
  )
  func returnOnADisabledFocusedCardChangesNothingAndEmitsNoZoom(module: HubModule) {
    let state = makeNavigationState(position: .hub(focus: module), slots: makeFullSlots())
    let everythingButThisModule = allModulesEnabled.subtracting([module])
    let transition = HubNavigationResolver.transition(
      state, applying: .return, enabledModules: everythingButThisModule
    )
    #expect(transition.next == state)
    #expect(transition.zoom == nil)
  }

  @Test(
    "return with no modules enabled is the identity for every focus",
    arguments: HubModule.allCases
  )
  func returnWithNoModulesEnabledIsTheIdentityForEveryFocus(module: HubModule) {
    let state = makeNavigationState(position: .hub(focus: module), slots: makeFullSlots())
    let transition = HubNavigationResolver.transition(
      state, applying: .return, enabledModules: []
    )
    #expect(transition.next == state)
    #expect(transition.zoom == nil)
  }

  @Test(
    "escape inside a module returns to the hub focused on the entered card with a zoom out for it",
    arguments: HubModule.allCases
  )
  func escapeInsideAModuleReturnsToTheHubFocusedOnTheEnteredCardWithAZoomOutForIt(
    module: HubModule
  ) {
    let state = makeNavigationState(position: .module(module), slots: makeFullSlots())
    let transition = HubNavigationResolver.transition(
      state, applying: .escape, enabledModules: allModulesEnabled
    )
    #expect(transition.next.position == .hub(focus: module))
    #expect(transition.zoom == HubZoom(module: module, direction: .zoomOut))
  }

  @Test(
    "entering then escaping restores the exact starting state for every module",
    arguments: HubModule.allCases
  )
  func enteringThenEscapingRestoresTheExactStartingStateForEveryModule(module: HubModule) {
    let original = makeNavigationState(position: .hub(focus: module), slots: makeFullSlots())
    let entered = HubNavigationResolver.transition(
      original, applying: .return, enabledModules: allModulesEnabled
    ).next
    let left = HubNavigationResolver.transition(
      entered, applying: .escape, enabledModules: allModulesEnabled
    ).next
    #expect(left == original)
  }

  @Test(
    "every key other than escape inside a module is the identity",
    arguments: HubModule.allCases, HubKeyEvent.allCases.filter { $0 != .escape }
  )
  func everyKeyOtherThanEscapeInsideAModuleIsTheIdentity(module: HubModule, key: HubKeyEvent) {
    let state = makeNavigationState(position: .module(module), slots: makeFullSlots())
    let transition = HubNavigationResolver.transition(
      state, applying: key, enabledModules: allModulesEnabled
    )
    #expect(transition.next == state)
    #expect(transition.zoom == nil)
  }

  @Test(
    "escape on the hub is the identity for every focus",
    arguments: HubModule.allCases
  )
  func escapeOnTheHubIsTheIdentityForEveryFocus(focus: HubModule) {
    let state = makeNavigationState(position: .hub(focus: focus), slots: makeFullSlots())
    let transition = HubNavigationResolver.transition(
      state, applying: .escape, enabledModules: allModulesEnabled
    )
    #expect(transition.next == state)
    #expect(transition.zoom == nil)
  }

  @Test(
    "escape still restores focus to the entered card after key presses inside the module",
    arguments: HubModule.allCases
  )
  func escapeStillRestoresFocusToTheEnteredCardAfterKeyPressesInsideTheModule(
    module: HubModule
  ) {
    var state = HubNavigationResolver.transition(
      makeNavigationState(position: .hub(focus: module), slots: makeFullSlots()),
      applying: .return,
      enabledModules: allModulesEnabled
    ).next
    let keysInsideTheModule: [HubKeyEvent] = [
      .arrowUp, .arrowDown, .arrowLeft, .arrowRight, .return
    ]
    for key in keysInsideTheModule {
      state = HubNavigationResolver.transition(
        state, applying: key, enabledModules: allModulesEnabled
      ).next
    }
    let left = HubNavigationResolver.transition(
      state, applying: .escape, enabledModules: allModulesEnabled
    )
    #expect(left.next.position == .hub(focus: module))
    #expect(left.zoom == HubZoom(module: module, direction: .zoomOut))
  }

  @Test(
    "a zoom is emitted exactly when a module boundary is crossed, over generated key sequences",
    arguments: UInt64(0)..<UInt64(16)
  )
  func aZoomIsEmittedExactlyWhenAModuleBoundaryIsCrossed(seed: UInt64) {
    let keys = makeKeySequence(seed: seed, length: 200, drawnFrom: HubKeyEvent.allCases)
    var state = makeNavigationState(slots: makeFullSlots())
    for key in keys {
      let transition = HubNavigationResolver.transition(
        state, applying: key, enabledModules: allModulesEnabled
      )
      let crossedABoundary = isInsideModule(state) != isInsideModule(transition.next)
      #expect((transition.zoom != nil) == crossedABoundary)
      if let zoom = transition.zoom {
        switch transition.next.position {
        case .module(let entered):
          #expect(zoom == HubZoom(module: entered, direction: .zoomIn))
        case .hub(let focus):
          #expect(zoom == HubZoom(module: focus, direction: .zoomOut))
        }
      }
      state = transition.next
    }
  }
}
