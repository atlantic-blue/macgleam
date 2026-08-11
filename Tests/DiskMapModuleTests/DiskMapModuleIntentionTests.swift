import DiskMapEngine
import DiskMapModule
import Foundation
import GleamCore
import Testing

// The C39 amendment: while mapping, drillIn and toggleSelection accept paths
// whose nodes have not streamed yet as intentions, reconciled onto nodes as
// they arrive and pruned at completion; an intention resolving to a
// denylisted node or the volume root is dropped at resolution; unresolved
// intentions contribute nothing to selectedByteTotal; on completion pruning,
// focus falls back to the deepest streamed ancestor.

@MainActor
private func sendRoot(_ feed: MapFeed) {
  feed.send(
    .node(
      LensModuleFixture.node(
        LensModuleFixture.volume, parent: nil, isDirectory: true, subtreeBytes: 0)))
}

@MainActor
private func sendChildrenAndRevisions(_ feed: MapFeed) {
  feed.send(
    .node(
      LensModuleFixture.node(
        LensModuleFixture.mediaDirectory, parent: LensModuleFixture.volume,
        isDirectory: true, subtreeBytes: 0)),
    .node(
      LensModuleFixture.node(
        LensModuleFixture.filmFile, parent: LensModuleFixture.mediaDirectory,
        isDirectory: false, subtreeBytes: LensModuleFixture.filmBytes)),
    .node(
      LensModuleFixture.node(
        LensModuleFixture.clipFile, parent: LensModuleFixture.mediaDirectory,
        isDirectory: false, subtreeBytes: LensModuleFixture.clipBytes)),
    .node(
      LensModuleFixture.node(
        LensModuleFixture.documentsDirectory, parent: LensModuleFixture.volume,
        isDirectory: true, subtreeBytes: LensModuleFixture.documentsBytes)),
    .node(
      LensModuleFixture.node(
        LensModuleFixture.protectedDirectory, parent: LensModuleFixture.volume,
        isDirectory: true, subtreeBytes: LensModuleFixture.protectedBytes,
        isSelectable: false)),
    .sizeRevision(
      path: LensModuleFixture.mediaDirectory, subtreeBytes: LensModuleFixture.mediaBytes),
    .sizeRevision(
      path: LensModuleFixture.volume, subtreeBytes: LensModuleFixture.volumeBytes)
  )
}

@MainActor
@Suite("Space lens module intentions while mapping")
struct DiskMapModuleIntentionTests {

  @Test(
    "a selection intention for an unstreamed path counts nothing until its node arrives, then survives into browsing with its converged bytes"
  )
  func aSelectionIntentionResolvesWhenItsNodeArrives() async throws {
    let harness = makeDiskMapHarness()
    let feed = await beginMapping(harness)
    sendRoot(feed)
    await expectEventually("the root arrives") {
      mappingState(harness.model)?.root != nil
    }

    harness.model.toggleSelection(LensModuleFixture.filmFile)
    await settleBriefly()
    let unresolved = try #require(mappingState(harness.model))
    #expect(unresolved.selectedByteTotal == 0, "an unresolved intention contributes nothing")

    sendChildrenAndRevisions(feed)
    await expectEventually("the intention resolves onto the arrived node") {
      mappingState(harness.model)?.selectedByteTotal == LensModuleFixture.filmBytes
    }

    feed.send(.completed)
    feed.finish()
    await expectEventually("the model reaches browsing") {
      browsingState(harness.model) != nil
    }
    let browsing = try #require(browsingState(harness.model))
    #expect(browsing.selectedPaths == [LensModuleFixture.filmFile])
    #expect(browsing.selectedByteTotal == LensModuleFixture.filmBytes)
  }

  @Test(
    "a drill intention for an unstreamed directory returns the drill and the focus lands on the node once it arrives"
  )
  func aDrillIntentionLandsOnTheNodeOnceItArrives() async throws {
    let harness = makeDiskMapHarness()
    let feed = await beginMapping(harness)
    sendRoot(feed)
    await expectEventually("the root arrives") {
      mappingState(harness.model)?.root != nil
    }

    let drill = try #require(harness.model.drillIn(to: LensModuleFixture.mediaDirectory))
    #expect(drill.target == LensModuleFixture.mediaDirectory)
    #expect(drill.direction == .zoomIn)
    #expect(mappingState(harness.model)?.focusPath == LensModuleFixture.mediaDirectory)

    sendChildrenAndRevisions(feed)
    await expectEventually("the focused node arrives in the tree") {
      findNode(mappingState(harness.model)?.root, at: LensModuleFixture.mediaDirectory) != nil
    }
    #expect(mappingState(harness.model)?.focusPath == LensModuleFixture.mediaDirectory)

    feed.send(.completed)
    feed.finish()
    await expectEventually("the model reaches browsing") {
      browsingState(harness.model) != nil
    }
    let browsing = try #require(browsingState(harness.model))
    #expect(browsing.focusPath == LensModuleFixture.mediaDirectory)
    #expect(findNode(browsing.root, at: LensModuleFixture.mediaDirectory) != nil)
  }

  @Test(
    "an intention whose path never streams is pruned at completion: absent in browsing, bytes unaffected, focus fallen back to the deepest streamed ancestor"
  )
  func anUnmatchedIntentionIsPrunedAtCompletion() async throws {
    let harness = makeDiskMapHarness()
    let feed = await beginMapping(harness)
    sendStandardTree(feed)
    await expectEventually("the tree arrives") {
      findNode(mappingState(harness.model)?.root, at: LensModuleFixture.mediaDirectory) != nil
    }

    harness.model.toggleSelection(LensModuleFixture.filmFile)
    harness.model.toggleSelection(LensModuleFixture.path("/Volumes/Lens/Media/ghost.bin"))
    _ = try #require(harness.model.drillIn(to: LensModuleFixture.mediaDirectory))
    let archive = LensModuleFixture.path("/Volumes/Lens/Media/archive")
    let intentionDrill = try #require(harness.model.drillIn(to: archive))
    #expect(intentionDrill.direction == .zoomIn)
    #expect(mappingState(harness.model)?.focusPath == archive)
    await settleBriefly()
    #expect(
      mappingState(harness.model)?.selectedByteTotal == LensModuleFixture.filmBytes,
      "the ghost intention contributes nothing while unresolved")

    feed.send(.completed)
    feed.finish()
    await expectEventually("the model reaches browsing") {
      browsingState(harness.model) != nil
    }
    let browsing = try #require(browsingState(harness.model))
    #expect(browsing.selectedPaths == [LensModuleFixture.filmFile])
    #expect(browsing.selectedByteTotal == LensModuleFixture.filmBytes)
    #expect(
      browsing.focusPath == LensModuleFixture.mediaDirectory,
      "focus falls back to the deepest streamed ancestor of the pruned intention")
  }

  @Test("a selection intention resolving to a denylisted node is dropped at resolution")
  func anIntentionResolvingToADenylistedNodeIsDropped() async throws {
    let harness = makeDiskMapHarness()
    let feed = await beginMapping(harness)
    sendRoot(feed)
    await expectEventually("the root arrives") {
      mappingState(harness.model)?.root != nil
    }

    harness.model.toggleSelection(LensModuleFixture.protectedDirectory)
    await settleBriefly()
    #expect(mappingState(harness.model)?.selectedByteTotal == 0)

    sendChildrenAndRevisions(feed)
    await expectEventually("the denylisted node arrives") {
      findNode(mappingState(harness.model)?.root, at: LensModuleFixture.protectedDirectory)
        != nil
    }
    await settleBriefly()
    #expect(
      mappingState(harness.model)?.selectedByteTotal == 0,
      "a denylisted resolution must never be counted")

    feed.send(.completed)
    feed.finish()
    await expectEventually("the model reaches browsing") {
      browsingState(harness.model) != nil
    }
    let browsing = try #require(browsingState(harness.model))
    #expect(browsing.selectedPaths.isEmpty)
    #expect(browsing.selectedByteTotal == 0)
  }

  @Test("a selection intention resolving to the volume root is dropped at resolution")
  func anIntentionResolvingToTheVolumeRootIsDropped() async throws {
    let harness = makeDiskMapHarness()
    let feed = await beginMapping(harness)

    harness.model.toggleSelection(LensModuleFixture.volume)
    await settleBriefly()

    sendStandardTree(feed)
    await expectEventually("the root arrives") {
      mappingState(harness.model)?.root != nil
    }
    await settleBriefly()
    #expect(
      mappingState(harness.model)?.selectedByteTotal == 0,
      "the volume root must never be counted, whatever the engine claims")

    feed.send(.completed)
    feed.finish()
    await expectEventually("the model reaches browsing") {
      browsingState(harness.model) != nil
    }
    let browsing = try #require(browsingState(harness.model))
    #expect(browsing.selectedPaths.isEmpty)
    #expect(browsing.selectedByteTotal == 0)
  }
}
