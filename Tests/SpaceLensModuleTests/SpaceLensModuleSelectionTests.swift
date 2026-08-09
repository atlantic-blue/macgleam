import Foundation
import GleamCore
import SpaceLensModule
import Testing

@MainActor
@Suite("Space lens module selection")
struct SpaceLensModuleSelectionTests {

  @Test("toggling a selectable node selects it and the byte total is the exact sum")
  func togglingSelectsWithAnExactByteTotal() async throws {
    let harness = makeSpaceLensHarness()
    _ = try #require(await reachBrowsing(harness))

    harness.model.toggleSelection(LensModuleFixture.filmFile)
    harness.model.toggleSelection(LensModuleFixture.documentsDirectory)

    let map = try #require(browsingState(harness.model))
    #expect(
      map.selectedPaths == [LensModuleFixture.filmFile, LensModuleFixture.documentsDirectory])
    #expect(
      map.selectedByteTotal
        == LensModuleFixture.filmBytes + LensModuleFixture.documentsBytes)
  }

  @Test("toggling a selected node deselects it")
  func togglingASelectedNodeDeselects() async throws {
    let harness = makeSpaceLensHarness()
    _ = try #require(await reachBrowsing(harness))
    harness.model.toggleSelection(LensModuleFixture.filmFile)

    harness.model.toggleSelection(LensModuleFixture.filmFile)

    let map = try #require(browsingState(harness.model))
    #expect(map.selectedPaths.isEmpty)
    #expect(map.selectedByteTotal == 0)
  }

  @Test("selecting an ancestor removes its selected descendants: the ancestor covers them")
  func selectingAnAncestorRemovesSelectedDescendants() async throws {
    let harness = makeSpaceLensHarness()
    _ = try #require(await reachBrowsing(harness))
    harness.model.toggleSelection(LensModuleFixture.filmFile)
    harness.model.toggleSelection(LensModuleFixture.clipFile)

    harness.model.toggleSelection(LensModuleFixture.mediaDirectory)

    let map = try #require(browsingState(harness.model))
    #expect(map.selectedPaths == [LensModuleFixture.mediaDirectory])
    #expect(map.selectedByteTotal == LensModuleFixture.mediaBytes)
  }

  @Test("toggling a path covered by a selected ancestor is the identity")
  func togglingACoveredDescendantIsTheIdentity() async throws {
    let harness = makeSpaceLensHarness()
    _ = try #require(await reachBrowsing(harness))
    harness.model.toggleSelection(LensModuleFixture.mediaDirectory)
    let before = snapshot(harness.model)

    harness.model.toggleSelection(LensModuleFixture.filmFile)

    #expect(snapshot(harness.model) == before)
  }

  @Test("toggling a denylisted node is the identity")
  func togglingADenylistedNodeIsTheIdentity() async throws {
    let harness = makeSpaceLensHarness()
    _ = try #require(await reachBrowsing(harness))
    let before = snapshot(harness.model)

    harness.model.toggleSelection(LensModuleFixture.protectedDirectory)

    #expect(snapshot(harness.model) == before)
  }

  @Test("toggling the volume root is the identity")
  func togglingTheVolumeRootIsTheIdentity() async throws {
    let harness = makeSpaceLensHarness()
    _ = try #require(await reachBrowsing(harness))
    let before = snapshot(harness.model)

    harness.model.toggleSelection(LensModuleFixture.volume)

    #expect(snapshot(harness.model) == before)
  }

  @Test("toggling a path missing from the tree is the identity")
  func togglingAnUnknownPathIsTheIdentity() async throws {
    let harness = makeSpaceLensHarness()
    _ = try #require(await reachBrowsing(harness))
    let before = snapshot(harness.model)

    harness.model.toggleSelection(LensModuleFixture.path("/Volumes/Lens/Ghost"))

    #expect(snapshot(harness.model) == before)
  }

  @Test("the selection stays an antichain under every adversarial toggle sequence")
  func selectionStaysAnAntichain() async throws {
    let harness = makeSpaceLensHarness()
    _ = try #require(await reachBrowsing(harness))

    for path in [
      LensModuleFixture.filmFile,
      LensModuleFixture.mediaDirectory,
      LensModuleFixture.clipFile,
      LensModuleFixture.documentsDirectory,
      LensModuleFixture.volume,
      LensModuleFixture.protectedDirectory,
      LensModuleFixture.filmFile,
      LensModuleFixture.mediaDirectory,
    ] {
      harness.model.toggleSelection(path)
      let map = try #require(browsingState(harness.model))
      for selected in map.selectedPaths {
        for other in map.selectedPaths where other != selected {
          #expect(
            !selected.isDescendant(of: other),
            "\(selected.value) is covered by selected ancestor \(other.value)")
        }
      }
    }
  }

  @Test("selection works while the map is still streaming")
  func selectionWorksWhileMapping() async throws {
    let harness = makeSpaceLensHarness()
    let feed = await beginMapping(harness)
    sendStandardTree(feed)
    await expectEventually("the tree arrives") {
      mappingState(harness.model)?.root != nil
    }

    harness.model.toggleSelection(LensModuleFixture.filmFile)

    let map = try #require(mappingState(harness.model))
    #expect(map.selectedPaths == [LensModuleFixture.filmFile])
  }
}
