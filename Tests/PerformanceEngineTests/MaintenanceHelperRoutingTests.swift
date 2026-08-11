import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// C23: maintenance plans emit `runMaintenance` operations with privilege
/// root, because maintenance tasks are the helper's job. C17: an operation
/// the user process cannot do itself goes to the helper as a typed request.
///
/// The whole point is that this work never happens in the user process, so
/// every test here runs the plan against a file system that performs no
/// mutation and reports every attempt, and against a fake helper that records
/// what crossed the boundary. Nothing in this suite runs a system command,
/// asks for privilege or reaches the real daemon; turning an operation into a
/// C30 request is the helper client's job and is pinned in its own suite.
@Suite("Performance maintenance: it runs through the helper")
struct MaintenanceHelperRoutingTests {

  @Test("every maintenance operation is planned at root privilege")
  func maintenanceOperationsArePlannedAtRootPrivilege() async throws {
    let (plan, _) = try await planMaintenance()

    #expect(plan.operations.isEmpty == false)
    #expect(plan.operations.allSatisfy { $0.privilege == .root })
  }

  @Test("every selected task reaches the helper, in plan order")
  func everyTaskReachesTheHelperInPlanOrder() async throws {
    let (plan, _) = try await planMaintenance()
    let helper = FakeHelper()
    let executor = makeExecutor(
      helper: helper,
      fileSystem: TrappingFileSystem(),
      denylist: try await performanceDenylist()
    )

    _ = await executorCollect(executor, executing: plan)

    #expect(helper.performedTasks == plan.operations.compactMap(maintenanceTask(of:)))
    #expect(helper.performedTasks == MaintenanceTask.allCases)
  }

  @Test("the operation reaches the helper naming the plan it belongs to")
  func theHandoverNamesThePlanItBelongsTo() async throws {
    let (plan, _) = try await planMaintenance([.flushDomainNameSystemCache])
    let helper = FakeHelper()
    let executor = makeExecutor(
      helper: helper,
      fileSystem: TrappingFileSystem(),
      denylist: try await performanceDenylist()
    )

    _ = await executorCollect(executor, executing: plan)

    let operation = try #require(plan.operations.first)
    #expect(
      helper.handovers == [
        PrivilegedHandover(
          operationID: operation.id,
          planID: plan.id,
          kind: .runMaintenance(task: .flushDomainNameSystemCache),
          privilege: .root
        )
      ],
      "C30 requires every request to name the plan and the operation it belongs to")
  }

  @Test("nothing but maintenance crosses into the privileged process")
  func nothingButMaintenanceCrossesTheBoundary() async throws {
    let (plan, _) = try await planMaintenance()
    let helper = FakeHelper()
    let executor = makeExecutor(
      helper: helper,
      fileSystem: TrappingFileSystem(),
      denylist: try await performanceDenylist()
    )

    _ = await executorCollect(executor, executing: plan)

    #expect(
      helper.performedKinds.allSatisfy { isFileRemoval($0) == false },
      "the helper runs as root; a removal reaching it is the failure this module must not have")
    #expect(
      helper.performedKinds.count == helper.performedTasks.count,
      "every kind that crossed was a maintenance kind, nothing else")
  }

  @Test("no maintenance work happens in the user process")
  func noMaintenanceWorkHappensInProcess() async throws {
    let (plan, _) = try await planMaintenance()
    let fileSystem = TrappingFileSystem()
    let executor = makeExecutor(
      helper: FakeHelper(),
      fileSystem: fileSystem,
      denylist: try await performanceDenylist()
    )

    _ = await executorCollect(executor, executing: plan)

    #expect(fileSystem.mutations.isEmpty, "the user process attempted \(fileSystem.mutations)")
  }

  @Test("a maintenance run leaves every file on disk exactly as it found it")
  func aMaintenanceRunLeavesTheDiskAlone() async throws {
    let (plan, _) = try await planMaintenance()
    let fileSystem = await makeFixtureFileSystem()
    let userCache = PerformanceFixture.path(PerformanceFixture.realUserCachePath)
    let systemCache = PerformanceFixture.path(PerformanceFixture.realSystemCachePath)
    let before = try await fileSystem.readData(at: userCache, maxBytes: 4_096)
    let executor = makeExecutor(
      helper: FakeHelper(),
      fileSystem: fileSystem,
      denylist: try await performanceDenylist()
    )

    _ = await executorCollect(executor, executing: plan)

    #expect(await fileSystem.exists(userCache))
    #expect(await fileSystem.exists(systemCache))
    #expect(try await fileSystem.readData(at: userCache, maxBytes: 4_096) == before)
  }

  @Test("even when the ownership policy calls everything user domain, maintenance still routes out")
  func maintenanceRoutesOutWhateverTheOwnershipPolicySays() async throws {
    let (plan, _) = try await planMaintenance([.purgeMemoryPressure])
    let helper = FakeHelper()
    let executor = makeExecutor(
      helper: helper,
      fileSystem: TrappingFileSystem(),
      denylist: try await performanceDenylist(),
      ownership: EverythingIsUserDomainPolicy()
    )

    _ = await executorCollect(executor, executing: plan)

    #expect(
      helper.performedTasks == [.purgeMemoryPressure],
      "a maintenance task names no path, so no path's ownership can bring it back in process")
  }

  @Test("with no helper the run is refused and nothing is attempted in process")
  func withNoHelperTheRunIsRefused() async throws {
    let (plan, _) = try await planMaintenance([.rebuildLaunchServicesDatabase])
    let fileSystem = TrappingFileSystem()
    let executor = makeExecutor(
      helper: nil,
      fileSystem: fileSystem,
      denylist: try await performanceDenylist()
    )

    let events = await executorCollect(executor, executing: plan)

    let refusal = try #require(executorRefusal(in: events))
    guard case .helperUnavailable(let reason) = refusal else {
      Issue.record("expected helperUnavailable, got \(refusal)")
      return
    }
    #expect(reason.isEmpty == false)
    #expect(fileSystem.mutations.isEmpty)
    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.result) == [.notStarted])
  }

  @Test("the report accounts for every task once, in plan order, whatever the helper answered")
  func theReportAccountsForEveryTaskOnce() async throws {
    let (plan, _) = try await planMaintenance()
    let helper = FakeHelper(
      results: [
        .triggerSpotlightReindex: .failed(
          reason: "The reindex could not be started, so nothing was changed.")
      ])
    let executor = makeExecutor(
      helper: helper,
      fileSystem: TrappingFileSystem(),
      denylist: try await performanceDenylist()
    )

    let events = await executorCollect(executor, executing: plan)

    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.operationID) == plan.operations.map(\.id))
    #expect(report.bytesReclaimed == 0, "maintenance frees no space, so the report claims none")
  }

  @Test("one task failing in the helper costs that task and not the run")
  func oneFailingTaskDoesNotSinkTheRun() async throws {
    let (plan, _) = try await planMaintenance()
    let sentence = "The cache could not be flushed, so it is unchanged."
    let helper = FakeHelper(results: [.flushDomainNameSystemCache: .failed(reason: sentence)])
    let executor = makeExecutor(
      helper: helper,
      fileSystem: TrappingFileSystem(),
      denylist: try await performanceDenylist()
    )

    let events = await executorCollect(executor, executing: plan)

    #expect(helper.performedTasks == MaintenanceTask.allCases, "later tasks still ran")
    let report = try #require(executorFinalReport(in: events))
    let failures = report.results.filter {
      if case .failed = $0.result { return true }
      return false
    }
    #expect(failures.count == 1)
    #expect(executorRefusal(in: events) == nil, "one task failing is not the run failing")
  }
}
