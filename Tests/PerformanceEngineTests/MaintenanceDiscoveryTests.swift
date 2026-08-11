import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// C23's first guarantee: the Performance scan reports maintenance
/// opportunities as findings, at risk safe. C7 fixes the set of tasks, so
/// discovery is a closed question with a checkable answer rather than a list
/// somebody maintains by hand.
@Suite("Performance discovery: the maintenance tasks on offer")
struct MaintenanceDiscoveryTests {

  @Test("the engine declares the performance module")
  func engineDeclaresThePerformanceModule() {
    #expect(PerformanceEngine().module == .performance)
  }

  @Test("the scan offers every maintenance task the contract names, and no other")
  func scanOffersEveryTaskTheContractNames() async throws {
    let outcome = try await runPerformanceScan()

    #expect(Set(outcome.maintenanceTasks) == Set(MaintenanceTask.allCases))
  }

  @Test("no maintenance task is offered twice in one scan")
  func noTaskIsOfferedTwice() async throws {
    let outcome = try await runPerformanceScan()

    #expect(outcome.maintenanceTasks.count == Set(outcome.maintenanceTasks).count)
  }

  @Test("the catalogue and the contract's closed set of tasks are the same set")
  func catalogueMatchesTheClosedSetOfTasks() {
    #expect(Set(MaintenanceCatalogue.tasks) == Set(MaintenanceTask.allCases))
    #expect(MaintenanceCatalogue.tasks.count == MaintenanceTask.allCases.count)
  }

  @Test("the scan offers the tasks in the catalogue's presentation order")
  func scanFollowsTheCataloguesOrder() async throws {
    let outcome = try await runPerformanceScan()

    #expect(outcome.maintenanceTasks == MaintenanceCatalogue.tasks)
  }

  @Test("every maintenance finding carries the task it is offering")
  func everyFindingCarriesItsTask() async throws {
    let outcome = try await runPerformanceScan()

    for task in MaintenanceTask.allCases {
      let finding = try #require(
        outcome.maintenanceFinding(for: task), "no finding offered \(task.rawValue)")
      #expect(finding.category == .maintenanceTask(task: task))
    }
  }

  @Test("every maintenance task explains itself in a plain sentence")
  func everyTaskExplainsItselfInPlainWords() async throws {
    let outcome = try await runPerformanceScan()

    for task in MaintenanceTask.allCases {
      let finding = try #require(outcome.maintenanceFinding(for: task))
      expectPlainSentence(finding.explanation)
      expectPlainSentence(MaintenanceCatalogue.explanation(for: task))
      #expect(
        finding.explanation.contains(MaintenanceCatalogue.explanation(for: task)),
        "the finding a person reads says what the catalogue says about \(task.rawValue)")
    }
  }

  @Test("each task's explanation is its own rather than one sentence reused")
  func explanationsAreOwnedByTheirTask() {
    let explanations = MaintenanceTask.allCases.map(MaintenanceCatalogue.explanation(for:))

    #expect(Set(explanations).count == MaintenanceTask.allCases.count)
  }

  @Test("every maintenance finding is risk safe")
  func maintenanceFindingsAreRiskSafe() async throws {
    let outcome = try await runPerformanceScan()

    #expect(outcome.maintenanceFindings.isEmpty == false)
    #expect(outcome.maintenanceFindings.allSatisfy { $0.risk == .safe })
  }

  @Test("nothing the scan preselects is riskier than safe")
  func preselectionNeverExceedsSafe() async throws {
    let outcome = try await runPerformanceScan()

    #expect(
      outcome.findings.allSatisfy { $0.isPreselected == false || $0.risk == .safe },
      "a preselected finding runs without the user choosing it, so only safe may be preselected")
  }

  @Test("no maintenance finding names a file path")
  func maintenanceFindingsNameNoPath() async throws {
    let outcome = try await runPerformanceScan()

    for finding in outcome.maintenanceFindings {
      #expect(
        finding.paths.isEmpty,
        "a maintenance finding names a task; a path in one is a removal waiting to be planned")
      #expect(finding.byteSize == 0, "maintenance reclaims no space and must not promise any")
    }
  }

  @Test("two scans of the same machine offer the same tasks with the same words")
  func discoveryIsDeterministic() async throws {
    let first = try await runPerformanceScan()
    let second = try await runPerformanceScan()

    #expect(first.maintenanceTasks == second.maintenanceTasks)
    for task in MaintenanceTask.allCases {
      let left = try #require(first.maintenanceFinding(for: task))
      let right = try #require(second.maintenanceFinding(for: task))
      #expect(left.explanation == right.explanation)
      #expect(left.risk == right.risk)
      #expect(left.isPreselected == right.isPreselected)
    }
  }

  @Test("maintenance is offered without Full Disk Access, because it reads no files")
  func maintenanceIsOfferedWithoutFullDiskAccess() async throws {
    let outcome = try await runPerformanceScan(hasFullDiskAccess: false)

    #expect(Set(outcome.maintenanceTasks) == Set(MaintenanceTask.allCases))
  }
}
