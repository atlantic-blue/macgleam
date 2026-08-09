import Foundation
import GleamCore
import SpaceLensEngine
import Testing

@Suite("Space lens plan: the Trash default and exact entry totals")
struct SpaceLensPlanTests {

  private let documentsSelection = makeSpaceLensSelection(
    id: SpaceLensFixture.uuid(0xF1),
    entries: [
      PathEntry(
        path: SpaceLensFixture.path(LensTree.documentsDirectory), allocatedBytes: 9_000)
    ]
  )
  private let photoSelection = makeSpaceLensSelection(
    id: SpaceLensFixture.uuid(0xF2),
    entries: [
      PathEntry(path: SpaceLensFixture.path(LensTree.photo), allocatedBytes: 8_000)
    ]
  )

  @Test("trash mode plans one moveToTrash operation per selected node and no confirmation")
  func trashModePlansMoveToTrashPerNode() throws {
    let plan = try SpaceLensEngine().plan(
      selection: [documentsSelection, photoSelection],
      context: makePlanContext(
        rules: try LensTree.catalog(),
        settings: makeSpaceLensSettings(deletionMode: .trash))
    )

    #expect(plan.operations.count == 2)
    for operation in plan.operations {
      guard case .moveToTrash = operation.kind else {
        Issue.record("expected moveToTrash, got \(operation.kind)")
        continue
      }
    }
    let targets = Set(plan.operations.compactMap(operationTarget))
    #expect(
      targets == [
        SpaceLensFixture.path(LensTree.documentsDirectory),
        SpaceLensFixture.path(LensTree.photo),
      ])
    #expect(plan.permanentDeletionConfirmation == nil)
    #expect(plan.sessionID == SpaceLensFixture.sessionID)
  }

  @Test("the plan's total bytes are exactly the sum of the selected findings' entries")
  func planTotalBytesAreTheExactEntrySum() throws {
    let plan = try SpaceLensEngine().plan(
      selection: [documentsSelection, photoSelection],
      context: makePlanContext(rules: try LensTree.catalog())
    )

    #expect(plan.totalBytes == 17_000)
  }

  @Test("every operation carries the identifier of the finding it came from")
  func operationsCarryTheirFindingIdentifier() throws {
    let selection = [documentsSelection, photoSelection]
    let plan = try SpaceLensEngine().plan(
      selection: selection,
      context: makePlanContext(rules: try LensTree.catalog())
    )

    for operation in plan.operations {
      let target = try #require(operationTarget(operation))
      let owner = try #require(selection.first { $0.id == operation.findingID })
      #expect(owner.paths.contains(target))
    }
  }

  @Test("permanent mode plans deletePermanently with a confirmation naming exact counts")
  func permanentModeCarriesConfirmationWithExactCounts() throws {
    let plan = try SpaceLensEngine().plan(
      selection: [documentsSelection, photoSelection],
      context: makePlanContext(
        rules: try LensTree.catalog(),
        settings: makeSpaceLensSettings(deletionMode: .permanent))
    )

    for operation in plan.operations {
      guard case .deletePermanently = operation.kind else {
        Issue.record("expected deletePermanently, got \(operation.kind)")
        continue
      }
    }
    let confirmation = try #require(plan.permanentDeletionConfirmation)
    #expect(confirmation.fileCount == 2)
    #expect(confirmation.byteTotal == 17_000)
  }

  @Test("a denylisted selection plans no operation against it and its bytes are excluded exactly")
  func denylistedSelectionIsExcludedWithItsExactBytes() throws {
    let hostile = makeSpaceLensSelection(
      id: SpaceLensFixture.uuid(0xF3),
      entries: [
        PathEntry(
          path: SpaceLensFixture.path(LensTree.protectedDirectory), allocatedBytes: 2_000)
      ]
    )

    let plan = try SpaceLensEngine().plan(
      selection: [photoSelection, hostile],
      context: makePlanContext(rules: try LensTree.catalog())
    )

    let targets = plan.operations.compactMap(operationTarget)
    #expect(targets == [SpaceLensFixture.path(LensTree.photo)])
    #expect(plan.totalBytes == 8_000)
  }

  @Test("an empty selection throws emptySelection rather than producing an empty plan")
  func emptySelectionThrows() throws {
    let context = makePlanContext(rules: try LensTree.catalog())

    #expect(throws: PlanningError.emptySelection) {
      _ = try SpaceLensEngine().plan(selection: [], context: context)
    }
  }

  @Test("a finding from a different session throws rather than producing a partial plan")
  func findingFromDifferentSessionThrows() throws {
    let context = makePlanContext(
      rules: try LensTree.catalog(),
      sessionID: SpaceLensFixture.sessionID
    )
    let foreign = makeSpaceLensSelection(
      sessionID: SpaceLensFixture.foreignSessionID,
      entries: [
        PathEntry(path: SpaceLensFixture.path(LensTree.photo), allocatedBytes: 8_000)
      ]
    )

    #expect {
      _ = try SpaceLensEngine().plan(selection: [foreign], context: context)
    } throws: { error in
      guard let planning = error as? PlanningError,
        case .findingFromDifferentSession = planning
      else { return false }
      return true
    }
  }
}

@Suite("Space lens end to end: map, select, plan, execute")
struct SpaceLensEndToEndTests {

  @Test(
    "a file selected on the map travels through plan and the real executor into the trash with matching byte accounting"
  )
  func selectedFileLandsInTheTrashEndToEnd() async throws {
    let fileSystem = await LensTree.seeded()
    let catalog = try LensTree.catalog()
    let target = SpaceLensFixture.path(LensTree.photo)

    let outcome = try await runMap(over: fileSystem, rules: catalog)
    let convergedBytes = try #require(outcome.finalTotals[target])

    let selection = makeSpaceLensSelection(
      entries: [PathEntry(path: target, allocatedBytes: convergedBytes)]
    )
    let plan = try SpaceLensEngine().plan(
      selection: [selection],
      context: makePlanContext(
        rules: catalog, settings: makeSpaceLensSettings(deletionMode: .trash))
    )
    #expect(plan.totalBytes == convergedBytes)
    #expect(plan.permanentDeletionConfirmation == nil)
    let operation = try #require(plan.operations.first)
    #expect(plan.operations.count == 1)
    guard case .moveToTrash(let operationTarget) = operation.kind else {
      Issue.record("expected moveToTrash, got \(operation.kind)")
      return
    }
    #expect(operationTarget == target)

    var events: [ExecutionEvent] = []
    for await event in makeExecutor(fileSystem: fileSystem).execute(plan) {
      events.append(event)
    }

    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.result) == [.completed(bytesReclaimed: convergedBytes)])
    #expect(report.bytesReclaimed == selection.byteSize)
    #expect(await fileSystem.exists(target) == false)
    #expect(await fileSystem.exists(SpaceLensFixture.path("/.Trash/photo.heic")))
  }
}
