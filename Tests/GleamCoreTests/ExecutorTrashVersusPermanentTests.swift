import Foundation
import GleamCore
import Testing

@Suite("Executor trash versus permanent")
struct ExecutorTrashVersusPermanentTests {
  @Test("moveToTrash relocates the payload into the trash where it remains restorable")
  func moveToTrashLeavesThePayloadRestorable() async throws {
    let fileSystem = InMemoryFileSystem()
    let target = ExecutorFixture.path("/Users/julian/Downloads/report.pdf")
    let payload = Data(repeating: 0x31, count: 40)
    await fileSystem.seedFile(at: target, contents: payload)
    let plan = ExecutorFixture.plan(
      operations: [ExecutorFixture.trashOperation(target: target)],
      totalBytes: 40
    )
    let executor = executorMake(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist())

    let events = await executorCollect(executor, executing: plan)

    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.result) == [.completed(bytesReclaimed: 40)])
    #expect(await fileSystem.exists(target) == false)
    let trashLocation = ExecutorFixture.path("/.Trash/report.pdf")
    #expect(await fileSystem.exists(trashLocation))
    #expect(try await fileSystem.readData(at: trashLocation, maxBytes: 100) == payload)
  }

  @Test("deletePermanently removes the target outright, leaving nothing in the trash")
  func deletePermanentlyLeavesNothingInTheTrash() async throws {
    let fileSystem = InMemoryFileSystem()
    let target = ExecutorFixture.path("/Users/julian/Downloads/secret.dat")
    await fileSystem.seedFile(at: target, contents: Data(repeating: 0x32, count: 40))
    let plan = ExecutorFixture.plan(
      operations: [ExecutorFixture.permanentOperation(target: target)],
      totalBytes: 40,
      confirmation: ExecutorFixture.confirmation(fileCount: 1, byteTotal: 40)
    )
    let executor = executorMake(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist())

    let events = await executorCollect(executor, executing: plan)

    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.result) == [.completed(bytesReclaimed: 40)])
    #expect(await fileSystem.exists(target) == false)
    #expect(await fileSystem.exists(ExecutorFixture.path("/.Trash/secret.dat")) == false)
  }

  @Test("a mixed plan trashes the trash operations and permanently removes the permanent ones")
  func mixedPlanBehavesPerOperationKind() async throws {
    let fileSystem = InMemoryFileSystem()
    let trashTarget = ExecutorFixture.path("/Users/julian/Caches/kept-around.log")
    let permanentTarget = ExecutorFixture.path("/Users/julian/Caches/gone-for-good.log")
    let trashPayload = Data(repeating: 0x33, count: 10)
    await fileSystem.seedFile(at: trashTarget, contents: trashPayload)
    await fileSystem.seedFile(at: permanentTarget, contents: Data(repeating: 0x34, count: 20))
    let plan = ExecutorFixture.plan(
      operations: [
        ExecutorFixture.trashOperation(target: trashTarget),
        ExecutorFixture.permanentOperation(target: permanentTarget),
      ],
      totalBytes: 30,
      confirmation: ExecutorFixture.confirmation(fileCount: 1, byteTotal: 20)
    )
    let executor = executorMake(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist())

    let events = await executorCollect(executor, executing: plan)

    let report = try #require(executorFinalReport(in: events))
    #expect(
      report.results.map(\.result) == [
        .completed(bytesReclaimed: 10),
        .completed(bytesReclaimed: 20),
      ])
    #expect(report.bytesReclaimed == 30)
    #expect(await fileSystem.exists(ExecutorFixture.path("/.Trash/kept-around.log")))
    #expect(
      try await fileSystem.readData(
        at: ExecutorFixture.path("/.Trash/kept-around.log"), maxBytes: 100) == trashPayload)
    #expect(await fileSystem.exists(permanentTarget) == false)
    #expect(await fileSystem.exists(ExecutorFixture.path("/.Trash/gone-for-good.log")) == false)
  }
}
