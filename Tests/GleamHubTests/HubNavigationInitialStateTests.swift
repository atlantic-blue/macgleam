import Foundation
import GleamHub
import Testing

@Suite("Hub navigation initial state")
struct HubNavigationInitialStateTests {

  @Test("the app opens on the first destination in rail order")
  func theAppOpensOnTheFirstDestinationInRailOrder() {
    #expect(HubDestination.allCases.first == .module(.fullSweep))
    #expect(HubNavigationState.initial.selection == .module(.fullSweep))
  }

  @Test("initial carries no stored module slots")
  func initialCarriesNoStoredModuleSlots() {
    #expect(HubNavigationState.initial.moduleStateSlots.isEmpty)
  }
}
