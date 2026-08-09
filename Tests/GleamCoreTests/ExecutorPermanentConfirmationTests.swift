import Foundation
import GleamCore
import Testing

@Suite("Executor permanent deletion confirmation gate")
struct ExecutorPermanentConfirmationTests {
  private struct Fixture {
    let fileSystem: InMemoryFileSystem
    let first: AbsolutePath
    let second: AbsolutePath
    let firstPayload: Data
    let secondPayload: Data
    let operations: [ExecutorOperation]
  }

  private func makePermanentFixture() async -> Fixture {
    let fileSystem = InMemoryFileSystem()
    let first = ExecutorFixture.path("/Users/julian/Caches/perm-one.dat")
    let second = ExecutorFixture.path("/Users/julian/Caches/perm-two.dat")
    let firstPayload = Data(repeating: 0x21, count: 10)
    let secondPayload = Data(repeating: 0x22, count: 20)
    await fileSystem.seedFile(at: first, contents: firstPayload)
    await fileSystem.seedFile(at: second, contents: secondPayload)
    return Fixture(
      fileSystem: fileSystem,
      first: first,
      second: second,
      firstPayload: firstPayload,
      secondPayload: secondPayload,
      operations: [
        ExecutorFixture.permanentOperation(target: first),
        ExecutorFixture.permanentOperation(target: second),
      ]
    )
  }

  private func expectRefusedWhole(
    plan: OperationPlan,
    fixture: Fixture
  ) async throws {
    let executor = executorMake(
      fileSystem: fixture.fileSystem, denylist: try await ExecutorFixture.emptyDenylist())

    let events = await executorCollect(executor, executing: plan)

    let expectedReport = ExecutionReport(
      planID: plan.id,
      results: plan.operations.map { (operationID: $0.id, result: OperationResult.notStarted) },
      bytesReclaimed: 0,
      startedAt: ExecutorFixture.executionInstant,
      finishedAt: ExecutorFixture.executionInstant
    )
    #expect(
      events == [
        .refused(.permanentDeletionUnconfirmed),
        .planCompleted(expectedReport),
      ])
    #expect(await fixture.fileSystem.exists(fixture.first))
    #expect(await fixture.fileSystem.exists(fixture.second))
    #expect(
      try await fixture.fileSystem.readData(at: fixture.first, maxBytes: 100)
        == fixture.firstPayload)
    #expect(
      try await fixture.fileSystem.readData(at: fixture.second, maxBytes: 100)
        == fixture.secondPayload)
  }

  @Test("a permanent plan with no confirmation is refused whole before anything runs")
  func missingConfirmationRefusesWholePlan() async throws {
    let fixture = await makePermanentFixture()
    let plan = ExecutorFixture.plan(
      operations: fixture.operations, totalBytes: 30, confirmation: nil)
    try await expectRefusedWhole(plan: plan, fixture: fixture)
  }

  @Test("a confirmation whose file count does not match the permanent operations is refused whole")
  func mismatchedFileCountRefusesWholePlan() async throws {
    let fixture = await makePermanentFixture()
    let plan = ExecutorFixture.plan(
      operations: fixture.operations,
      totalBytes: 30,
      confirmation: ExecutorFixture.confirmation(fileCount: 3, byteTotal: 30)
    )
    try await expectRefusedWhole(plan: plan, fixture: fixture)
  }

  @Test("a confirmation whose byte total does not match the permanent operations is refused whole")
  func mismatchedByteTotalRefusesWholePlan() async throws {
    let fixture = await makePermanentFixture()
    let plan = ExecutorFixture.plan(
      operations: fixture.operations,
      totalBytes: 30,
      confirmation: ExecutorFixture.confirmation(fileCount: 2, byteTotal: 29)
    )
    try await expectRefusedWhole(plan: plan, fixture: fixture)
  }

  @Test("a permanent plan with an exactly matching confirmation executes and removes every target")
  func matchingConfirmationExecutesPermanentPlan() async throws {
    let fixture = await makePermanentFixture()
    let plan = ExecutorFixture.plan(
      operations: fixture.operations,
      totalBytes: 30,
      confirmation: ExecutorFixture.confirmation(fileCount: 2, byteTotal: 30)
    )
    let executor = executorMake(
      fileSystem: fixture.fileSystem, denylist: try await ExecutorFixture.emptyDenylist())

    let events = await executorCollect(executor, executing: plan)

    let report = try #require(executorFinalReport(in: events))
    #expect(
      report.results.map(\.result) == [
        .completed(bytesReclaimed: 10),
        .completed(bytesReclaimed: 20),
      ])
    #expect(report.bytesReclaimed == 30)
    #expect(await fixture.fileSystem.exists(fixture.first) == false)
    #expect(await fixture.fileSystem.exists(fixture.second) == false)
  }
}
