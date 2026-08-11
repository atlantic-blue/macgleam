import Foundation
import GleamCore
import LeftoversEngine
import Testing

@Suite("Leftovers plan and execution")
struct LeftoversPlanAndExecutionTests {

  @Test(
    "a selected large file travels from scan through plan and the real executor into the trash with matching byte accounting"
  )
  func selectedLargeFileLandsInTheTrashEndToEnd() async throws {
    let fileSystem = await LeftoversTree.seeded()
    let engine = makeLeftoversEngine()
    let catalog = try LeftoversTree.catalog()
    let target = LeftoversFixture.path(LeftoversTree.largeExactlyAtThreshold)

    let outcome = try await runLeftoversScan(rules: catalog, over: fileSystem, engine: engine)
    let selected = try #require(
      outcome.findings(in: .largeFile).first { $0.paths == [target] })

    let plan = try engine.plan(
      selection: [selected],
      context: makePlanContext(
        rules: catalog, settings: makeLeftoversSettings(deletionMode: .trash))
    )
    #expect(plan.totalBytes == LeftoversTree.largeThresholdBytes)
    #expect(plan.permanentDeletionConfirmation == nil)
    let operation = try #require(plan.operations.first)
    #expect(plan.operations.count == 1)
    guard case .moveToTrash(let operationTarget) = operation.kind else {
      Issue.record("expected moveToTrash, got \(operation.kind)")
      return
    }
    #expect(operationTarget == target)
    #expect(operation.findingID == selected.id)

    var events: [ExecutionEvent] = []
    for await event in makeExecutor(fileSystem: fileSystem).execute(plan) {
      events.append(event)
    }

    let report = try #require(executorFinalReport(in: events))
    #expect(
      report.results.map(\.result) == [
        .completed(bytesReclaimed: LeftoversTree.largeThresholdBytes)
      ])
    #expect(report.bytesReclaimed == selected.byteSize)
    #expect(await fileSystem.exists(target) == false)
    #expect(await fileSystem.exists(LeftoversFixture.path("/.Trash/video-archive.mov")))
  }

  @Test("every planned operation carries the identifier of the finding it came from")
  func operationsCarryTheirFindingIdentifier() async throws {
    let fileSystem = await LeftoversTree.seeded()
    let engine = makeLeftoversEngine()
    let catalog = try LeftoversTree.catalog()

    let outcome = try await runLeftoversScan(rules: catalog, over: fileSystem, engine: engine)
    let large = try #require(
      outcome.findings(in: .largeFile).first {
        $0.paths == [LeftoversFixture.path(LeftoversTree.largeExactlyAtThreshold)]
      })
    let old = try #require(
      outcome.findings(in: .oldFile).first {
        $0.paths == [LeftoversFixture.path(LeftoversTree.oldByLastOpened)]
      })
    let selection = [large, old]

    let plan = try engine.plan(selection: selection, context: makePlanContext(rules: catalog))

    #expect(plan.operations.count == 2)
    for operation in plan.operations {
      let target = try #require(operationTarget(operation))
      let owner = try #require(selection.first { $0.id == operation.findingID })
      #expect(owner.paths.contains(target))
    }
  }

  @Test("a hostile selection containing a denylisted path plans no operation against it")
  func denylistedPathNeverBecomesAnOperation() async throws {
    let catalog = try LeftoversTree.catalog()
    let allowed = LeftoversFixture.path(LeftoversTree.largeExactlyAtThreshold)
    let blocked = LeftoversFixture.path(LeftoversTree.denylistedLargeAndOld)
    let hostile = makeLeftoversFinding(
      paths: [LeftoversTree.largeExactlyAtThreshold, LeftoversTree.denylistedLargeAndOld],
      byteSize: LeftoversTree.largeThresholdBytes + 5_000
    )

    let plan = try makeLeftoversEngine().plan(
      selection: [hostile],
      context: makePlanContext(rules: catalog)
    )

    let targets = plan.operations.compactMap(operationTarget)
    #expect(targets == [allowed])
    #expect(!targets.contains(blocked))
  }

  /// C15 fixes the payload: the identifier is the offending finding's, never
  /// the session's, because a caller reconciling a refusal needs to know
  /// which finding to drop and a session identifier cannot tell them. The
  /// finding's identifier, its session and the context's session are three
  /// distinct fixture values, so this equality discriminates between them.
  @Test("the refusal names the offending finding, never the session it came from")
  func findingFromDifferentSessionNamesTheFinding() throws {
    let context = makePlanContext(
      rules: try LeftoversTree.catalog(),
      sessionID: LeftoversFixture.sessionID
    )
    let foreign = makeLeftoversFinding(
      id: LeftoversFixture.uuid(0xD4),
      sessionID: LeftoversFixture.foreignSessionID
    )

    #expect(throws: PlanningError.findingFromDifferentSession(foreign.id)) {
      _ = try makeLeftoversEngine().plan(selection: [foreign], context: context)
    }
  }
}
