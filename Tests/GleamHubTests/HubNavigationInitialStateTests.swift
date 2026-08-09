import Foundation
import GleamHub
import Testing

@Suite("Hub navigation initial state")
struct HubNavigationInitialStateTests {

  @Test("initial sits on the hub with focus on the first card in the layout order")
  func initialSitsOnTheHubWithFocusOnTheFirstCardInTheLayoutOrder() {
    #expect(HubModule.allCases.first == .smartCare)
    #expect(HubNavigationState.initial.position == .hub(focus: .smartCare))
  }

  @Test("initial carries no stored module slots")
  func initialCarriesNoStoredModuleSlots() {
    #expect(HubNavigationState.initial.moduleStateSlots.isEmpty)
  }
}
