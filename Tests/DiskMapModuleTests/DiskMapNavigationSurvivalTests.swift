import DiskMapModule
import Foundation
import GleamCore
import GleamHub
import Testing

/// Disk Map is rail chrome rather than a module: `HubModule` has no case for
/// it and the slot store has no key for it (C39). Its state survives a walk
/// through the rail because the model outlives the pane, so what these prove
/// is the other half of the same promise: the exchange, which exists to move
/// module state around, never touches the map on its way past.
@MainActor
@Suite("Disk Map survives a walk through the rail")
struct DiskMapNavigationSurvivalTests {

  private func walkAwayAndBack(
    from state: HubNavigationState,
    preservers: [HubModule: any ModuleStatePreserving] = [:]
  ) -> HubNavigationState {
    var navigation = state
    for destination in [HubDestination.module(.cleanup), .settings, .module(.protection), .diskMap]
    {
      navigation = ModuleStateExchange.navigate(
        navigation, to: destination, preservers: preservers)
    }
    return navigation
  }

  @Test("the drilled in folder and the selection are exactly what they were")
  func theDrilledInFolderAndTheSelectionAreExactlyWhatTheyWere() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachBrowsing(harness))
    _ = harness.model.drillIn(to: LensModuleFixture.mediaDirectory)
    harness.model.toggleSelection(LensModuleFixture.filmFile)
    let before = try #require(browsingState(harness.model))
    #expect(before.focusPath == LensModuleFixture.mediaDirectory)
    #expect(before.selectedPaths.contains(LensModuleFixture.filmFile))

    let navigation = walkAwayAndBack(
      from: HubNavigationState(selection: .diskMap, moduleStateSlots: [:]))

    #expect(navigation.selection == .diskMap)
    #expect(browsingState(harness.model) == before)
  }

  @Test("the map is still usable after the walk, so what came back is live")
  func theMapIsStillUsableAfterTheWalk() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachBrowsing(harness))
    _ = harness.model.drillIn(to: LensModuleFixture.mediaDirectory)

    _ = walkAwayAndBack(from: HubNavigationState(selection: .diskMap, moduleStateSlots: [:]))

    let drill = try #require(harness.model.drillOut())
    #expect(drill.direction == .zoomOut)
    #expect(browsingState(harness.model)?.focusPath == LensModuleFixture.volume)
  }

  @Test("walking the rail never writes a slot for the map")
  func walkingTheRailNeverWritesASlotForTheMap() {
    let navigation = walkAwayAndBack(
      from: HubNavigationState(selection: .diskMap, moduleStateSlots: [:]))
    #expect(navigation.moduleStateSlots.isEmpty)
  }
}
