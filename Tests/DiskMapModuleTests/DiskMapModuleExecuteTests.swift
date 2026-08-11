import DiskMapModule
import Foundation
import GleamCore
import Testing

@MainActor
@Suite("Space lens module execute: minting findings and the plan path")
struct DiskMapModuleExecuteTests {

  @Test("an empty selection while browsing is refused and nothing is touched")
  func anEmptySelectionIsRefused() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachBrowsing(harness))
    let before = snapshot(harness.model)

    #expect(harness.model.executeSelection(permanentConfirmation: nil) == .emptySelection)
    await settleBriefly()
    #expect(snapshot(harness.model) == before)
    #expect(harness.engine.planCallCount == 0)
    #expect(harness.executor.executeCallCount == 0)
  }

  @Test(
    "execution mints one finding per selected node with one entry carrying the converged total")
  func executionMintsOneFindingPerSelectedNode() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(
      await reachExecuting(
        harness,
        selecting: [LensModuleFixture.filmFile, LensModuleFixture.documentsDirectory]))

    let selection = try #require(harness.engine.lastPlanSelection)
    #expect(selection.count == 2)
    for finding in selection {
      #expect(finding.category == .diskMapSelection)
      #expect(finding.risk == .review)
      #expect(finding.isPreselected == false)
      #expect(finding.sessionID == LensModuleFixture.sessionA)
      #expect(finding.entries.count == 1)
      #expect(!finding.explanation.isEmpty)
    }
    let entriesByPath = Dictionary(
      uniqueKeysWithValues: selection.map { ($0.entries[0].path, $0.entries[0].allocatedBytes) })
    #expect(
      entriesByPath == [
        LensModuleFixture.filmFile: LensModuleFixture.filmBytes,
        LensModuleFixture.documentsDirectory: LensModuleFixture.documentsBytes,
      ])
  }

  @Test("the plan context is minted for the map session with the store's current settings")
  func thePlanContextBelongsToTheMapSession() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachExecuting(harness))

    #expect(
      harness.sessions.recordedPlanRequests == [
        PlanContextRequest(
          sessionID: LensModuleFixture.sessionA,
          settings: LensModuleFixture.settings(mode: .trash))
      ])
    #expect(harness.engine.lastPlanContext?.sessionID == LensModuleFixture.sessionA)
  }

  @Test("in trash mode the plan the executor receives moves every target to the trash")
  func trashModePlansMoveToTrash() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachExecuting(harness, selecting: [LensModuleFixture.filmFile]))

    let plan = try #require(harness.executor.lastPlan)
    #expect(plan.operations.map(\.kind) == [.moveToTrash(target: LensModuleFixture.filmFile)])
    #expect(plan.permanentDeletionConfirmation == nil)
  }

  @Test("a deletion mode saved while browsing is honoured at the moment of the command")
  func aSavedDeletionModeIsHonouredAtCommandTime() async throws {
    let harness = makeDiskMapHarness(deletionMode: .trash)
    _ = try #require(await reachBrowsing(harness))
    harness.model.toggleSelection(LensModuleFixture.filmFile)
    #expect(harness.model.permanentDeletionScope() == nil)

    harness.store.pushUpdate(LensModuleFixture.settings(mode: .permanent))
    await expectEventually("the scope reflects the permanent mode") {
      harness.model.permanentDeletionScope() != nil
    }

    let refusal = harness.model.executeSelection(
      permanentConfirmation: makeConfirmation(
        fileCount: 1, byteTotal: LensModuleFixture.filmBytes))
    #expect(refusal == nil)
    _ = await harness.executor.nextExecutionFeed()
    #expect(
      harness.sessions.recordedPlanRequests.last
        == PlanContextRequest(
          sessionID: LensModuleFixture.sessionA,
          settings: LensModuleFixture.settings(mode: .permanent)))
  }

  @Test("a plan failure leaves the model browsing with a plain failure sentence")
  func aPlanFailureLeavesTheModelBrowsing() async throws {
    struct PlanBroke: Error {}
    let harness = makeDiskMapHarness()
    _ = try #require(await reachBrowsing(harness))
    harness.model.toggleSelection(LensModuleFixture.filmFile)
    harness.engine.failPlans(with: PlanBroke())

    let refusal = harness.model.executeSelection(permanentConfirmation: nil)
    await settleBriefly()

    #expect(refusal == nil)
    #expect(browsingState(harness.model) != nil)
    let notice = try #require(harness.model.failureNotice)
    #expect(!notice.isEmpty)
    #expect(harness.executor.executeCallCount == 0)
  }

  @Test("the model never touches the file system on the whole path from map to execution")
  func theModelNeverTouchesTheFileSystem() async throws {
    let harness = makeDiskMapHarness()
    _ = try #require(await reachResult(harness))
    #expect(harness.sessions.fileSystem.violationCount == 0)
  }
}

@MainActor
@Suite("Space lens module permanent deletion confirmation")
struct DiskMapModulePermanentConfirmationTests {

  @Test("in trash mode the permanent scope is nil while browsing")
  func trashModeNeedsNoScope() async throws {
    let harness = makeDiskMapHarness(deletionMode: .trash)
    _ = try #require(await reachBrowsing(harness))
    harness.model.toggleSelection(LensModuleFixture.filmFile)

    #expect(harness.model.permanentDeletionScope() == nil)
  }

  @Test("in permanent mode the scope names the exact selected counts and bytes")
  func permanentModeScopeNamesExactCounts() async throws {
    let harness = makeDiskMapHarness(deletionMode: .permanent)
    _ = try #require(await reachBrowsing(harness))
    harness.model.toggleSelection(LensModuleFixture.filmFile)
    harness.model.toggleSelection(LensModuleFixture.documentsDirectory)

    let scope = try #require(harness.model.permanentDeletionScope())
    #expect(scope.fileCount == 2)
    #expect(
      scope.byteTotal == LensModuleFixture.filmBytes + LensModuleFixture.documentsBytes)
  }

  @Test("the scope moves with the selection")
  func theScopeMovesWithTheSelection() async throws {
    let harness = makeDiskMapHarness(deletionMode: .permanent)
    _ = try #require(await reachBrowsing(harness))
    harness.model.toggleSelection(LensModuleFixture.filmFile)
    harness.model.toggleSelection(LensModuleFixture.documentsDirectory)

    harness.model.toggleSelection(LensModuleFixture.documentsDirectory)

    let scope = try #require(harness.model.permanentDeletionScope())
    #expect(scope.fileCount == 1)
    #expect(scope.byteTotal == LensModuleFixture.filmBytes)
  }

  @Test(
    "a permanent selection with no confirmation refuses with the required scope and touches nothing"
  )
  func aMissingConfirmationRefusesWithTheRequiredScope() async throws {
    let harness = makeDiskMapHarness(deletionMode: .permanent)
    _ = try #require(await reachBrowsing(harness))
    harness.model.toggleSelection(LensModuleFixture.filmFile)
    let before = snapshot(harness.model)

    let refusal = harness.model.executeSelection(permanentConfirmation: nil)
    guard case .permanentDeletionUnconfirmed(let required) = refusal else {
      Issue.record("expected permanentDeletionUnconfirmed, got \(String(describing: refusal))")
      return
    }
    #expect(required.fileCount == 1)
    #expect(required.byteTotal == LensModuleFixture.filmBytes)
    await settleBriefly()
    #expect(snapshot(harness.model) == before)
    #expect(harness.engine.planCallCount == 0)
    #expect(harness.executor.executeCallCount == 0)
  }

  @Test("a confirmation naming different counts refuses with the mismatch and touches nothing")
  func aMismatchedConfirmationRefuses() async throws {
    let harness = makeDiskMapHarness(deletionMode: .permanent)
    _ = try #require(await reachBrowsing(harness))
    harness.model.toggleSelection(LensModuleFixture.filmFile)
    let before = snapshot(harness.model)

    let wrongCounts = makeConfirmation(fileCount: 2, byteTotal: LensModuleFixture.filmBytes)
    let refusal = harness.model.executeSelection(permanentConfirmation: wrongCounts)
    guard case .confirmationMismatch(let required) = refusal else {
      Issue.record("expected confirmationMismatch, got \(String(describing: refusal))")
      return
    }
    #expect(required.fileCount == 1)
    #expect(required.byteTotal == LensModuleFixture.filmBytes)
    await settleBriefly()
    #expect(snapshot(harness.model) == before)
    #expect(harness.engine.planCallCount == 0)
    #expect(harness.executor.executeCallCount == 0)
  }

  @Test(
    "a confirmation naming the exact counts starts execution carrying that confirmation, untouched")
  func anExactConfirmationStartsExecutionCarryingIt() async throws {
    let harness = makeDiskMapHarness(deletionMode: .permanent)
    let confirmation = makeConfirmation(
      fileCount: 1, byteTotal: LensModuleFixture.filmBytes)
    _ = try #require(
      await reachExecuting(
        harness, selecting: [LensModuleFixture.filmFile], confirmation: confirmation))

    let plan = try #require(harness.executor.lastPlan)
    #expect(plan.permanentDeletionConfirmation == confirmation)
    #expect(
      plan.permanentDeletionConfirmation?.confirmedAt == LensModuleFixture.confirmationInstant)
    #expect(
      plan.operations.map(\.kind) == [.deletePermanently(target: LensModuleFixture.filmFile)])
  }
}
