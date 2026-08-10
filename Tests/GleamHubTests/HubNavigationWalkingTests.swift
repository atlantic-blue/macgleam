import Foundation
import GleamHub
import Testing

@Suite("Hub arrow walking")
struct HubArrowWalkingTests {

  @Test(
    "the two columns follow the HubModule.allCases order: fullSweep, cleanup, protection on the left, performance, applications, leftovers on the right"
  )
  func theTwoColumnsFollowTheAllCasesOrder() {
    #expect(HubModule.allCases == leftColumnTopToBottom + rightColumnTopToBottom)
  }

  @Test(
    "arrowDown moves focus one row down within the same column",
    arguments: zip(
      [HubModule.fullSweep, .cleanup, .performance, .applications],
      [HubModule.cleanup, .protection, .applications, .leftovers]
    )
  )
  func arrowDownMovesFocusOneRowDownWithinTheSameColumn(from: HubModule, to: HubModule) {
    let state = makeNavigationState(position: .hub(focus: from))
    let transition = HubNavigationResolver.transition(
      state, applying: .arrowDown, enabledModules: allModulesEnabled
    )
    #expect(transition.next.position == .hub(focus: to))
    #expect(transition.zoom == nil)
  }

  @Test(
    "arrowUp moves focus one row up within the same column",
    arguments: zip(
      [HubModule.cleanup, .protection, .applications, .leftovers],
      [HubModule.fullSweep, .cleanup, .performance, .applications]
    )
  )
  func arrowUpMovesFocusOneRowUpWithinTheSameColumn(from: HubModule, to: HubModule) {
    let state = makeNavigationState(position: .hub(focus: from))
    let transition = HubNavigationResolver.transition(
      state, applying: .arrowUp, enabledModules: allModulesEnabled
    )
    #expect(transition.next.position == .hub(focus: to))
    #expect(transition.zoom == nil)
  }

  @Test(
    "arrowDown at the bottom of a column leaves the state unchanged",
    arguments: [HubModule.protection, .leftovers]
  )
  func arrowDownAtTheBottomOfAColumnLeavesTheStateUnchanged(bottom: HubModule) {
    let state = makeNavigationState(position: .hub(focus: bottom), slots: makeFullSlots())
    let transition = HubNavigationResolver.transition(
      state, applying: .arrowDown, enabledModules: allModulesEnabled
    )
    #expect(transition.next == state)
    #expect(transition.zoom == nil)
  }

  @Test(
    "arrowUp at the top of a column leaves the state unchanged",
    arguments: [HubModule.fullSweep, .performance]
  )
  func arrowUpAtTheTopOfAColumnLeavesTheStateUnchanged(top: HubModule) {
    let state = makeNavigationState(position: .hub(focus: top), slots: makeFullSlots())
    let transition = HubNavigationResolver.transition(
      state, applying: .arrowUp, enabledModules: allModulesEnabled
    )
    #expect(transition.next == state)
    #expect(transition.zoom == nil)
  }

  @Test(
    "arrowRight moves to the same row of the right column",
    arguments: zip(leftColumnTopToBottom, rightColumnTopToBottom)
  )
  func arrowRightMovesToTheSameRowOfTheRightColumn(from: HubModule, to: HubModule) {
    let state = makeNavigationState(position: .hub(focus: from))
    let transition = HubNavigationResolver.transition(
      state, applying: .arrowRight, enabledModules: allModulesEnabled
    )
    #expect(transition.next.position == .hub(focus: to))
    #expect(transition.zoom == nil)
  }

  @Test(
    "arrowLeft moves to the same row of the left column",
    arguments: zip(rightColumnTopToBottom, leftColumnTopToBottom)
  )
  func arrowLeftMovesToTheSameRowOfTheLeftColumn(from: HubModule, to: HubModule) {
    let state = makeNavigationState(position: .hub(focus: from))
    let transition = HubNavigationResolver.transition(
      state, applying: .arrowLeft, enabledModules: allModulesEnabled
    )
    #expect(transition.next.position == .hub(focus: to))
    #expect(transition.zoom == nil)
  }

  @Test(
    "arrowRight when focus is already in the right column leaves the state unchanged",
    arguments: rightColumnTopToBottom
  )
  func arrowRightInTheRightColumnLeavesTheStateUnchanged(focus: HubModule) {
    let state = makeNavigationState(position: .hub(focus: focus), slots: makeFullSlots())
    let transition = HubNavigationResolver.transition(
      state, applying: .arrowRight, enabledModules: allModulesEnabled
    )
    #expect(transition.next == state)
    #expect(transition.zoom == nil)
  }

  @Test(
    "arrowLeft when focus is already in the left column leaves the state unchanged",
    arguments: leftColumnTopToBottom
  )
  func arrowLeftInTheLeftColumnLeavesTheStateUnchanged(focus: HubModule) {
    let state = makeNavigationState(position: .hub(focus: focus), slots: makeFullSlots())
    let transition = HubNavigationResolver.transition(
      state, applying: .arrowLeft, enabledModules: allModulesEnabled
    )
    #expect(transition.next == state)
    #expect(transition.zoom == nil)
  }

  @Test(
    "no arrow key on the hub ever produces a zoom",
    arguments: HubModule.allCases, [HubKeyEvent.arrowUp, .arrowDown, .arrowLeft, .arrowRight]
  )
  func noArrowKeyOnTheHubEverProducesAZoom(focus: HubModule, key: HubKeyEvent) {
    let state = makeNavigationState(position: .hub(focus: focus))
    let transition = HubNavigationResolver.transition(
      state, applying: key, enabledModules: allModulesEnabled
    )
    #expect(transition.zoom == nil)
  }

  @Test(
    "arrow moves are the same whatever the enabled set, since the spatial rules name no enabled condition",
    arguments: HubModule.allCases, [HubKeyEvent.arrowUp, .arrowDown, .arrowLeft, .arrowRight]
  )
  func arrowMovesAreTheSameWhateverTheEnabledSet(focus: HubModule, key: HubKeyEvent) {
    let state = makeNavigationState(position: .hub(focus: focus))
    let withEverythingEnabled = HubNavigationResolver.transition(
      state, applying: key, enabledModules: allModulesEnabled
    )
    let withNothingEnabled = HubNavigationResolver.transition(
      state, applying: key, enabledModules: []
    )
    #expect(withEverythingEnabled == withNothingEnabled)
  }

  @Test(
    "arrow walking from every starting card stays on the hub over generated key sequences",
    arguments: UInt64(0)..<UInt64(16)
  )
  func arrowWalkingFromEveryStartingCardStaysOnTheHubOverGeneratedKeySequences(seed: UInt64) {
    let keys = makeKeySequence(seed: seed, length: 128, drawnFrom: arrowKeys)
    for start in HubModule.allCases {
      var state = makeNavigationState(position: .hub(focus: start), slots: makeFullSlots())
      for key in keys {
        let transition = HubNavigationResolver.transition(
          state, applying: key, enabledModules: allModulesEnabled
        )
        #expect(transition.zoom == nil)
        guard case .hub(let focus) = transition.next.position else {
          Issue.record("arrow walking left the hub from \(start) on \(key)")
          return
        }
        #expect(HubModule.allCases.contains(focus))
        state = transition.next
      }
    }
  }
}
