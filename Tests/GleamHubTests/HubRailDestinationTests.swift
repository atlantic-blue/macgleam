import Foundation
import GleamHub
import Testing

@Suite("The rail")
struct HubRailDestinationTests {

  @Test("the rail is every module in order, then the disk map, then settings")
  func theRailIsEveryModuleInOrderThenTheDiskMapThenSettings() {
    #expect(
      HubDestination.allCases == [
        .module(.fullSweep),
        .module(.cleanup),
        .module(.protection),
        .module(.performance),
        .module(.applications),
        .module(.leftovers),
        .diskMap,
        .settings,
      ])
  }

  @Test("HubModule.allCases is the fixed rail order for modules")
  func hubModuleAllCasesIsTheFixedRailOrder() {
    #expect(
      HubModule.allCases == [
        .fullSweep, .cleanup, .protection, .performance, .applications, .leftovers,
      ])
  }

  @Test("the work group holds everything except settings", arguments: HubDestination.allCases)
  func theWorkGroupHoldsEverythingExceptSettings(destination: HubDestination) {
    #expect(destination.group == (destination == .settings ? .apart : .work))
  }

  @Test("the work group is contiguous and comes first")
  func theWorkGroupIsContiguousAndComesFirst() {
    let groups = HubDestination.allCases.map(\.group)
    #expect(groups == groups.sorted { first, _ in first == .work })
    #expect(groups.first == .work)
  }

  @Test("every destination has a title and a symbol", arguments: HubDestination.allCases)
  func everyDestinationHasATitleAndASymbol(destination: HubDestination) {
    #expect(!destination.title.isEmpty)
    #expect(!destination.symbolName.isEmpty)
  }

  @Test("no two destinations share a title or a symbol")
  func noTwoDestinationsShareATitleOrASymbol() {
    #expect(Set(HubDestination.allCases.map(\.title)).count == HubDestination.allCases.count)
    #expect(Set(HubDestination.allCases.map(\.symbolName)).count == HubDestination.allCases.count)
  }

  @Test("every module says in one sentence what it is for", arguments: HubModule.allCases)
  func everyModuleSaysInOneSentenceWhatItIsFor(module: HubModule) {
    #expect(module.summarySentence.hasSuffix("."))
    #expect(module.summarySentence.count > 20)
  }

  /// The hexagon refused to enter a module that was not built. The rail does
  /// not: every destination selects, and the pane is where a module admits it
  /// has nothing to offer yet.
  @Test("a module that is not built is still selectable", arguments: HubModule.allCases)
  func aModuleThatIsNotBuiltIsStillSelectable(module: HubModule) {
    let above = makeNavigationState(selection: .module(.fullSweep))
    var state = above
    while state.selection != .module(module) {
      let next = HubNavigationResolver.transition(state, applying: .arrowDown).next
      #expect(next != state, "the rail stopped before reaching \(module)")
      state = next
    }
    #expect(state.selection == .module(module))
  }
}
