import CleanupModule
import Foundation
import GleamCore
import Testing

@MainActor
@Suite("Cleanup module permanent deletion confirmation")
struct CleanupModulePermanentConfirmationTests {

  @Test("in trash mode the scope is nil when no trash bin finding is selected")
  func trashModeWithoutTrashBinNeedsNoScope() async throws {
    let harness = makeCleanupHarness(deletionMode: .trash)
    _ = try #require(
      await reachReviewing(
        harness,
        findings: [ModuleFixture.cacheFinding(), ModuleFixture.logFinding()]))
    #expect(harness.model.permanentDeletionScope() == nil)
  }

  @Test(
    "trash bin findings are permanent even in trash mode and set the scope to their exact counts")
  func trashBinFindingsArePermanentEvenInTrashMode() async throws {
    let harness = makeCleanupHarness(deletionMode: .trash)
    _ = try #require(
      await reachReviewing(
        harness,
        findings: [ModuleFixture.cacheFinding(), ModuleFixture.trashBinFinding()]))

    let scope = try #require(harness.model.permanentDeletionScope())
    #expect(scope.fileCount == 2)
    #expect(scope.byteTotal == 700)
  }

  @Test("deselecting the trash bin finding clears the scope in trash mode")
  func deselectingTheTrashBinClearsTheScope() async throws {
    let harness = makeCleanupHarness(deletionMode: .trash)
    _ = try #require(
      await reachReviewing(
        harness,
        findings: [ModuleFixture.cacheFinding(), ModuleFixture.trashBinFinding()]))
    harness.model.toggleFinding(ModuleFixture.trashBinFinding().id)
    #expect(harness.model.permanentDeletionScope() == nil)
  }

  @Test("in permanent mode the scope covers every selected finding's files and bytes")
  func permanentModeScopeCoversTheWholeSelection() async throws {
    let harness = makeCleanupHarness(deletionMode: .permanent)
    _ = try #require(
      await reachReviewing(
        harness,
        findings: [
          ModuleFixture.cacheFinding(),
          ModuleFixture.logFinding(),
          ModuleFixture.trashBinFinding(),
        ]))

    let scope = try #require(harness.model.permanentDeletionScope())
    #expect(scope.fileCount == 5)
    #expect(scope.byteTotal == 2_000)
  }

  @Test("the scope moves with the selection in permanent mode")
  func permanentModeScopeMovesWithTheSelection() async throws {
    let harness = makeCleanupHarness(deletionMode: .permanent)
    let log = ModuleFixture.logFinding()
    _ = try #require(
      await reachReviewing(
        harness, findings: [ModuleFixture.cacheFinding(), log]))

    harness.model.toggleFinding(log.id)
    let scope = try #require(harness.model.permanentDeletionScope())
    #expect(scope.fileCount == 2)
    #expect(scope.byteTotal == 1_000)
  }

  @Test("a deletion mode saved while reviewing is honoured by the scope without another scan")
  func aSavedDeletionModeIsHonouredWhileReviewing() async throws {
    let harness = makeCleanupHarness(deletionMode: .trash)
    _ = try #require(
      await reachReviewing(harness, findings: [ModuleFixture.cacheFinding()]))
    #expect(harness.model.permanentDeletionScope() == nil)

    harness.store.pushUpdate(ModuleFixture.settings(mode: .permanent))
    await expectEventually("the scope reflects the permanent mode") {
      harness.model.permanentDeletionScope() != nil
    }
    let scope = try #require(harness.model.permanentDeletionScope())
    #expect(scope.fileCount == 2)
    #expect(scope.byteTotal == 1_000)
  }

  @Test(
    "executing a permanent scope with no confirmation refuses with the required scope and touches nothing"
  )
  func aMissingConfirmationRefusesWithTheRequiredScope() async throws {
    let harness = makeCleanupHarness(deletionMode: .permanent)
    _ = try #require(
      await reachReviewing(
        harness,
        findings: [
          ModuleFixture.cacheFinding(),
          ModuleFixture.logFinding(),
          ModuleFixture.trashBinFinding(),
        ]))
    let before = snapshot(harness.model)

    let refusal = harness.model.executeSelection(permanentConfirmation: nil)
    guard case .permanentDeletionUnconfirmed(let required) = refusal else {
      Issue.record("expected permanentDeletionUnconfirmed, got \(String(describing: refusal))")
      return
    }
    #expect(required.fileCount == 5)
    #expect(required.byteTotal == 2_000)
    await settleBriefly()
    #expect(snapshot(harness.model) == before)
    #expect(harness.engine.planCallCount == 0)
    #expect(harness.executor.executeCallCount == 0)
  }

  @Test("a confirmation naming different counts refuses with the mismatch and touches nothing")
  func aMismatchedConfirmationRefuses() async throws {
    let harness = makeCleanupHarness(deletionMode: .permanent)
    _ = try #require(
      await reachReviewing(
        harness,
        findings: [
          ModuleFixture.cacheFinding(),
          ModuleFixture.logFinding(),
          ModuleFixture.trashBinFinding(),
        ]))
    let before = snapshot(harness.model)

    let wrongCounts = PermanentDeletionConfirmation(
      fileCount: 4, byteTotal: 2_000, confirmedAt: ModuleFixture.confirmationInstant)
    let refusal = harness.model.executeSelection(permanentConfirmation: wrongCounts)
    guard case .confirmationMismatch(let required) = refusal else {
      Issue.record("expected confirmationMismatch, got \(String(describing: refusal))")
      return
    }
    #expect(required.fileCount == 5)
    #expect(required.byteTotal == 2_000)
    await settleBriefly()
    #expect(snapshot(harness.model) == before)
    #expect(harness.engine.planCallCount == 0)
    #expect(harness.executor.executeCallCount == 0)
  }

  @Test(
    "a confirmation naming the exact counts starts execution carrying that confirmation on the plan"
  )
  func anExactConfirmationStartsExecutionCarryingIt() async throws {
    let harness = makeCleanupHarness(deletionMode: .permanent)
    let confirmation = PermanentDeletionConfirmation(
      fileCount: 2, byteTotal: 1_000, confirmedAt: ModuleFixture.confirmationInstant)
    let run = try #require(
      await reachExecuting(
        harness,
        findings: [ModuleFixture.cacheFinding()],
        confirmation: confirmation
      ))

    #expect(run.plan.permanentDeletionConfirmation == confirmation)
    #expect(
      run.plan.operations.map(\.kind)
        == ModuleFixture.cacheFinding().paths.map { .deletePermanently(target: $0) })
  }

  @Test(
    "trash mode plans the trash bin permanently and everything else to the trash, under one confirmation"
  )
  func trashModeStillPlansTheTrashBinPermanently() async throws {
    let harness = makeCleanupHarness(deletionMode: .trash)
    let cache = ModuleFixture.cacheFinding()
    let bin = ModuleFixture.trashBinFinding()
    let confirmation = PermanentDeletionConfirmation(
      fileCount: 2, byteTotal: 700, confirmedAt: ModuleFixture.confirmationInstant)
    let run = try #require(
      await reachExecuting(harness, findings: [cache, bin], confirmation: confirmation))

    #expect(run.plan.permanentDeletionConfirmation == confirmation)
    let kindsByFinding = Dictionary(grouping: run.plan.operations, by: \.findingID)
    #expect(kindsByFinding[cache.id]?.map(\.kind) == cache.paths.map { .moveToTrash(target: $0) })
    #expect(kindsByFinding[bin.id]?.map(\.kind) == bin.paths.map { .deletePermanently(target: $0) })
  }
}
