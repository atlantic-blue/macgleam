import CleanupModule
import Foundation
import GleamCore
import GleamHub
import Testing

let presentableCategories: [FindingCategory] = [
  .userCache,
  .log,
  .browserCache,
  .trashBin(volume: AbsolutePath(normalising: "/")),
  .duplicateSet(keptPath: AbsolutePath(normalising: "/Users/x/keep.txt")),
]

/// The collapsed categories are the state the pane owns and the rail
/// destroys: the rail tears the pane down on the way out and builds a fresh
/// one on the way back, so without a slot every category springs open again.
@MainActor
@Suite("Cleanup presentation state")
struct CleanupPresentationTests {

  @Test("a category starts expanded and toggles both ways", arguments: presentableCategories)
  func aCategoryStartsExpandedAndTogglesBothWays(category: FindingCategory) {
    let presentation = CleanupPresentation()
    #expect(!presentation.isCollapsed(category))
    presentation.toggleCollapse(category)
    #expect(presentation.isCollapsed(category))
    presentation.toggleCollapse(category)
    #expect(!presentation.isCollapsed(category))
  }

  @Test("collapsing one category leaves every other one alone")
  func collapsingOneCategoryLeavesEveryOtherOneAlone() {
    let presentation = CleanupPresentation()
    presentation.toggleCollapse(.log)
    for category in presentableCategories where category != .log {
      #expect(!presentation.isCollapsed(category))
    }
  }

  @Test("what was collapsed comes back through a slot, and nothing else does")
  func whatWasCollapsedComesBackThroughASlot() throws {
    let departing = CleanupPresentation()
    departing.toggleCollapse(.userCache)
    departing.toggleCollapse(.trashBin(volume: AbsolutePath(normalising: "/")))
    let slot = try #require(departing.stateSlot())

    let arriving = CleanupPresentation()
    arriving.restoreState(from: slot)
    #expect(arriving.isCollapsed(.userCache))
    #expect(arriving.isCollapsed(.trashBin(volume: AbsolutePath(normalising: "/"))))
    #expect(!arriving.isCollapsed(.log))
    #expect(!arriving.isCollapsed(.browserCache))
  }

  @Test("a slot written with everything expanded expands everything again")
  func aSlotWrittenWithEverythingExpandedExpandsEverythingAgain() throws {
    let departing = CleanupPresentation()
    let slot = try #require(departing.stateSlot())

    let arriving = CleanupPresentation()
    arriving.toggleCollapse(.log)
    arriving.toggleCollapse(.userCache)
    arriving.restoreState(from: slot)
    #expect(!arriving.isCollapsed(.log))
    #expect(!arriving.isCollapsed(.userCache))
  }

  @Test("the module always offers a slot, so a stale one can never be restored")
  func theModuleAlwaysOffersASlot() {
    #expect(CleanupPresentation().stateSlot() != nil)
  }

  @Test("a payload the module cannot read leaves it exactly as it was")
  func aPayloadTheModuleCannotReadLeavesItExactlyAsItWas() {
    let presentation = CleanupPresentation()
    presentation.toggleCollapse(.log)
    presentation.restoreState(from: ModuleStateSlot(payload: Data("not json".utf8)))
    #expect(presentation.isCollapsed(.log))
    #expect(!presentation.isCollapsed(.userCache))
  }

  @Test("an empty payload leaves it exactly as it was")
  func anEmptyPayloadLeavesItExactlyAsItWas() {
    let presentation = CleanupPresentation()
    presentation.toggleCollapse(.log)
    presentation.restoreState(from: ModuleStateSlot(payload: Data()))
    #expect(presentation.isCollapsed(.log))
  }

  @Test("a category collapsed on the way out is still collapsed on the way back")
  func aCategoryCollapsedOnTheWayOutIsStillCollapsedOnTheWayBack() {
    let presentation = CleanupPresentation()
    presentation.toggleCollapse(.userCache)
    presentation.toggleCollapse(.log)

    var navigation = HubNavigationState(
      selection: .module(.cleanup), moduleStateSlots: [:])
    let preservers: [HubModule: any ModuleStatePreserving] = [.cleanup: presentation]
    for destination in [HubDestination.diskMap, .settings, .module(.protection)] {
      navigation = ModuleStateExchange.navigate(
        navigation, to: destination, preservers: preservers)
    }
    // The pane is torn down while away, so the state the user sees on return
    // is a fresh one that has only ever seen the slot.
    let rebuilt = CleanupPresentation()
    navigation = ModuleStateExchange.navigate(
      navigation, to: .module(.cleanup), preservers: [.cleanup: rebuilt])

    #expect(navigation.selection == .module(.cleanup))
    #expect(rebuilt.isCollapsed(.userCache))
    #expect(rebuilt.isCollapsed(.log))
    #expect(!rebuilt.isCollapsed(.browserCache))
  }

  @Test("expanding a category before leaving means it is expanded on return")
  func expandingACategoryBeforeLeavingMeansItIsExpandedOnReturn() {
    let presentation = CleanupPresentation()
    presentation.toggleCollapse(.userCache)
    var navigation = HubNavigationState(
      selection: .module(.cleanup), moduleStateSlots: [:])
    navigation = ModuleStateExchange.navigate(
      navigation, to: .diskMap, preservers: [.cleanup: presentation])

    presentation.restoreState(from: ModuleStateSlot(payload: Data()))
    let secondVisit = CleanupPresentation()
    navigation = ModuleStateExchange.navigate(
      navigation, to: .module(.cleanup), preservers: [.cleanup: secondVisit])
    #expect(secondVisit.isCollapsed(.userCache))

    secondVisit.toggleCollapse(.userCache)
    navigation = ModuleStateExchange.navigate(
      navigation, to: .settings, preservers: [.cleanup: secondVisit])
    let thirdVisit = CleanupPresentation()
    navigation = ModuleStateExchange.navigate(
      navigation, to: .module(.cleanup), preservers: [.cleanup: thirdVisit])
    #expect(!thirdVisit.isCollapsed(.userCache))
  }
}
