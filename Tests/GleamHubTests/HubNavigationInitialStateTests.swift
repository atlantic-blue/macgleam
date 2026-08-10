import Foundation
import GleamHub
import Testing

@Suite("Hub navigation initial state")
struct HubNavigationInitialStateTests {

  @Test("the app opens on the first destination in rail order")
  func theAppOpensOnTheFirstDestinationInRailOrder() {
    #expect(HubDestination.allCases.first == .module(.smartCare))
    #expect(HubNavigationState.initial.selection == .module(.smartCare))
  }

  @Test("initial carries no stored module slots")
  func initialCarriesNoStoredModuleSlots() {
    #expect(HubNavigationState.initial.moduleStateSlots.isEmpty)
  }
}
