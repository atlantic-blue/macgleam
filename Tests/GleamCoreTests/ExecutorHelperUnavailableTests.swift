import Foundation
import GleamCore
import Testing

@Suite("Executor without a helper")
struct ExecutorHelperUnavailableTests {
  @Test(
    "reaching a system domain operation with no helper refuses with helperUnavailable, keeps earlier work, starts nothing more"
  )
  func systemDomainOperationRefusesWithHelperUnavailable() async throws {
    let fileSystem = InMemoryFileSystem()
    let first = ExecutorFixture.path("/Users/julian/Caches/root-one.log")
    let systemTarget = ExecutorFixture.path("/Library/Application Support/Example/cache.db")
    let third = ExecutorFixture.path("/Users/julian/Caches/root-three.log")
    let systemPayload = Data(repeating: 0x82, count: 20)
    let thirdPayload = Data(repeating: 0x83, count: 30)
    await fileSystem.seedFile(at: first, contents: Data(repeating: 0x81, count: 10))
    await fileSystem.seedFile(at: systemTarget, contents: systemPayload)
    await fileSystem.seedFile(at: third, contents: thirdPayload)
    let plan = ExecutorFixture.plan(
      operations: [
        ExecutorFixture.trashOperation(target: first),
        ExecutorFixture.trashOperation(target: systemTarget, privilege: .root),
        ExecutorFixture.trashOperation(target: third),
      ],
      totalBytes: 60
    )
    let executor = executorMake(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist())

    let events = await executorCollect(executor, executing: plan)

    let reason = try #require(executorHelperUnavailableReason(in: events))
    #expect(reason.isEmpty == false)
    #expect(executorStartedOperationIDs(in: events) == [plan.operations[0].id])
    let report = try #require(executorFinalReport(in: events))
    #expect(
      report.results.map(\.result) == [
        .completed(bytesReclaimed: 10),
        .notStarted,
        .notStarted,
      ])
    #expect(report.bytesReclaimed == 10)
    #expect(await fileSystem.exists(ExecutorFixture.path("/.Trash/root-one.log")))
    #expect(await fileSystem.exists(systemTarget))
    #expect(try await fileSystem.readData(at: systemTarget, maxBytes: 100) == systemPayload)
    #expect(await fileSystem.exists(third))
    #expect(try await fileSystem.readData(at: third, maxBytes: 100) == thirdPayload)
  }

  @Test("a root maintenance task with no helper refuses with helperUnavailable and mutates nothing")
  func rootMaintenanceTaskRefusesWithHelperUnavailable() async throws {
    let fileSystem = InMemoryFileSystem()
    let first = ExecutorFixture.path("/Users/julian/Caches/maint-one.log")
    await fileSystem.seedFile(at: first, contents: Data(repeating: 0x91, count: 10))
    let plan = ExecutorFixture.plan(
      operations: [
        ExecutorFixture.trashOperation(target: first),
        ExecutorFixture.maintenanceOperation(task: .flushDomainNameSystemCache, privilege: .root),
      ],
      totalBytes: 10
    )
    let executor = executorMake(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist())

    let events = await executorCollect(executor, executing: plan)

    let reason = try #require(executorHelperUnavailableReason(in: events))
    #expect(reason.isEmpty == false)
    let report = try #require(executorFinalReport(in: events))
    #expect(
      report.results.map(\.result) == [
        .completed(bytesReclaimed: 10),
        .notStarted,
      ])
    #expect(await fileSystem.exists(ExecutorFixture.path("/.Trash/maint-one.log")))
  }

  @Test("a root scope launch item change with no helper refuses with helperUnavailable")
  func rootLaunchItemChangeRefusesWithHelperUnavailable() async throws {
    let fileSystem = InMemoryFileSystem()
    let plan = ExecutorFixture.plan(
      operations: [
        ExecutorFixture.launchItemOperation(
          label: "com.example.daemon", enabled: false, privilege: .root)
      ],
      totalBytes: 0
    )
    let executor = executorMake(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist())

    let events = await executorCollect(executor, executing: plan)

    let reason = try #require(executorHelperUnavailableReason(in: events))
    #expect(reason.isEmpty == false)
    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.result) == [.notStarted])
    #expect(report.bytesReclaimed == 0)
  }
}
