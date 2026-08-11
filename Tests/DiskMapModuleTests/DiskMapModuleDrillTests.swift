import DiskMapModule
import Foundation
import GleamCore
import GleamDesign
import GleamHub
import Testing

@MainActor
@Suite("Space lens module drill")
struct DiskMapModuleDrillTests {

  @Test("drilling into a directory child of the focus moves the focus and zooms in")
  func drillingIntoADirectoryChildZoomsIn() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachBrowsing(harness))

    let drill = try #require(harness.model.drillIn(to: LensModuleFixture.mediaDirectory))
    #expect(drill.target == LensModuleFixture.mediaDirectory)
    #expect(drill.direction == .zoomIn)
    #expect(browsingState(harness.model)?.focusPath == LensModuleFixture.mediaDirectory)
  }

  @Test("drilling into a file returns nil and changes nothing")
  func drillingIntoAFileIsRefused() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachBrowsing(harness))
    _ = harness.model.drillIn(to: LensModuleFixture.mediaDirectory)
    let before = snapshot(harness.model)

    #expect(harness.model.drillIn(to: LensModuleFixture.filmFile) == nil)
    #expect(snapshot(harness.model) == before)
  }

  @Test("drilling into a directory that is not a child of the focus returns nil")
  func drillingPastTheFocusIsRefused() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachBrowsing(harness))
    _ = harness.model.drillIn(to: LensModuleFixture.mediaDirectory)
    let before = snapshot(harness.model)

    #expect(harness.model.drillIn(to: LensModuleFixture.documentsDirectory) == nil)
    #expect(snapshot(harness.model) == before)
  }

  @Test("drilling into a path missing from the tree returns nil")
  func drillingIntoAnUnknownPathIsRefused() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachBrowsing(harness))
    let before = snapshot(harness.model)

    #expect(harness.model.drillIn(to: LensModuleFixture.path("/Volumes/Lens/Ghost")) == nil)
    #expect(snapshot(harness.model) == before)
  }

  @Test("drilling out moves the focus to its parent and zooms out")
  func drillingOutZoomsOutToTheParent() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachBrowsing(harness))
    _ = harness.model.drillIn(to: LensModuleFixture.mediaDirectory)

    let drill = try #require(harness.model.drillOut())
    #expect(drill.target == LensModuleFixture.volume)
    #expect(drill.direction == .zoomOut)
    #expect(browsingState(harness.model)?.focusPath == LensModuleFixture.volume)
  }

  @Test("drilling out at the volume root returns nil: leaving is the chrome's job")
  func drillingOutAtTheRootIsRefused() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachBrowsing(harness))
    let before = snapshot(harness.model)

    #expect(harness.model.drillOut() == nil)
    #expect(snapshot(harness.model) == before)
  }

  @Test("drilling works while the map is still streaming")
  func drillingWorksWhileMapping() async throws {
    let harness = makeDiskMapHarness()
    let feed = await beginMapping(harness)
    sendStandardTree(feed)
    await expectEventually("the tree arrives") {
      mappingState(harness.model)?.root != nil
    }

    let drill = try #require(harness.model.drillIn(to: LensModuleFixture.mediaDirectory))
    #expect(drill.direction == .zoomIn)
    #expect(mappingState(harness.model)?.focusPath == LensModuleFixture.mediaDirectory)
    let out = try #require(harness.model.drillOut())
    #expect(out.direction == .zoomOut)
    #expect(mappingState(harness.model)?.focusPath == LensModuleFixture.volume)
  }

  @Test(
    "drill directions resolve through the shared hub zoom grammar: snappy matched geometry, crossfade under Reduce Motion"
  )
  func drillDirectionsResolveThroughTheHubZoomGrammar() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachBrowsing(harness))
    let inDrill = try #require(harness.model.drillIn(to: LensModuleFixture.mediaDirectory))
    let outDrill = try #require(harness.model.drillOut())

    for direction in [inDrill.direction, outDrill.direction] {
      #expect(
        HubZoomResolver.appearance(for: direction, reduceMotion: false)
          == .matchedGeometry(spring: .snappy))
      #expect(
        HubZoomResolver.appearance(for: direction, reduceMotion: true)
          == .crossfade(fade: .standard))
    }
  }
}
