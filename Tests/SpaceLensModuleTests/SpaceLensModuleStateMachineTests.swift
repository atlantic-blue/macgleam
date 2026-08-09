import Foundation
import GleamCore
import SpaceLensModule
import Testing

@MainActor
@Suite("Space lens module state machine")
struct SpaceLensModuleStateMachineTests {

  @Test("startMapping moves idle to mapping with a fresh session focused on the volume root")
  func startMappingMovesIdleToMapping() async throws {
    let harness = makeSpaceLensHarness()
    _ = await beginMapping(harness)

    let map = try #require(mappingState(harness.model))
    #expect(map.sessionID == LensModuleFixture.sessionA)
    #expect(map.volume == LensModuleFixture.volume)
    #expect(map.root == nil)
    #expect(map.focusPath == LensModuleFixture.volume)
    #expect(map.selectedPaths.isEmpty)
    #expect(map.selectedByteTotal == 0)
    #expect(harness.sessions.minted == [LensModuleFixture.sessionA])
  }

  @Test("startMapping reads the store's settings and the monitor's grant into one scan context")
  func startMappingReadsSettingsAndGrant() async throws {
    let harness = makeSpaceLensHarness(deletionMode: .trash, granted: true)
    let feed = await beginMapping(harness)

    #expect(
      harness.sessions.recordedScanRequests == [
        ScanContextRequest(
          settings: LensModuleFixture.settings(mode: .trash), hasFullDiskAccess: true)
      ])
    #expect(feed.volume == LensModuleFixture.volume)
    #expect(feed.context.sessionID == LensModuleFixture.sessionA)
    #expect(feed.context.hasFullDiskAccess == true)
  }

  @Test("without the grant the scan context says so and the model never opens settings itself")
  func withoutTheGrantTheContextSaysSo() async throws {
    let harness = makeSpaceLensHarness(granted: false)
    let feed = await beginMapping(harness)

    #expect(feed.context.hasFullDiskAccess == false)
    #expect(
      harness.sessions.recordedScanRequests == [
        ScanContextRequest(
          settings: LensModuleFixture.settings(mode: .trash), hasFullDiskAccess: false)
      ])
    #expect(harness.access.openPrivacySettingsCallCount == 0)
  }

  @Test("startMapping while mapping is the identity and mints no session")
  func startMappingWhileMappingIsIgnored() async throws {
    let harness = makeSpaceLensHarness()
    let feed = await beginMapping(harness)
    sendStandardTree(feed)
    await expectEventually("the tree arrives") {
      mappingState(harness.model)?.root != nil
    }
    let before = snapshot(harness.model)

    harness.model.startMapping(volume: LensModuleFixture.volume)
    await settleBriefly()

    #expect(snapshot(harness.model) == before)
    #expect(harness.engine.mapCallCount == 1)
    #expect(harness.sessions.minted.count == 1)
  }

  @Test("startMapping while executing is the identity")
  func startMappingWhileExecutingIsIgnored() async throws {
    let harness = makeSpaceLensHarness()
    _ = try #require(await reachExecuting(harness))
    let before = snapshot(harness.model)

    harness.model.startMapping(volume: LensModuleFixture.volume)
    await settleBriefly()

    #expect(snapshot(harness.model) == before)
    #expect(harness.engine.mapCallCount == 1)
  }

  @Test("startMapping from browsing discards the map and begins a fresh session")
  func startMappingFromBrowsingBeginsAFreshSession() async throws {
    let harness = makeSpaceLensHarness()
    _ = try #require(await reachBrowsing(harness))

    harness.model.startMapping(volume: LensModuleFixture.volume)
    _ = await harness.engine.nextMapFeed()

    let map = try #require(mappingState(harness.model))
    #expect(map.sessionID == LensModuleFixture.sessionB)
    #expect(map.root == nil)
    #expect(harness.engine.mapCallCount == 2)
  }

  @Test("startMapping from result begins a fresh session, never the old map")
  func startMappingFromResultBeginsAFreshSession() async throws {
    let harness = makeSpaceLensHarness()
    _ = try #require(await reachResult(harness))

    harness.model.startMapping(volume: LensModuleFixture.volume)
    _ = await harness.engine.nextMapFeed()

    let map = try #require(mappingState(harness.model))
    #expect(map.sessionID == LensModuleFixture.sessionB)
    #expect(map.root == nil)
  }

  @Test("cancelMapping moves mapping to idle and discards the partial map")
  func cancelMappingDiscardsThePartialMap() async throws {
    let harness = makeSpaceLensHarness()
    let feed = await beginMapping(harness)
    sendStandardTree(feed)
    await expectEventually("the tree arrives") {
      mappingState(harness.model)?.root != nil
    }

    harness.model.cancelMapping()
    #expect(harness.model.state == .idle)

    feed.send(.completed)
    feed.finish()
    await settleBriefly()
    #expect(harness.model.state == .idle)
  }

  @Test("a thrown map stream moves to idle with a plain failure sentence")
  func aThrownStreamMovesToIdleWithANotice() async throws {
    struct MapBroke: Error {}
    let harness = makeSpaceLensHarness()
    let feed = await beginMapping(harness)
    sendStandardTree(feed)

    feed.fail(MapBroke())
    await expectEventually("the model lands on idle") {
      harness.model.state == .idle
    }

    let notice = try #require(harness.model.failureNotice)
    #expect(!notice.isEmpty)
  }

  @Test("the failure notice is cleared by the next startMapping")
  func theFailureNoticeIsClearedByTheNextStart() async throws {
    struct MapBroke: Error {}
    let harness = makeSpaceLensHarness()
    let feed = await beginMapping(harness)
    feed.fail(MapBroke())
    await expectEventually("the notice arrives") {
      harness.model.failureNotice != nil
    }

    harness.model.startMapping(volume: LensModuleFixture.volume)
    _ = await harness.engine.nextMapFeed()
    #expect(harness.model.failureNotice == nil)
  }

  @Test("completed moves mapping to browsing with the identical map state")
  func completedMovesToBrowsingWithTheIdenticalMapState() async throws {
    let harness = makeSpaceLensHarness()
    let feed = await beginMapping(harness)
    sendStandardTree(feed)
    harness.model.drillIn(to: LensModuleFixture.mediaDirectory)
    harness.model.toggleSelection(LensModuleFixture.clipFile)
    await expectEventually("the tree arrives") {
      mappingState(harness.model)?.root != nil
    }

    feed.send(.completed)
    feed.finish()
    await expectEventually("the model reaches browsing") {
      browsingState(harness.model) != nil
    }

    let browsing = try #require(browsingState(harness.model))
    #expect(browsing.focusPath == LensModuleFixture.mediaDirectory)
    #expect(browsing.selectedPaths == [LensModuleFixture.clipFile])
    #expect(browsing.sessionID == LensModuleFixture.sessionA)
    #expect(findNode(browsing.root, at: LensModuleFixture.filmFile) != nil)
  }

  @Test("equal command and event sequences produce equal states")
  func equalSequencesProduceEqualStates() async throws {
    let first = makeSpaceLensHarness()
    let second = makeSpaceLensHarness()
    _ = try #require(await reachBrowsing(first))
    _ = try #require(await reachBrowsing(second))
    for harness in [first, second] {
      harness.model.toggleSelection(LensModuleFixture.filmFile)
      harness.model.drillIn(to: LensModuleFixture.mediaDirectory)
    }

    #expect(snapshot(first.model) == snapshot(second.model))
  }
}

// MARK: - Command totality

enum ForeignCommand: Equatable {
  case startMapping
  case drillIn
  case drillOut
  case toggleSelection
  case executeSelection(expecting: SpaceLensCommandRefusal)
  case cancelMapping
  case cancelExecution
  case acknowledgeResult
}

@MainActor
func expectCommandsAreIdentity(
  _ commands: [ForeignCommand],
  on harness: SpaceLensHarness
) async {
  for command in commands {
    let before = snapshot(harness.model)
    let mintedBefore = harness.sessions.minted.count
    switch command {
    case .startMapping:
      harness.model.startMapping(volume: LensModuleFixture.volume)
    case .drillIn:
      #expect(harness.model.drillIn(to: LensModuleFixture.mediaDirectory) == nil)
    case .drillOut:
      #expect(harness.model.drillOut() == nil)
    case .toggleSelection:
      harness.model.toggleSelection(LensModuleFixture.filmFile)
    case .executeSelection(let expected):
      #expect(harness.model.executeSelection(permanentConfirmation: nil) == expected)
    case .cancelMapping:
      harness.model.cancelMapping()
    case .cancelExecution:
      harness.model.cancelExecution()
    case .acknowledgeResult:
      harness.model.acknowledgeResult()
    }
    await settleBriefly()
    #expect(
      snapshot(harness.model) == before,
      "\(command) must be the identity in this state")
    if command == .startMapping {
      #expect(
        harness.sessions.minted.count == mintedBefore,
        "an ignored startMapping must not mint a session")
    }
  }
}

@MainActor
@Suite("Space lens module command totality")
struct SpaceLensModuleCommandTotalityTests {

  @Test("in idle every command except startMapping is the identity")
  func idleIgnoresEveryForeignCommand() async {
    let harness = makeSpaceLensHarness()
    await expectCommandsAreIdentity(
      [
        .drillIn, .drillOut, .toggleSelection,
        .executeSelection(expecting: .notBrowsing),
        .cancelMapping, .cancelExecution, .acknowledgeResult,
      ],
      on: harness)
    #expect(harness.model.permanentDeletionScope() == nil)
  }

  @Test("while mapping, execution is refused as still running and foreign commands are identity")
  func mappingRefusesExecutionAndIgnoresForeignCommands() async throws {
    let harness = makeSpaceLensHarness()
    let feed = await beginMapping(harness)
    sendStandardTree(feed)
    harness.model.toggleSelection(LensModuleFixture.filmFile)
    await expectEventually("the tree arrives") {
      mappingState(harness.model)?.root != nil
    }
    await expectCommandsAreIdentity(
      [
        .startMapping,
        .executeSelection(expecting: .mappingStillRunning),
        .cancelExecution, .acknowledgeResult,
      ],
      on: harness)
    #expect(harness.model.permanentDeletionScope() == nil)
    #expect(harness.engine.planCallCount == 0)
    #expect(harness.executor.executeCallCount == 0)
  }

  @Test("while executing every command except cancelExecution is the identity")
  func executingIgnoresEveryForeignCommand() async throws {
    let harness = makeSpaceLensHarness()
    _ = try #require(await reachExecuting(harness))
    await expectCommandsAreIdentity(
      [
        .startMapping, .drillIn, .drillOut, .toggleSelection,
        .executeSelection(expecting: .notBrowsing),
        .cancelMapping, .acknowledgeResult,
      ],
      on: harness)
    #expect(harness.model.permanentDeletionScope() == nil)
  }

  @Test("in result every command except acknowledgeResult and startMapping is the identity")
  func resultIgnoresEveryForeignCommand() async throws {
    let harness = makeSpaceLensHarness()
    _ = try #require(await reachResult(harness))
    await expectCommandsAreIdentity(
      [
        .drillIn, .drillOut, .toggleSelection,
        .executeSelection(expecting: .notBrowsing),
        .cancelMapping, .cancelExecution,
      ],
      on: harness)
    #expect(harness.model.permanentDeletionScope() == nil)
  }
}
