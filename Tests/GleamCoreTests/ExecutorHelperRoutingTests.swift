import Foundation
import GleamCore
import Testing

/// C17's routing rule with a helper on the far side: "before every operation,
/// in this order: denylist check, ownership routing (userDomain runs in
/// process, systemDomain goes to the helper as a typed request)".
///
/// The s1e tests pinned the half of that rule the app could keep on its own,
/// which is the refusal when there is no helper at all. These pin the other
/// half. Two properties matter more than the rest and are tested from both
/// sides: nothing the user process can do itself is ever sent, and nothing the
/// denylist blocks is ever sent.
@Suite("Executor routing to the helper")
struct ExecutorHelperRoutingTests {

  // MARK: What goes to the helper

  @Test("a system domain operation is handed to the helper instead of refusing the plan")
  func systemDomainOperationIsHandedToTheHelper() async throws {
    let fileSystem = InMemoryFileSystem()
    let systemTarget = ExecutorFixture.path("/Library/Application Support/Example/cache.db")
    await fileSystem.seedFile(at: systemTarget, contents: Data(repeating: 0x11, count: 40))
    let operation = ExecutorFixture.trashOperation(target: systemTarget, privilege: .root)
    let plan = ExecutorFixture.plan(operations: [operation], totalBytes: 40)
    let helper = RecordingPrivilegedPerformer(
      results: [operation.id: .completed(bytesReclaimed: 40)])
    let executor = executorMakeWithHelper(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist(), helper: helper)

    let events = await executorCollect(executor, executing: plan)

    #expect(helper.handedOverOperationIDs == [operation.id])
    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.result) == [.completed(bytesReclaimed: 40)])
    #expect(report.bytesReclaimed == 40)
  }

  @Test("a system domain operation reaches the helper with the plan it belongs to")
  func handoverNamesThePlanTheOperationBelongsTo() async throws {
    let fileSystem = InMemoryFileSystem()
    let systemTarget = ExecutorFixture.path("/Library/Caches/example.db")
    await fileSystem.seedFile(at: systemTarget, contents: Data(repeating: 0x12, count: 10))
    let operation = ExecutorFixture.trashOperation(target: systemTarget, privilege: .root)
    let plan = ExecutorFixture.plan(operations: [operation], totalBytes: 10)
    let helper = RecordingPrivilegedPerformer()
    let executor = executorMakeWithHelper(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist(), helper: helper)

    _ = await executorCollect(executor, executing: plan)

    #expect(
      helper.handovers == [
        PrivilegedHandover(
          operationID: operation.id, planID: plan.id, kind: .moveToTrash(target: systemTarget))
      ],
      "C30 requires every mutating request to name its plan and its operation")
  }

  @Test("a root maintenance task, which names no path, is handed to the helper")
  func rootMaintenanceTaskIsHandedToTheHelper() async throws {
    let operation = ExecutorFixture.maintenanceOperation(
      task: .flushDomainNameSystemCache, privilege: .root)
    let plan = ExecutorFixture.plan(operations: [operation], totalBytes: 0)
    let helper = RecordingPrivilegedPerformer()
    let executor = executorMakeWithHelper(
      fileSystem: InMemoryFileSystem(), denylist: try await ExecutorFixture.emptyDenylist(),
      helper: helper)

    let events = await executorCollect(executor, executing: plan)

    #expect(helper.handedOverOperationIDs == [operation.id])
    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.result) == [.completed(bytesReclaimed: 0)])
  }

  @Test(
    "a root launch item change, which names an item rather than a path, is handed to the helper")
  func rootLaunchItemChangeIsHandedToTheHelper() async throws {
    let operation = ExecutorFixture.launchItemOperation(
      label: "com.example.daemon", enabled: false, privilege: .root)
    let plan = ExecutorFixture.plan(operations: [operation], totalBytes: 0)
    let helper = RecordingPrivilegedPerformer()
    let executor = executorMakeWithHelper(
      fileSystem: InMemoryFileSystem(), denylist: try await ExecutorFixture.emptyDenylist(),
      helper: helper)

    _ = await executorCollect(executor, executing: plan)

    #expect(helper.handedOverOperationIDs == [operation.id])
  }

  @Test("an operation the helper completed still emits started then finished, in that order")
  func helperOperationEmitsStartedThenFinished() async throws {
    let fileSystem = InMemoryFileSystem()
    let systemTarget = ExecutorFixture.path("/Library/Caches/events.db")
    await fileSystem.seedFile(at: systemTarget, contents: Data(repeating: 0x13, count: 5))
    let operation = ExecutorFixture.trashOperation(target: systemTarget, privilege: .root)
    let plan = ExecutorFixture.plan(operations: [operation], totalBytes: 5)
    let helper = RecordingPrivilegedPerformer(
      results: [operation.id: .completed(bytesReclaimed: 5)])
    let executor = executorMakeWithHelper(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist(), helper: helper)

    let events = await executorCollect(executor, executing: plan)

    #expect(events.count == 3)
    #expect(events.first == .operationStarted(operationID: operation.id))
    #expect(
      events[1]
        == .operationFinished(operationID: operation.id, result: .completed(bytesReclaimed: 5)))
    #expect(executorFinalReport(in: events) != nil)
  }

  @Test("the bytes the helper reclaimed are counted in the report total")
  func helperBytesAreCountedInTheReport() async throws {
    let fileSystem = InMemoryFileSystem()
    let userTarget = ExecutorFixture.path("/Users/julian/Caches/local.log")
    let systemTarget = ExecutorFixture.path("/Library/Caches/remote.db")
    await fileSystem.seedFile(at: userTarget, contents: Data(repeating: 0x14, count: 100))
    await fileSystem.seedFile(at: systemTarget, contents: Data(repeating: 0x15, count: 200))
    let systemOperation = ExecutorFixture.trashOperation(target: systemTarget, privilege: .root)
    let plan = ExecutorFixture.plan(
      operations: [ExecutorFixture.trashOperation(target: userTarget), systemOperation],
      totalBytes: 300)
    let helper = RecordingPrivilegedPerformer(
      results: [systemOperation.id: .completed(bytesReclaimed: 200)])
    let executor = executorMakeWithHelper(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist(), helper: helper)

    let events = await executorCollect(executor, executing: plan)

    let report = try #require(executorFinalReport(in: events))
    #expect(report.bytesReclaimed == 300)
  }

  @Test("with a helper connected, no operation is refused as helperUnavailable")
  func connectedHelperNeverRefusesTheRun() async throws {
    let fileSystem = InMemoryFileSystem()
    let systemTarget = ExecutorFixture.path("/Library/Caches/connected.db")
    await fileSystem.seedFile(at: systemTarget, contents: Data(repeating: 0x16, count: 10))
    let plan = ExecutorFixture.plan(
      operations: [ExecutorFixture.trashOperation(target: systemTarget, privilege: .root)],
      totalBytes: 10)
    let executor = executorMakeWithHelper(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist(),
      helper: RecordingPrivilegedPerformer())

    let events = await executorCollect(executor, executing: plan)

    #expect(executorHelperUnavailableReason(in: events) == nil)
  }

  // MARK: What never goes to the helper

  @Test("a user domain operation never reaches the helper")
  func userDomainOperationNeverReachesTheHelper() async throws {
    let fileSystem = InMemoryFileSystem()
    let userTarget = ExecutorFixture.path("/Users/julian/Caches/mine.log")
    await fileSystem.seedFile(at: userTarget, contents: Data(repeating: 0x17, count: 10))
    let plan = ExecutorFixture.plan(
      operations: [ExecutorFixture.trashOperation(target: userTarget)], totalBytes: 10)
    let helper = RecordingPrivilegedPerformer()
    let executor = executorMakeWithHelper(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist(), helper: helper)

    let events = await executorCollect(executor, executing: plan)

    #expect(
      helper.sawNothing,
      "least privilege cuts both ways: the helper does no work the user process can do")
    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.result) == [.completed(bytesReclaimed: 10)])
    #expect(await fileSystem.exists(ExecutorFixture.path("/.Trash/mine.log")))
  }

  @Test("a user domain target labelled root at plan time still runs in process")
  func userDomainTargetLabelledRootStillRunsInProcess() async throws {
    let fileSystem = InMemoryFileSystem()
    let userTarget = ExecutorFixture.path("/Users/julian/Caches/mislabelled.log")
    await fileSystem.seedFile(at: userTarget, contents: Data(repeating: 0x18, count: 10))
    let plan = ExecutorFixture.plan(
      operations: [ExecutorFixture.trashOperation(target: userTarget, privilege: .root)],
      totalBytes: 10)
    let helper = RecordingPrivilegedPerformer()
    let executor = executorMakeWithHelper(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist(), helper: helper)

    let events = await executorCollect(executor, executing: plan)

    #expect(
      helper.sawNothing,
      "ownership at run time decides the route, not the label the plan carries")
    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.result) == [.completed(bytesReclaimed: 10)])
  }

  @Test("a denylisted system domain target is skipped and never handed to the helper")
  func denylistedSystemTargetIsNeverHandedToTheHelper() async throws {
    let fileSystem = InMemoryFileSystem()
    let blocked = ExecutorFixture.path("/Library/Blocked/com.example.agent.plist")
    let payload = Data(repeating: 0x19, count: 20)
    await fileSystem.seedFile(at: blocked, contents: payload)
    let plan = ExecutorFixture.plan(
      operations: [ExecutorFixture.trashOperation(target: blocked, privilege: .root)],
      totalBytes: 20)
    let helper = RecordingPrivilegedPerformer()
    let executor = executorMakeWithHelper(
      fileSystem: fileSystem,
      denylist: try await ExecutorFixture.signedDenylist(blocking: ["/Library/Blocked"]),
      helper: helper)

    let events = await executorCollect(executor, executing: plan)

    #expect(
      helper.sawNothing,
      "the denylist is checked before routing, so a blocked target is never transmitted")
    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.result) == [.skippedDenylisted])
    #expect(await fileSystem.exists(blocked))
    #expect(try await fileSystem.readData(at: blocked, maxBytes: 100) == payload)
  }

  @Test("a denylisted target between two system operations blocks only itself")
  func denylistBlocksOnlyItselfAmongSystemOperations() async throws {
    let fileSystem = InMemoryFileSystem()
    let first = ExecutorFixture.path("/Library/Caches/first.db")
    let blocked = ExecutorFixture.path("/Library/Blocked/keep.plist")
    let third = ExecutorFixture.path("/Library/Caches/third.db")
    for path in [first, blocked, third] {
      await fileSystem.seedFile(at: path, contents: Data(repeating: 0x1A, count: 10))
    }
    let operations = [first, blocked, third].map {
      ExecutorFixture.trashOperation(target: $0, privilege: .root)
    }
    let plan = ExecutorFixture.plan(operations: operations, totalBytes: 30)
    let helper = RecordingPrivilegedPerformer(otherwise: .completed(bytesReclaimed: 10))
    let executor = executorMakeWithHelper(
      fileSystem: fileSystem,
      denylist: try await ExecutorFixture.signedDenylist(blocking: ["/Library/Blocked"]),
      helper: helper)

    let events = await executorCollect(executor, executing: plan)

    #expect(helper.handedOverOperationIDs == [operations[0].id, operations[2].id])
    let report = try #require(executorFinalReport(in: events))
    #expect(
      report.results.map(\.result) == [
        .completed(bytesReclaimed: 10),
        .skippedDenylisted,
        .completed(bytesReclaimed: 10),
      ])
  }

  // MARK: One operation failing is not the run failing

  @Test("a helper failure fails that one operation and the plan continues")
  func helperFailureFailsOneOperationAndThePlanContinues() async throws {
    let fileSystem = InMemoryFileSystem()
    let systemTarget = ExecutorFixture.path("/Library/Caches/doomed.db")
    let laterUserTarget = ExecutorFixture.path("/Users/julian/Caches/later.log")
    await fileSystem.seedFile(at: systemTarget, contents: Data(repeating: 0x1B, count: 10))
    await fileSystem.seedFile(at: laterUserTarget, contents: Data(repeating: 0x1C, count: 30))
    let failing = ExecutorFixture.trashOperation(target: systemTarget, privilege: .root)
    let later = ExecutorFixture.trashOperation(target: laterUserTarget)
    let plan = ExecutorFixture.plan(operations: [failing, later], totalBytes: 40)
    let helper = RecordingPrivilegedPerformer(
      results: [
        failing.id: .failed(reason: "The helper could not remove that file, so it is still there.")
      ])
    let executor = executorMakeWithHelper(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist(), helper: helper)

    let events = await executorCollect(executor, executing: plan)

    let report = try #require(executorFinalReport(in: events))
    try expectPlainSentence(executorFailureReason(report.results.first?.result))
    #expect(report.results.map(\.result).last == .completed(bytesReclaimed: 30))
    #expect(report.bytesReclaimed == 30)
    #expect(executorStartedOperationIDs(in: events) == [failing.id, later.id])
    #expect(
      executorHelperUnavailableReason(in: events) == nil,
      "one operation failing is not the run failing")
  }

  @Test("every operation of a mixed plan appears once, in plan order, whichever side ran it")
  func mixedPlanReportsEveryOperationInOrder() async throws {
    let fileSystem = InMemoryFileSystem()
    let paths = [
      ExecutorFixture.path("/Users/julian/Caches/a.log"),
      ExecutorFixture.path("/Library/Caches/b.db"),
      ExecutorFixture.path("/Users/julian/Caches/c.log"),
      ExecutorFixture.path("/Library/Caches/d.db"),
    ]
    for path in paths {
      await fileSystem.seedFile(at: path, contents: Data(repeating: 0x1D, count: 10))
    }
    let operations = [
      ExecutorFixture.trashOperation(target: paths[0]),
      ExecutorFixture.trashOperation(target: paths[1], privilege: .root),
      ExecutorFixture.trashOperation(target: paths[2]),
      ExecutorFixture.trashOperation(target: paths[3], privilege: .root),
    ]
    let plan = ExecutorFixture.plan(operations: operations, totalBytes: 40)
    let helper = RecordingPrivilegedPerformer(otherwise: .completed(bytesReclaimed: 10))
    let executor = executorMakeWithHelper(
      fileSystem: fileSystem, denylist: try await ExecutorFixture.emptyDenylist(), helper: helper)

    let events = await executorCollect(executor, executing: plan)

    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.operationID) == operations.map(\.id))
    #expect(helper.handedOverOperationIDs == [operations[1].id, operations[3].id])
    #expect(report.results.allSatisfy { $0.result == .completed(bytesReclaimed: 10) })
  }
}
