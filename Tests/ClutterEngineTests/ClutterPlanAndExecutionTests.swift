import ClutterEngine
import Foundation
import GleamCore
import Testing

@Suite("Clutter plan and execution")
struct ClutterPlanAndExecutionTests {

  @Test(
    "a selected large file travels from scan through plan and the real executor into the trash with matching byte accounting"
  )
  func selectedLargeFileLandsInTheTrashEndToEnd() async throws {
    let fileSystem = await ClutterTree.seeded()
    let engine = makeClutterEngine()
    let catalog = try ClutterTree.catalog()
    let target = ClutterFixture.path(ClutterTree.largeExactlyAtThreshold)

    let outcome = try await runClutterScan(rules: catalog, over: fileSystem, engine: engine)
    let selected = try #require(
      outcome.findings(in: .largeFile).first { $0.paths == [target] })

    let plan = try engine.plan(
      selection: [selected],
      context: makePlanContext(rules: catalog, settings: makeClutterSettings(deletionMode: .trash))
    )
    #expect(plan.totalBytes == ClutterTree.largeThresholdBytes)
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
        .completed(bytesReclaimed: ClutterTree.largeThresholdBytes)
      ])
    #expect(report.bytesReclaimed == selected.byteSize)
    #expect(await fileSystem.exists(target) == false)
    #expect(await fileSystem.exists(ClutterFixture.path("/.Trash/video-archive.mov")))
  }

  @Test("every planned operation carries the identifier of the finding it came from")
  func operationsCarryTheirFindingIdentifier() async throws {
    let fileSystem = await ClutterTree.seeded()
    let engine = makeClutterEngine()
    let catalog = try ClutterTree.catalog()

    let outcome = try await runClutterScan(rules: catalog, over: fileSystem, engine: engine)
    let large = try #require(
      outcome.findings(in: .largeFile).first {
        $0.paths == [ClutterFixture.path(ClutterTree.largeExactlyAtThreshold)]
      })
    let old = try #require(
      outcome.findings(in: .oldFile).first {
        $0.paths == [ClutterFixture.path(ClutterTree.oldByLastOpened)]
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
    let catalog = try ClutterTree.catalog()
    let allowed = ClutterFixture.path(ClutterTree.largeExactlyAtThreshold)
    let blocked = ClutterFixture.path(ClutterTree.denylistedLargeAndOld)
    let hostile = makeClutterFinding(
      paths: [ClutterTree.largeExactlyAtThreshold, ClutterTree.denylistedLargeAndOld],
      byteSize: ClutterTree.largeThresholdBytes + 5_000
    )

    let plan = try makeClutterEngine().plan(
      selection: [hostile],
      context: makePlanContext(rules: catalog)
    )

    let targets = plan.operations.compactMap(operationTarget)
    #expect(targets == [allowed])
    #expect(!targets.contains(blocked))
  }
}
