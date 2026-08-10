import DiskMapEngine
import DiskMapModule
import Foundation
import GleamCore
import Testing

@MainActor
@Suite("Disk map module tree")
struct DiskMapModuleTreeTests {

  @Test("node updates grow the published tree under the streamed structure")
  func nodeUpdatesGrowThePublishedTree() async throws {
    let harness = makeDiskMapHarness()
    let feed = await beginMapping(harness)
    sendStandardTree(feed)
    await expectEventually("the tree arrives") {
      mappingState(harness.model)?.root != nil
    }

    let root = try #require(mappingState(harness.model)?.root)
    #expect(root.path == LensModuleFixture.volume)
    #expect(root.isDirectory)
    #expect(root.children.count == 3)

    let media = try #require(findNode(root, at: LensModuleFixture.mediaDirectory))
    #expect(media.children.map(\.path) == [LensModuleFixture.filmFile, LensModuleFixture.clipFile])
    #expect(findNode(root, at: LensModuleFixture.documentsDirectory) != nil)
    #expect(findNode(root, at: LensModuleFixture.protectedDirectory) != nil)
  }

  @Test("children sort by allocated bytes descending")
  func childrenSortByBytesDescending() async throws {
    let harness = makeDiskMapHarness()
    let feed = await beginMapping(harness)
    sendStandardTree(feed)
    await expectEventually("the revisions arrive") {
      findNode(mappingState(harness.model)?.root, at: LensModuleFixture.mediaDirectory)?
        .allocatedBytesSoFar == LensModuleFixture.mediaBytes
    }

    let root = try #require(mappingState(harness.model)?.root)
    #expect(
      root.children.map(\.path) == [
        LensModuleFixture.mediaDirectory,
        LensModuleFixture.documentsDirectory,
        LensModuleFixture.protectedDirectory,
      ])
    #expect(
      root.children.map(\.allocatedBytesSoFar) == [
        LensModuleFixture.mediaBytes,
        LensModuleFixture.documentsBytes,
        LensModuleFixture.protectedBytes,
      ])
  }

  @Test("equal byte totals tie break lexicographically by path")
  func equalTotalsTieBreakLexicographically() async throws {
    let harness = makeDiskMapHarness()
    let feed = await beginMapping(harness)
    let archive = LensModuleFixture.path("/Volumes/Lens/Archive")
    feed.send(
      .node(
        LensModuleFixture.node(
          LensModuleFixture.volume, parent: nil, isDirectory: true, subtreeBytes: 0)),
      .node(
        LensModuleFixture.node(
          LensModuleFixture.documentsDirectory, parent: LensModuleFixture.volume,
          isDirectory: true, subtreeBytes: 1_500)),
      .node(
        LensModuleFixture.node(
          archive, parent: LensModuleFixture.volume,
          isDirectory: true, subtreeBytes: 1_500))
    )
    await expectEventually("both children arrive") {
      mappingState(harness.model)?.root?.children.count == 2
    }

    let root = try #require(mappingState(harness.model)?.root)
    #expect(root.children.map(\.path) == [archive, LensModuleFixture.documentsDirectory])
  }

  @Test("a size revision only ever raises a node's published total")
  func sizeRevisionsOnlyRaiseTotals() async throws {
    let harness = makeDiskMapHarness()
    let feed = await beginMapping(harness)
    feed.send(
      .node(
        LensModuleFixture.node(
          LensModuleFixture.volume, parent: nil, isDirectory: true, subtreeBytes: 0)),
      .node(
        LensModuleFixture.node(
          LensModuleFixture.mediaDirectory, parent: LensModuleFixture.volume,
          isDirectory: true, subtreeBytes: 0))
    )
    await expectEventually("the media node arrives") {
      findNode(mappingState(harness.model)?.root, at: LensModuleFixture.mediaDirectory) != nil
    }
    let beforeRevision = try #require(
      findNode(mappingState(harness.model)?.root, at: LensModuleFixture.mediaDirectory))

    feed.send(
      .sizeRevision(path: LensModuleFixture.mediaDirectory, subtreeBytes: 9_000))
    await expectEventually("the revision lands") {
      findNode(mappingState(harness.model)?.root, at: LensModuleFixture.mediaDirectory)?
        .allocatedBytesSoFar == 9_000
    }
    let afterRevision = try #require(
      findNode(mappingState(harness.model)?.root, at: LensModuleFixture.mediaDirectory))

    #expect(beforeRevision.allocatedBytesSoFar <= afterRevision.allocatedBytesSoFar)
    #expect(afterRevision.allocatedBytesSoFar == 9_000)
  }

  @Test("no node claims convergence while the stream is still running")
  func noNodeConvergesWhileMapping() async throws {
    let harness = makeDiskMapHarness()
    let feed = await beginMapping(harness)
    sendStandardTree(feed)
    await expectEventually("the tree arrives") {
      mappingState(harness.model)?.root != nil
    }

    let root = try #require(mappingState(harness.model)?.root)
    for node in everyNode(root) {
      #expect(node.hasConverged == false, "\(node.path.value) converged mid stream")
    }
  }

  @Test("when the stream completes every node has converged at the engine's final total")
  func completionConvergesEveryNode() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachBrowsing(harness))

    let root = try #require(browsingState(harness.model)?.root)
    for node in everyNode(root) {
      #expect(node.hasConverged, "\(node.path.value) never converged")
    }
    #expect(root.allocatedBytesSoFar == LensModuleFixture.volumeBytes)
    let media = try #require(findNode(root, at: LensModuleFixture.mediaDirectory))
    #expect(media.allocatedBytesSoFar == LensModuleFixture.mediaBytes)
    let film = try #require(findNode(root, at: LensModuleFixture.filmFile))
    #expect(film.allocatedBytesSoFar == LensModuleFixture.filmBytes)
  }

  @Test("a denylisted node renders in the tree but is not selectable")
  func denylistedNodeRendersUnselectable() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachBrowsing(harness))

    let root = try #require(browsingState(harness.model)?.root)
    let protected = try #require(findNode(root, at: LensModuleFixture.protectedDirectory))
    #expect(protected.isSelectable == false)
  }

  @Test("the volume root is never selectable even when the engine offers it")
  func volumeRootIsNeverSelectable() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachBrowsing(harness))

    let root = try #require(browsingState(harness.model)?.root)
    #expect(root.isSelectable == false)
  }

  @Test("nodes the engine offers stay selectable")
  func offeredNodesStaySelectable() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachBrowsing(harness))

    let root = try #require(browsingState(harness.model)?.root)
    for path in [
      LensModuleFixture.mediaDirectory,
      LensModuleFixture.filmFile,
      LensModuleFixture.documentsDirectory,
    ] {
      let node = try #require(findNode(root, at: path))
      #expect(node.isSelectable, "\(path.value) should be selectable")
    }
  }
}
