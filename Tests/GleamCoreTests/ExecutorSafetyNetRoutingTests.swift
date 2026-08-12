import Foundation
import GleamCore
import Testing
import os

/// Where a quarantine and an archive go, and who says how many bytes they
/// freed.
///
/// Both answers used to depend on the path's ownership: a system domain target
/// went to the helper as a removal into the store directory, so the payload
/// landed in the store with nothing recording it. The store holds the
/// manifest, so the store is the thing that must know an archive happened, and
/// it does its own routing inside.
@Suite("Executor SafetyNet routing")
struct ExecutorSafetyNetRoutingTests {

  private static let systemTarget = Fixture.path("/Library/Caches/com.example.helper")
  private static let userTarget = Fixture.path("/Users/julian/Caches/mine.log")

  private func make(
    safetyNet: RecordingSafetyNet,
    helper: RecordingPrivilegedPerformer
  ) -> PlanExecutor {
    PlanExecutor(
      fileSystem: InMemoryFileSystem(),
      denylist: makeDenylist([]),
      helper: helper,
      ownershipPolicy: ExecutorLibraryOwnershipPolicy(),
      environment: ExecutorFixture.environment,
      safetyNet: safetyNet,
      now: { ExecutorFixture.executionInstant },
      isCancelled: { false }
    )
  }

  private func operations(over target: AbsolutePath) -> [Operation] {
    [
      Operation(
        id: UUID(), findingID: UUID(), kind: .quarantine(target: target), privilege: .root),
      Operation(
        id: UUID(), findingID: UUID(), kind: .quarantine(target: target), privilege: .user),
      Operation(
        id: UUID(), findingID: UUID(), kind: .archive(target: target, groupID: UUID()),
        privilege: .root),
      Operation(
        id: UUID(), findingID: UUID(), kind: .archive(target: target, groupID: UUID()),
        privilege: .user),
    ]
  }

  @Test("every quarantine and archive reaches the store, whatever the ownership says")
  func everyQuarantineAndArchiveReachesTheStore() async throws {
    for target in [Self.systemTarget, Self.userTarget] {
      for operation in operations(over: target) {
        let safetyNet = RecordingSafetyNet()
        let helper = RecordingPrivilegedPerformer()
        let executor = make(safetyNet: safetyNet, helper: helper)

        _ = await executorCollect(
          executor, executing: ExecutorFixture.plan(operations: [operation], totalBytes: 0))

        #expect(await safetyNet.stored.map(\.path) == [target])
        #expect(
          helper.sawNothing,
          """
          a system domain archive sent to the helper moves a file into the \
          store without the store knowing, which is the defect this closes
          """)
      }
    }
  }

  @Test("the bytes reported are the size the store recorded, never one measured here")
  func theBytesReportedAreTheSizeTheStoreRecorded() async throws {
    let safetyNet = RecordingSafetyNet()
    await safetyNet.recordAllocatedBytes(9_999)
    let executor = make(safetyNet: safetyNet, helper: RecordingPrivilegedPerformer())
    let operation = Operation(
      id: UUID(), findingID: UUID(), kind: .quarantine(target: Self.systemTarget),
      privilege: .root)

    let events = await executorCollect(
      executor, executing: ExecutorFixture.plan(operations: [operation], totalBytes: 0))

    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.result) == [.completed(bytesReclaimed: 9_999)])
  }

  @Test("a store that refuses fails that operation and leaves the run going")
  func aStoreThatRefusesFailsThatOperationOnly() async throws {
    let safetyNet = RecordingSafetyNet()
    await safetyNet.refuseEverything()
    let executor = make(safetyNet: safetyNet, helper: RecordingPrivilegedPerformer())
    let quarantine = Operation(
      id: UUID(), findingID: UUID(), kind: .quarantine(target: Self.systemTarget),
      privilege: .root)
    let maintenance = Operation(
      id: UUID(), findingID: UUID(),
      kind: .runMaintenance(task: .flushDomainNameSystemCache), privilege: .root)

    let events = await executorCollect(
      executor,
      executing: ExecutorFixture.plan(operations: [quarantine, maintenance], totalBytes: 0))

    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.count == 2)
    guard case .failed = report.results.first?.result else {
      Issue.record("a store that refused cannot report a completed archive")
      return
    }
  }

  @Test("an executor with no store fails an archive rather than sending it to the helper")
  func anExecutorWithNoStoreFailsAnArchive() async throws {
    let helper = RecordingPrivilegedPerformer()
    let executor = PlanExecutor(
      fileSystem: InMemoryFileSystem(),
      denylist: makeDenylist([]),
      helper: helper,
      ownershipPolicy: ExecutorLibraryOwnershipPolicy(),
      environment: ExecutorFixture.environment,
      now: { ExecutorFixture.executionInstant },
      isCancelled: { false }
    )
    let operation = Operation(
      id: UUID(), findingID: UUID(), kind: .quarantine(target: Self.systemTarget),
      privilege: .root)

    let events = await executorCollect(
      executor, executing: ExecutorFixture.plan(operations: [operation], totalBytes: 0))

    #expect(helper.sawNothing)
    let report = try #require(executorFinalReport(in: events))
    guard case .failed = report.results.first?.result else {
      Issue.record("no store means no archive, said out loud")
      return
    }
  }

  @Test("a denylisted archive is skipped before the store hears about it")
  func aDenylistedArchiveIsSkippedBeforeTheStoreHearsAboutIt() async throws {
    let safetyNet = RecordingSafetyNet()
    let executor = PlanExecutor(
      fileSystem: InMemoryFileSystem(),
      denylist: makeDenylist([Self.systemTarget.value]),
      helper: RecordingPrivilegedPerformer(),
      ownershipPolicy: ExecutorLibraryOwnershipPolicy(),
      environment: ExecutorFixture.environment,
      safetyNet: safetyNet,
      now: { ExecutorFixture.executionInstant },
      isCancelled: { false }
    )
    let operation = Operation(
      id: UUID(), findingID: UUID(), kind: .quarantine(target: Self.systemTarget),
      privilege: .root)

    let events = await executorCollect(
      executor, executing: ExecutorFixture.plan(operations: [operation], totalBytes: 0))

    #expect(await safetyNet.stored.isEmpty)
    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.result) == [.skippedDenylisted])
  }
}

/// The store at the boundary the executor sees. It records what it was asked
/// to hold and answers with an item, so a test can tell an archive that
/// reached the store from one that went somewhere else.
actor RecordingSafetyNet: SafetyNetStoring {
  struct Stored: Sendable, Equatable {
    let path: AbsolutePath
    let source: SafetyNetItem.Source
    let groupID: UUID?
  }

  private(set) var stored: [Stored] = []
  private var allocatedBytes: UInt64 = 64
  private var refuses = false

  func recordAllocatedBytes(_ bytes: UInt64) { allocatedBytes = bytes }
  func refuseEverything() { refuses = true }

  func store(
    _ path: AbsolutePath,
    source: SafetyNetItem.Source,
    groupID: UUID?
  ) async throws -> SafetyNetItem {
    if refuses { throw SafetyNetError.privilegeUnavailable(path) }
    stored.append(Stored(path: path, source: source, groupID: groupID))
    let identifier = UUID()
    return SafetyNetItem(
      id: identifier,
      originPath: path,
      storedPath: Fixture.path("/store/payloads/" + identifier.uuidString),
      source: source,
      groupID: groupID,
      metadata: FileMetadataSnapshot(
        posixPermissions: 0o755, extendedAttributes: [:], created: nil, modified: nil),
      allocatedBytes: allocatedBytes,
      storedAt: ExecutorFixture.executionInstant,
      expiresAt: ExecutorFixture.executionInstant,
      isRestored: false)
  }

  func items(includingRestored: Bool) async throws -> [SafetyNetItem] { [] }
  func restore(itemID: UUID) async throws {}
  func restoreGroup(groupID: UUID) async throws {}
  func purge(itemIDs: [UUID], confirmation: PurgeConfirmation) async throws {}
  func purgeEligibleItems(asOf now: Date) async throws -> [SafetyNetItem] { [] }
}
