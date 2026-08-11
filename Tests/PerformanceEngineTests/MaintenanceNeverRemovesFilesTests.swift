import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// The safety property of the Performance module, from C23: "Disable, never
/// delete: no PerformanceEngine plan ever contains a file removal operation.
/// A test asserts this over the whole generated plan space."
///
/// Performance is the module that touches the running system rather than
/// files, so a removal appearing in one of its plans is a category error with
/// real consequences: a plan built to flush a cache would take files away
/// instead. So this suite pins the property structurally rather than by
/// example. It sweeps every selection the engine's own findings can make, in
/// both deletion modes, and it feeds the plan builder findings that carry real
/// file paths to see whether a removal can be coaxed out of it.
@Suite("Performance plans: no file removal, ever")
struct MaintenanceNeverRemovesFilesTests {

  // MARK: The whole generated plan space

  @Test("every selection of the scan's own findings plans maintenance and nothing else")
  func everySelectionOfScannedFindingsPlansOnlyMaintenance() async throws {
    let outcome = try await runPerformanceScan()
    let rules = try makeSignedPerformanceCatalog()

    for mode in [Settings.DeletionMode.trash, .permanent] {
      let context = makePlanContext(
        rules: rules, settings: makePerformanceSettings(deletionMode: mode))
      for selection in everySelection(of: outcome.maintenanceFindings) {
        let plan = try PerformanceEngine().plan(selection: selection, context: context)

        expectNoFileRemoval(in: plan)
        #expect(
          plan.operations.map(maintenanceTask(of:)) == selection.map(maintenanceTask(of:)),
          "one maintenance operation per selected task, in selection order, in \(mode.rawValue)")
        #expect(plan.operations.allSatisfy { $0.privilege == .root })
        #expect(plan.operations.map(\.findingID) == selection.map(\.id))
        #expect(plan.totalBytes == 0, "maintenance reclaims nothing, so it promises nothing")
        #expect(plan.sessionID == context.sessionID)
      }
    }
  }

  @Test("every selection built by hand from the closed set of tasks plans maintenance only")
  func everySelectionOfHandBuiltTasksPlansOnlyMaintenance() throws {
    let rules = try makeSignedPerformanceCatalog()
    let context = makePlanContext(rules: rules)
    let findings = MaintenanceTask.allCases.enumerated().map { index, task in
      makeMaintenanceFinding(task: task, id: PerformanceFixture.uuid(UInt8(0x40 + index)))
    }

    for selection in everySelection(of: findings) {
      let plan = try PerformanceEngine().plan(selection: selection, context: context)

      expectNoFileRemoval(in: plan)
      #expect(plan.operations.map(maintenanceTask(of:)) == selection.map(maintenanceTask(of:)))
    }
  }

  @Test("no selection drawn from a pool that includes path carrying findings yields a removal")
  func noSelectionFromAHostilePoolYieldsARemoval() async throws {
    let outcome = try await runPerformanceScan()
    let rules = try makeSignedPerformanceCatalog()
    let pool =
      outcome.maintenanceFindings + [
        makeForeignFindingWithPaths(id: PerformanceFixture.uuid(0x51), category: .userCache),
        makeForeignFindingWithPaths(id: PerformanceFixture.uuid(0x52), category: .diskMapSelection),
        makeMaintenanceFinding(
          task: .flushDomainNameSystemCache,
          id: PerformanceFixture.uuid(0x53),
          entries: [
            PathEntry(
              path: PerformanceFixture.path(PerformanceFixture.realUserCachePath),
              allocatedBytes: 512)
          ]),
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

  @Test("a cleanup finding carrying real paths is refused or produces no removal")
  func aCleanupFindingCarryingPathsProducesNoRemoval() throws {
    let context = makePlanContext(rules: try makeSignedPerformanceCatalog())

    let plan = planExpectingNoFileRemoval([makeForeignFindingWithPaths()], context: context)

    if let plan {
      #expect(
        plan.totalBytes == 0,
        "a Performance plan reclaims nothing, so it never inherits another module's bytes")
    }
  }

  @Test("a disk map selection carrying real paths is refused or produces no removal")
  func aDiskMapSelectionCarryingPathsProducesNoRemoval() throws {
    let context = makePlanContext(rules: try makeSignedPerformanceCatalog())
    let finding = makeForeignFindingWithPaths(category: .diskMapSelection, risk: .review)

    planExpectingNoFileRemoval([finding], context: context)
  }

  @Test("a maintenance finding tampered with to carry paths plans the task and removes nothing")
  func aTamperedMaintenanceFindingRemovesNothing() throws {
    let context = makePlanContext(rules: try makeSignedPerformanceCatalog())
    let tampered = makeMaintenanceFinding(
      task: .purgeMemoryPressure,
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
        plan.operations.compactMap(maintenanceTask(of:)) == [.purgeMemoryPressure],
        "a maintenance finding expands into its task, never into one operation per path")
      #expect(
        plan.totalBytes == 0,
        "the paths smuggled into the finding must not become a reclaim promise")
    }
  }

  @Test("permanent deletion mode does not turn a maintenance selection into a deletion")
  func permanentDeletionModeChangesNothing() async throws {
    let outcome = try await runPerformanceScan()
    let rules = try makeSignedPerformanceCatalog()
    let trashed = try PerformanceEngine().plan(
      selection: outcome.maintenanceFindings,
      context: makePlanContext(
        rules: rules, settings: makePerformanceSettings(deletionMode: .trash)))
    let permanent = try PerformanceEngine().plan(
      selection: outcome.maintenanceFindings,
      context: makePlanContext(
        rules: rules, settings: makePerformanceSettings(deletionMode: .permanent)))

    expectNoFileRemoval(in: permanent)
    #expect(
      permanent.operations.map(maintenanceTask(of:))
        == trashed.operations.map(maintenanceTask(of:)),
      "deletion mode picks between trash and permanent removal; maintenance removes neither")
  }

  @Test("a denylist that blocks the whole disk leaves the maintenance plan untouched")
  func aTotalDenylistLeavesTheMaintenancePlanUntouched() async throws {
    let outcome = try await runPerformanceScan()
    let context = makePlanContext(
      rules: try makeSignedPerformanceCatalog(blocking: ["/**"]))

    let plan = try PerformanceEngine().plan(
      selection: outcome.maintenanceFindings, context: context)

    expectNoFileRemoval(in: plan)
    #expect(
      plan.operations.map(maintenanceTask(of:)) == outcome.maintenanceTasks,
      "the denylist protects paths, and maintenance names none, so it filters nothing here")
  }

  // MARK: Planning refusals

  @Test("planning nothing throws emptySelection rather than an empty plan")
  func planningNothingThrowsEmptySelection() throws {
    let context = makePlanContext(rules: try makeSignedPerformanceCatalog())

    #expect(throws: PlanningError.emptySelection) {
      _ = try PerformanceEngine().plan(selection: [], context: context)
    }
  }

  /// C15 fixes the payload: the identifier is the offending finding's, never
  /// the session's, because a caller reconciling a refusal needs to know
  /// which finding to drop and a session identifier cannot tell them. The
  /// stray's identifier, its session and the context's session are three
  /// distinct fixture values, so this equality discriminates between them.
  @Test("a finding from another session is refused, naming the finding rather than the session")
  func aFindingFromAnotherSessionIsRefused() throws {
    let context = makePlanContext(rules: try makeSignedPerformanceCatalog())
    let stray = makeMaintenanceFinding(
      task: .runPeriodicMaintenance,
      id: PerformanceFixture.uuid(0xD2),
      sessionID: PerformanceFixture.otherSessionID)

    #expect(throws: PlanningError.findingFromDifferentSession(stray.id)) {
      _ = try PerformanceEngine().plan(selection: [stray], context: context)
    }
  }

  @Test("a refusal produces no partial plan, so nothing from the good half survives")
  func aRefusalProducesNoPartialPlan() async throws {
    let outcome = try await runPerformanceScan()
    let context = makePlanContext(rules: try makeSignedPerformanceCatalog())
    let stray = makeMaintenanceFinding(
      task: .triggerSpotlightReindex, sessionID: PerformanceFixture.otherSessionID)

    #expect(throws: PlanningError.self) {
      _ = try PerformanceEngine().plan(
        selection: outcome.maintenanceFindings + [stray], context: context)
    }
  }
}
