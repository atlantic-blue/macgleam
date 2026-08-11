import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// The safety property of the login item half, from C24: "`setEnabled`
/// disables or enables, never deletes", and from C23: "Disable, never delete:
/// no PerformanceEngine plan ever contains a file removal operation. A test
/// asserts this over the whole generated plan space."
///
/// A person turning off a startup item is saying "stop launching this", never
/// "take the file away". The two are one careless plan builder apart, and the
/// file is somebody's licensed updater or their employer's agent, so this
/// suite pins the property structurally rather than by example. It sweeps
/// every selection the scan's own findings can make, in both deletion modes,
/// it tampers with a login item finding so it carries real file paths, and it
/// mixes login items with findings from other modules that do name files.
@Suite("Performance login items: disable, never delete")
struct LaunchItemDisableNeverDeletesTests {

  // MARK: The whole generated plan space

  @Test("every selection of the listed login items plans a disable and nothing else")
  func everySelectionOfListedItemsPlansOnlyADisable() async throws {
    let world = LaunchItemWorld()
    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)
    let rules = try makeSignedPerformanceCatalog()

    for mode in [Settings.DeletionMode.trash, .permanent] {
      let context = makePlanContext(
        rules: rules, settings: makePerformanceSettings(deletionMode: mode))
      for selection in everySelection(of: outcome.launchItemFindings) {
        let plan = try PerformanceEngine().plan(selection: selection, context: context)

        expectNoFileRemoval(in: plan)
        #expect(
          plan.operations.compactMap { launchItemChange(of: $0)?.item }
            == selection.compactMap { launchItemCategory(of: $0)?.item },
          "one disable per selected item, in selection order, in \(mode.rawValue)")
        #expect(plan.operations.map(\.findingID) == selection.map(\.id))
        #expect(plan.totalBytes == 0, "turning an item off frees nothing, so it promises nothing")
        #expect(plan.sessionID == context.sessionID)
      }
    }
  }

  @Test("no plan ever turns an item on, whatever was selected")
  func noPlanEverTurnsAnItemOn() async throws {
    let world = LaunchItemWorld()
    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)
    let context = makePlanContext(rules: try makeSignedPerformanceCatalog())

    for selection in everySelection(of: outcome.launchItemFindings) {
      let plan = try PerformanceEngine().plan(selection: selection, context: context)

      #expect(
        plan.operations.allSatisfy { launchItemChange(of: $0)?.enabled == false },
        "C23: a login item selection plans setLaunchItemEnabled with enabled false")
    }
  }

  @Test("every mixed selection of login items and maintenance tasks plans no removal")
  func everyMixedSelectionOfPerformanceFindingsPlansNoRemoval() async throws {
    let world = LaunchItemWorld()
    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)
    let rules = try makeSignedPerformanceCatalog()
    let pool = Array(outcome.launchItemFindings.prefix(3)) + outcome.maintenanceFindings.prefix(3)

    for mode in [Settings.DeletionMode.trash, .permanent] {
      let context = makePlanContext(
        rules: rules, settings: makePerformanceSettings(deletionMode: mode))
      for selection in everySelection(of: pool) {
        let plan = try PerformanceEngine().plan(selection: selection, context: context)

        expectNoFileRemoval(in: plan)
        #expect(
          plan.operations.count == selection.count,
          "C15: a finding with no path entries expands into exactly one operation")
        #expect(plan.totalBytes == 0)
      }
    }
  }

  @Test("no selection drawn from a pool that includes path carrying findings yields a removal")
  func noSelectionFromAHostilePoolYieldsARemoval() async throws {
    let world = LaunchItemWorld()
    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)
    let rules = try makeSignedPerformanceCatalog()
    let entries = [
      PathEntry(
        path: PerformanceFixture.path(PerformanceFixture.realUserCachePath),
        allocatedBytes: 512),
      PathEntry(
        path: PerformanceFixture.path(PerformanceFixture.realSystemCachePath),
        allocatedBytes: 512),
    ]
    let pool =
      Array(outcome.launchItemFindings.prefix(2)) + [
        makeLaunchItemFinding(
          item: LaunchItemFixture.updaterAgent,
          id: PerformanceFixture.uuid(0xA5),
          entries: entries),
        makeMaintenanceFinding(
          task: .purgeMemoryPressure, id: PerformanceFixture.uuid(0xA6)),
        makeForeignFindingWithPaths(id: PerformanceFixture.uuid(0xA7), category: .userCache),
        makeForeignFindingWithPaths(
          id: PerformanceFixture.uuid(0xA8), category: .diskMapSelection),
      ]

    for mode in [Settings.DeletionMode.trash, .permanent] {
      let context = makePlanContext(
        rules: rules, settings: makePerformanceSettings(deletionMode: mode))
      for selection in everySelection(of: pool) {
        planExpectingNoFileRemoval(selection, context: context)
      }
    }
  }

  // MARK: Hostile findings, one shape at a time

  @Test("a login item finding tampered with to carry paths disables the item and removes nothing")
  func aTamperedLoginItemFindingRemovesNothing() throws {
    let context = makePlanContext(rules: try makeSignedPerformanceCatalog())
    let tampered = makeLaunchItemFinding(
      item: LaunchItemFixture.notesHelper,
      entries: [
        PathEntry(
          path: PerformanceFixture.path(PerformanceFixture.realUserCachePath),
          allocatedBytes: 4_096),
        PathEntry(
          path: PerformanceFixture.path(PerformanceFixture.realSystemCachePath),
          allocatedBytes: 8_192),
      ])

    let plan = planExpectingNoFileRemoval([tampered], context: context)

    if let plan {
      #expect(
        plan.operations.compactMap { launchItemChange(of: $0)?.item }
          == [LaunchItemFixture.notesHelper.identifier],
        "a login item finding expands into its item, never into one operation per path")
      #expect(
        plan.totalBytes == 0,
        "the paths smuggled into the finding must not become a reclaim promise")
    }
  }

  @Test("permanent deletion mode does not turn a login item selection into a deletion")
  func permanentDeletionModeChangesNothing() async throws {
    let world = LaunchItemWorld()
    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)
    let rules = try makeSignedPerformanceCatalog()
    let trashed = try PerformanceEngine().plan(
      selection: outcome.launchItemFindings,
      context: makePlanContext(
        rules: rules, settings: makePerformanceSettings(deletionMode: .trash)))
    let permanent = try PerformanceEngine().plan(
      selection: outcome.launchItemFindings,
      context: makePlanContext(
        rules: rules, settings: makePerformanceSettings(deletionMode: .permanent)))

    expectNoFileRemoval(in: permanent)
    #expect(
      permanent.operations.map(\.kind) == trashed.operations.map(\.kind),
      "deletion mode picks between trash and permanent removal; a disable is neither")
  }

  @Test("a denylist that blocks the whole disk leaves the login item plan untouched")
  func aTotalDenylistLeavesTheLoginItemPlanUntouched() async throws {
    let world = LaunchItemWorld()
    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)
    let context = makePlanContext(
      rules: try makeSignedPerformanceCatalog(blocking: ["/**"]))

    let plan = try PerformanceEngine().plan(
      selection: outcome.launchItemFindings, context: context)

    expectNoFileRemoval(in: plan)
    #expect(
      plan.operations.compactMap { launchItemChange(of: $0)?.item } == outcome.launchItems,
      "the denylist protects paths, and a login item finding names none, so it filters nothing")
  }

  // MARK: Running the plan

  @Test("running a plan that disables every login item mutates no file in this process")
  func runningTheWholePlanMutatesNoFile() async throws {
    let world = LaunchItemWorld()
    let (plan, _) = try await planLoginItems(
      LaunchItemFixture.items(LaunchItemFixture.inventory), inventory: world.inventoryOnly)
    let fileSystem = TrappingFileSystem()
    let executor = makeLaunchItemExecutor(
      manager: world.manager,
      helper: FakeHelper(),
      fileSystem: fileSystem,
      denylist: try await performanceDenylist()
    )

    _ = await executorCollect(executor, executing: plan)

    #expect(fileSystem.mutations.isEmpty, "the user process attempted \(fileSystem.mutations)")
  }

  @Test("running a plan that disables every login item leaves the disk exactly as it found it")
  func runningTheWholePlanLeavesTheDiskAlone() async throws {
    let world = LaunchItemWorld()
    let (plan, _) = try await planLoginItems(
      LaunchItemFixture.items(LaunchItemFixture.inventory), inventory: world.inventoryOnly)
    let fileSystem = await makeFixtureFileSystem()
    let userCache = PerformanceFixture.path(PerformanceFixture.realUserCachePath)
    let systemCache = PerformanceFixture.path(PerformanceFixture.realSystemCachePath)
    let before = try await fileSystem.readData(at: userCache, maxBytes: 4_096)
    let executor = makeLaunchItemExecutor(
      manager: world.manager,
      helper: FakeHelper(),
      fileSystem: fileSystem,
      denylist: try await performanceDenylist()
    )

    _ = await executorCollect(executor, executing: plan)

    #expect(await fileSystem.exists(userCache))
    #expect(await fileSystem.exists(systemCache))
    #expect(try await fileSystem.readData(at: userCache, maxBytes: 4_096) == before)
  }

  @Test("every login item is still listed after being disabled, off rather than gone")
  func everyDisabledItemIsStillListed() async throws {
    let world = LaunchItemWorld()
    let (plan, _) = try await planLoginItems(
      LaunchItemFixture.items(LaunchItemFixture.inventory), inventory: world.inventoryOnly)
    let executor = makeLaunchItemExecutor(
      manager: world.manager, denylist: try await performanceDenylist())

    _ = await executorCollect(executor, executing: plan)

    let listed = try await world.manager.list()
    #expect(
      listed.map(\.identifier) == LaunchItemFixture.items(LaunchItemFixture.inventory),
      "a disabled item stays in the list; a missing one would mean a deleted registration")
    #expect(listed.allSatisfy { $0.isEnabled == false })
    #expect(listed.map(\.path) == LaunchItemFixture.inventory.map(\.path))
  }
}
