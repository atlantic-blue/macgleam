import Foundation
import GleamCore
import Testing

@Suite("Executor denylist supremacy")
struct ExecutorDenylistSupremacyTests {
  @Test(
    "a hostile plan targeting a denylisted path is skipped as skippedDenylisted, the file stays, later items run"
  )
  func hostilePlanTargetingDenylistedPathIsSkipped() async throws {
    let fileSystem = InMemoryFileSystem()
    let first = ExecutorFixture.path("/Users/julian/Caches/one.log")
    let blocked = ExecutorFixture.path("/Users/julian/Blocked/keep.txt")
    let third = ExecutorFixture.path("/Users/julian/Caches/three.log")
    let blockedPayload = Data(repeating: 0xE2, count: 20)
    await fileSystem.seedFile(at: first, contents: Data(repeating: 0xE1, count: 10))
    await fileSystem.seedFile(at: blocked, contents: blockedPayload)
    await fileSystem.seedFile(at: third, contents: Data(repeating: 0xE3, count: 30))
    let denylist = try await ExecutorFixture.signedDenylist(blocking: ["/Users/julian/Blocked"])
    let plan = ExecutorFixture.plan(
      operations: [
        ExecutorFixture.trashOperation(target: first),
        ExecutorFixture.trashOperation(target: blocked),
        ExecutorFixture.trashOperation(target: third),
      ],
      totalBytes: 60
    )
    let executor = executorMake(fileSystem: fileSystem, denylist: denylist)

    let events = await executorCollect(executor, executing: plan)

    let report = try #require(executorFinalReport(in: events))
    #expect(
      report.results.map(\.result) == [
        .completed(bytesReclaimed: 10),
        .skippedDenylisted,
        .completed(bytesReclaimed: 30),
      ])
    #expect(report.bytesReclaimed == 40)
    #expect(await fileSystem.exists(blocked))
    #expect(try await fileSystem.readData(at: blocked, maxBytes: 100) == blockedPayload)
    #expect(await fileSystem.exists(first) == false)
    #expect(await fileSystem.exists(third) == false)
  }

  @Test("a target deep inside a denylisted directory is skipped through the descendant rule")
  func descendantOfDenylistedDirectoryIsSkipped() async throws {
    let fileSystem = InMemoryFileSystem()
    let deep = ExecutorFixture.path("/Users/julian/Blocked/nested/deeper/precious.db")
    let payload = Data(repeating: 0xF1, count: 15)
    await fileSystem.seedFile(at: deep, contents: payload)
    let denylist = try await ExecutorFixture.signedDenylist(blocking: ["/Users/julian/Blocked"])
    let plan = ExecutorFixture.plan(
      operations: [ExecutorFixture.trashOperation(target: deep)],
      totalBytes: 15
    )
    let executor = executorMake(fileSystem: fileSystem, denylist: denylist)

    let events = await executorCollect(executor, executing: plan)

    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.result) == [.skippedDenylisted])
    #expect(report.bytesReclaimed == 0)
    #expect(await fileSystem.exists(deep))
    #expect(try await fileSystem.readData(at: deep, maxBytes: 100) == payload)
  }

  @Test(
    "the denylist check precedes routing: a denylisted root operation is skipped, not refused for a missing helper"
  )
  func denylistedRootOperationIsSkippedNotRefused() async throws {
    let fileSystem = InMemoryFileSystem()
    let first = ExecutorFixture.path("/Users/julian/Caches/one.log")
    let blockedSystem = ExecutorFixture.path("/Library/Blocked/agent.plist")
    let third = ExecutorFixture.path("/Users/julian/Caches/three.log")
    await fileSystem.seedFile(at: first, contents: Data(repeating: 0x11, count: 10))
    await fileSystem.seedFile(at: blockedSystem, contents: Data(repeating: 0x12, count: 20))
    await fileSystem.seedFile(at: third, contents: Data(repeating: 0x13, count: 30))
    let denylist = try await ExecutorFixture.signedDenylist(blocking: ["/Library/Blocked"])
    let plan = ExecutorFixture.plan(
      operations: [
        ExecutorFixture.trashOperation(target: first),
        ExecutorFixture.trashOperation(target: blockedSystem, privilege: .root),
        ExecutorFixture.trashOperation(target: third),
      ],
      totalBytes: 60
    )
    let executor = executorMake(fileSystem: fileSystem, denylist: denylist)

    let events = await executorCollect(executor, executing: plan)

    #expect(executorHelperUnavailableReason(in: events) == nil)
    let report = try #require(executorFinalReport(in: events))
    #expect(
      report.results.map(\.result) == [
        .completed(bytesReclaimed: 10),
        .skippedDenylisted,
        .completed(bytesReclaimed: 30),
      ])
    #expect(await fileSystem.exists(blockedSystem))
  }
}
