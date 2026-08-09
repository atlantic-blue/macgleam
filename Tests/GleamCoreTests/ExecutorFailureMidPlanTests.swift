import Foundation
import GleamCore
import Testing

@Suite("Executor failure mid plan")
struct ExecutorFailureMidPlanTests {
  @Test(
    "an operation with a missing source fails with a reason while earlier items stay done and later items still run"
  )
  func missingSourceFailsThatOperationAndTheRestStillRun() async throws {
    let fileSystem = InMemoryFileSystem()
    let first = ExecutorFixture.path("/Users/julian/Caches/fail-one.log")
    let missing = ExecutorFixture.path("/Users/julian/Caches/was-never-here.log")
    let third = ExecutorFixture.path("/Users/julian/Caches/fail-three.log")
    await fileSystem.seedFile(at: first, contents: Data(repeating: 0x61, count: 10))
    await fileSystem.seedFile(at: third, contents: Data(repeating: 0x63, count: 30))
    let plan = ExecutorFixture.plan(
      operations: [
        ExecutorFixture.trashOperation(target: first),
        ExecutorFixture.trashOperation(target: missing),
        ExecutorFixture.trashOperation(target: third),
      ],
      totalBytes: 40
    )
    let executor = executorMake(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist())

    let events = await executorCollect(executor, executing: plan)

    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.count == 3)
    #expect(report.results[0].result == .completed(bytesReclaimed: 10))
    let reason = try #require(executorFailureReason(report.results[1].result))
    #expect(reason.isEmpty == false)
    #expect(report.results[2].result == .completed(bytesReclaimed: 30))
    #expect(report.bytesReclaimed == 40)
    #expect(await fileSystem.exists(ExecutorFixture.path("/.Trash/fail-one.log")))
    #expect(await fileSystem.exists(ExecutorFixture.path("/.Trash/fail-three.log")))
  }

  @Test(
    "a user scope launch item operation this slice cannot perform fails with a reason and does not sink the run"
  )
  func userLaunchItemOperationFailsWithoutSinkingTheRun() async throws {
    let fileSystem = InMemoryFileSystem()
    let first = ExecutorFixture.path("/Users/julian/Caches/item-one.log")
    let third = ExecutorFixture.path("/Users/julian/Caches/item-three.log")
    await fileSystem.seedFile(at: first, contents: Data(repeating: 0x71, count: 10))
    await fileSystem.seedFile(at: third, contents: Data(repeating: 0x73, count: 30))
    let plan = ExecutorFixture.plan(
      operations: [
        ExecutorFixture.trashOperation(target: first),
        ExecutorFixture.launchItemOperation(
          label: "com.example.updater.user", enabled: false, privilege: .user),
        ExecutorFixture.trashOperation(target: third),
      ],
      totalBytes: 40
    )
    let executor = executorMake(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist())

    let events = await executorCollect(executor, executing: plan)

    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.count == 3)
    #expect(report.results[0].result == .completed(bytesReclaimed: 10))
    let reason = try #require(executorFailureReason(report.results[1].result))
    #expect(reason.isEmpty == false)
    #expect(report.results[2].result == .completed(bytesReclaimed: 30))
    #expect(report.bytesReclaimed == 40)
    #expect(await fileSystem.exists(ExecutorFixture.path("/.Trash/item-one.log")))
    #expect(await fileSystem.exists(ExecutorFixture.path("/.Trash/item-three.log")))
  }
}
