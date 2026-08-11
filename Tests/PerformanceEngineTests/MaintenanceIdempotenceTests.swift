import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// C7: maintenance tasks are idempotent, running one twice is safe and
/// equivalent to running it once. A maintenance task that is not safe to
/// repeat is a trap, because the module's whole shape invites a second press.
///
/// What a unit suite can prove and what it cannot, said plainly. The real
/// commands' effect on a real machine is the s3c human check in GRAPH.md and
/// nothing here stands in for it. What is pinned here is the half that lives
/// in this code and would quietly break: the app offers, plans and dispatches
/// a repeat exactly as it did the first time, it does not swallow the second
/// press, it does not consume the offer, and it never claims a second run
/// reclaimed anything.
@Suite("Performance maintenance: running a task twice")
struct MaintenanceIdempotenceTests {

  @Test("planning the same selection twice produces the same operations")
  func planningTwiceProducesTheSameOperations() async throws {
    let (first, _) = try await planMaintenance()
    let (second, _) = try await planMaintenance()

    #expect(
      first.operations.compactMap(maintenanceTask(of:))
        == second.operations.compactMap(maintenanceTask(of:)))
    #expect(first.operations.map(\.privilege) == second.operations.map(\.privilege))
    #expect(first.totalBytes == second.totalBytes)
  }

  @Test("running the same plan twice reaches the helper twice with the same request")
  func runningTheSamePlanTwiceReachesTheHelperTwice() async throws {
    let (plan, _) = try await planMaintenance([.flushDomainNameSystemCache])
    let helper = FakeHelper()
    let executor = makeExecutor(
      helper: helper,
      fileSystem: TrappingFileSystem(),
      denylist: try await performanceDenylist()
    )

    _ = await executorCollect(executor, executing: plan)
    let afterFirst = helper.handovers
    _ = await executorCollect(executor, executing: plan)

    #expect(afterFirst.count == 1)
    #expect(
      helper.handovers == afterFirst + afterFirst,
      "the second press is dispatched, not swallowed, and it is the same request")
  }

  @Test("the second run reports exactly what the first reported")
  func theSecondRunReportsWhatTheFirstDid() async throws {
    let (plan, _) = try await planMaintenance()
    let executor = makeExecutor(
      helper: FakeHelper(),
      fileSystem: TrappingFileSystem(),
      denylist: try await performanceDenylist()
    )

    let firstEvents = await executorCollect(executor, executing: plan)
    let secondEvents = await executorCollect(executor, executing: plan)

    let first = try #require(executorFinalReport(in: firstEvents))
    let second = try #require(executorFinalReport(in: secondEvents))
    #expect(first.results.map(\.operationID) == second.results.map(\.operationID))
    #expect(first.results.map(\.result) == second.results.map(\.result))
  }

  @Test("a second run never claims to have reclaimed anything")
  func aSecondRunClaimsNoReclaimedBytes() async throws {
    let (plan, _) = try await planMaintenance()
    let executor = makeExecutor(
      helper: FakeHelper(),
      fileSystem: TrappingFileSystem(),
      denylist: try await performanceDenylist()
    )

    let firstEvents = await executorCollect(executor, executing: plan)
    let secondEvents = await executorCollect(executor, executing: plan)

    #expect(try #require(executorFinalReport(in: firstEvents)).bytesReclaimed == 0)
    #expect(try #require(executorFinalReport(in: secondEvents)).bytesReclaimed == 0)
  }

  @Test("two runs leave the disk in the state one run left it, which is untouched")
  func twoRunsLeaveTheDiskAsOneDid() async throws {
    let (plan, _) = try await planMaintenance()
    let fileSystem = await makeFixtureFileSystem()
    let userCache = PerformanceFixture.path(PerformanceFixture.realUserCachePath)
    let before = try await fileSystem.readData(at: userCache, maxBytes: 4_096)
    let executor = makeExecutor(
      helper: FakeHelper(),
      fileSystem: fileSystem,
      denylist: try await performanceDenylist()
    )

    _ = await executorCollect(executor, executing: plan)
    let afterFirst = try await fileSystem.readData(at: userCache, maxBytes: 4_096)
    _ = await executorCollect(executor, executing: plan)

    #expect(afterFirst == before)
    #expect(try await fileSystem.readData(at: userCache, maxBytes: 4_096) == afterFirst)
  }

  @Test("a task is still offered, unchanged, after it has been run")
  func aTaskIsStillOfferedAfterItHasRun() async throws {
    let (plan, findings) = try await planMaintenance()
    let executor = makeExecutor(
      helper: FakeHelper(),
      fileSystem: TrappingFileSystem(),
      denylist: try await performanceDenylist()
    )

    _ = await executorCollect(executor, executing: plan)
    let afterwards = try await runPerformanceScan()

    #expect(Set(afterwards.maintenanceTasks) == Set(MaintenanceTask.allCases))
    for finding in findings {
      let task = try #require(maintenanceTask(of: finding))
      let offered = try #require(afterwards.maintenanceFinding(for: task))
      #expect(offered.explanation == finding.explanation)
      #expect(offered.risk == finding.risk)
      #expect(offered.isPreselected == finding.isPreselected)
    }
  }

  @Test("two separate runs of the same task, each freshly scanned and planned, agree")
  func twoFreshlyPlannedRunsAgree() async throws {
    let executor = makeExecutor(
      helper: FakeHelper(),
      fileSystem: TrappingFileSystem(),
      denylist: try await performanceDenylist()
    )
    let (firstPlan, _) = try await planMaintenance([.runPeriodicMaintenance])
    let (secondPlan, _) = try await planMaintenance([.runPeriodicMaintenance])

    let firstEvents = await executorCollect(executor, executing: firstPlan)
    let secondEvents = await executorCollect(executor, executing: secondPlan)

    let first = try #require(executorFinalReport(in: firstEvents))
    let second = try #require(executorFinalReport(in: secondEvents))
    #expect(first.results.map(\.result) == second.results.map(\.result))
    #expect(first.bytesReclaimed == second.bytesReclaimed)
  }
}
