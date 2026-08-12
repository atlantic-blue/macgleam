import Foundation
import GleamCore
import GleamHelperClient
import GleamHelperCore
import Testing

/// The whole s3b path with nothing faked but the two boundaries: the real
/// executor, the real helper client, the real registration coordinator, a
/// system service double whose status a human moves, and a transport double
/// that records what crossed.
///
/// The behaviour that matters here is the one a user meets on day one. They
/// have never approved anything, they run a clean that touches both their own
/// caches and a system location, and the app has to do the half it can, tell
/// them plainly which half is waiting on them, and prompt for approval once
/// rather than once per file.
@Suite("A plan run against a helper that is not approved yet")
struct ExecutorDegradedHelperTests {

  private func mixedPlan() -> (plan: OperationPlan, operations: [PlanOperation]) {
    let operations = [
      HelperClientFixture.trash(HelperClientFixture.userTarget, privilege: .user),
      HelperClientFixture.trash(HelperClientFixture.systemTarget),
      HelperClientFixture.trash(HelperClientFixture.otherUserTarget, privilege: .user),
      HelperClientFixture.maintenance(),
    ]
    return (HelperClientFixture.plan(operations, totalBytes: 40), operations)
  }

  private func seedUserTargets(_ fileSystem: InMemoryFileSystem) async {
    await fileSystem.seedFile(
      at: HelperClientFixture.userTarget, contents: Data(repeating: 0x21, count: 10))
    await fileSystem.seedFile(
      at: HelperClientFixture.otherUserTarget, contents: Data(repeating: 0x22, count: 30))
    await fileSystem.seedFile(
      at: HelperClientFixture.systemTarget, contents: Data(repeating: 0x23, count: 100))
  }

  // MARK: Nothing privileged is asked for until something privileged is needed

  @Test("a plan of only user operations never registers the helper and transmits nothing")
  func userOnlyPlanNeverRegistersTheHelper() async throws {
    let fileSystem = InMemoryFileSystem()
    await seedUserTargets(fileSystem)
    let service = FakeHelperService(status: .notRegistered)
    let transport = RecordingHelperTransport()
    let client = makeHelperClient(
      transport: transport, registration: makeRegistrationCoordinator(service: service))
    let plan = HelperClientFixture.plan(
      [
        HelperClientFixture.trash(HelperClientFixture.userTarget, privilege: .user),
        HelperClientFixture.trash(HelperClientFixture.otherUserTarget, privilege: .user),
      ], totalBytes: 40)
    let executor = makeExecutor(
      fileSystem: fileSystem, denylist: try await HelperClientFixture.emptyDenylist(),
      helper: client)

    let events = await collect(executor, executing: plan)

    #expect(
      service.registerCallCount == 0,
      "nothing privileged was needed, so nothing was asked of the user")
    #expect(transport.transmittedNothing)
    let report = try #require(finalReport(in: events))
    #expect(
      report.results.map(\.result) == [
        .completed(bytesReclaimed: 10),
        .completed(bytesReclaimed: 30),
      ])
  }

  @Test("building the app's helper stack registers nothing until a plan runs")
  func buildingTheStackRegistersNothing() async throws {
    let service = FakeHelperService(status: .notRegistered)
    let client = makeHelperClient(
      transport: RecordingHelperTransport(),
      registration: makeRegistrationCoordinator(service: service))

    _ = makeExecutor(
      fileSystem: InMemoryFileSystem(), denylist: try await HelperClientFixture.emptyDenylist(),
      helper: client)

    #expect(service.registerCallCount == 0, "first launch must not prompt for anything")
  }

  @Test("the first system domain operation of a plan is what triggers registration")
  func firstSystemDomainOperationTriggersRegistration() async throws {
    let fileSystem = InMemoryFileSystem()
    await seedUserTargets(fileSystem)
    let service = FakeHelperService(status: .notRegistered)
    let client = makeHelperClient(
      transport: RecordingHelperTransport(),
      registration: makeRegistrationCoordinator(service: service))
    let (plan, _) = mixedPlan()
    let executor = makeExecutor(
      fileSystem: fileSystem, denylist: try await HelperClientFixture.emptyDenylist(),
      helper: client)

    _ = await collect(executor, executing: plan)

    #expect(service.registerCallCount == 1)
  }

  @Test("a plan holding two root operations still asks the user once")
  func twoRootOperationsAskOnce() async throws {
    let fileSystem = InMemoryFileSystem()
    await seedUserTargets(fileSystem)
    let service = FakeHelperService(status: .notRegistered)
    let client = makeHelperClient(
      transport: RecordingHelperTransport(),
      registration: makeRegistrationCoordinator(service: service))
    let (plan, _) = mixedPlan()
    let executor = makeExecutor(
      fileSystem: fileSystem, denylist: try await HelperClientFixture.emptyDenylist(),
      helper: client)

    _ = await collect(executor, executing: plan)

    #expect(
      service.registerCallCount == 1, "one approval prompt per install, not one per operation")
  }

  // MARK: The degraded run

  @Test("with approval outstanding, the user half of a plan completes and the root half waits")
  func userHalfCompletesAndRootHalfWaits() async throws {
    let fileSystem = InMemoryFileSystem()
    await seedUserTargets(fileSystem)
    let service = FakeHelperService(status: .notRegistered)
    let client = makeHelperClient(
      transport: RecordingHelperTransport(),
      registration: makeRegistrationCoordinator(service: service))
    let (plan, operations) = mixedPlan()
    let executor = makeExecutor(
      fileSystem: fileSystem, denylist: try await HelperClientFixture.emptyDenylist(),
      helper: client)

    let events = await collect(executor, executing: plan)

    let report = try #require(finalReport(in: events))
    #expect(report.results.map(\.operationID) == operations.map { $0.id })
    #expect(report.results[0].result == .completed(bytesReclaimed: 10))
    #expect(report.results[2].result == .completed(bytesReclaimed: 30))
    try expectApprovalSentence(failureReason(report.results[1].result))
    try expectApprovalSentence(failureReason(report.results[3].result))
    #expect(report.bytesReclaimed == 40)
  }

  @Test("with approval outstanding, the run is not refused whole")
  func degradedRunIsNotRefusedWhole() async throws {
    let fileSystem = InMemoryFileSystem()
    await seedUserTargets(fileSystem)
    let client = makeHelperClient(
      transport: RecordingHelperTransport(),
      registration: makeRegistrationCoordinator(service: FakeHelperService(status: .notRegistered)))
    let (plan, operations) = mixedPlan()
    let executor = makeExecutor(
      fileSystem: fileSystem, denylist: try await HelperClientFixture.emptyDenylist(),
      helper: client)

    let events = await collect(executor, executing: plan)

    #expect(helperUnavailableReason(in: events) == nil)
    let report = try #require(finalReport(in: events))
    #expect(
      report.results.contains { $0.result == .notStarted } == false,
      "waiting on approval stops the root half, never the run")
    #expect(report.results.count == operations.count)
  }

  @Test("with approval outstanding, nothing is transmitted to the helper")
  func nothingIsTransmittedWhileApprovalIsOutstanding() async throws {
    let fileSystem = InMemoryFileSystem()
    await seedUserTargets(fileSystem)
    let transport = RecordingHelperTransport()
    let client = makeHelperClient(
      transport: transport,
      registration: makeRegistrationCoordinator(service: FakeHelperService(status: .notRegistered)))
    let (plan, _) = mixedPlan()
    let executor = makeExecutor(
      fileSystem: fileSystem, denylist: try await HelperClientFixture.emptyDenylist(),
      helper: client)

    _ = await collect(executor, executing: plan)

    #expect(transport.transmittedNothing, "there is no one on the other end yet")
  }

  @Test("with approval outstanding, the system domain file is left exactly as it was")
  func systemFileIsUntouchedWhileApprovalIsOutstanding() async throws {
    let fileSystem = InMemoryFileSystem()
    await seedUserTargets(fileSystem)
    let payload = Data(repeating: 0x23, count: 100)
    let client = makeHelperClient(
      transport: RecordingHelperTransport(),
      registration: makeRegistrationCoordinator(service: FakeHelperService(status: .notRegistered)))
    let (plan, _) = mixedPlan()
    let executor = makeExecutor(
      fileSystem: fileSystem, denylist: try await HelperClientFixture.emptyDenylist(),
      helper: client)

    _ = await collect(executor, executing: plan)

    #expect(await fileSystem.exists(HelperClientFixture.systemTarget))
    #expect(
      try await fileSystem.readData(at: HelperClientFixture.systemTarget, maxBytes: 200) == payload)
  }

  @Test(
    "a helper the user refused outright reports its own plain sentence and the user half still runs"
  )
  func refusedHelperStillLetsTheUserHalfRun() async throws {
    let fileSystem = InMemoryFileSystem()
    await seedUserTargets(fileSystem)
    let service = FakeHelperService(
      status: .notRegistered, onRegister: .throwsOperationNotPermittedAndStaysNotRegistered)
    let client = makeHelperClient(
      transport: RecordingHelperTransport(),
      registration: makeRegistrationCoordinator(service: service))
    let (plan, _) = mixedPlan()
    let executor = makeExecutor(
      fileSystem: fileSystem, denylist: try await HelperClientFixture.emptyDenylist(),
      helper: client)

    let events = await collect(executor, executing: plan)

    let report = try #require(finalReport(in: events))
    #expect(report.results[0].result == .completed(bytesReclaimed: 10))
    #expect(report.results[2].result == .completed(bytesReclaimed: 30))
    try expectPlainSentence(failureReason(report.results[1].result))
    try expectPlainSentence(failureReason(report.results[3].result))
  }

  // MARK: The same plan once approval lands

  @Test("approval granted between two runs turns the same plan from half done into fully done")
  func approvalGrantedTurnsTheSamePlanIntoAFullRun() async throws {
    let fileSystem = InMemoryFileSystem()
    await seedUserTargets(fileSystem)
    let service = FakeHelperService(status: .notRegistered)
    let transport = RecordingHelperTransport(succeedingWith: 100)
    let client = makeHelperClient(
      transport: transport, registration: makeRegistrationCoordinator(service: service))
    let denylist = try await HelperClientFixture.emptyDenylist()
    let (firstPlan, _) = mixedPlan()
    let firstEvents = await collect(
      makeExecutor(fileSystem: fileSystem, denylist: denylist, helper: client),
      executing: firstPlan)
    let firstReport = try #require(finalReport(in: firstEvents))
    try expectApprovalSentence(failureReason(firstReport.results[1].result))

    service.approveInSystemSettings()
    let secondFileSystem = InMemoryFileSystem()
    await seedUserTargets(secondFileSystem)
    let (secondPlan, _) = mixedPlan()
    let secondEvents = await collect(
      makeExecutor(fileSystem: secondFileSystem, denylist: denylist, helper: client),
      executing: secondPlan)

    let secondReport = try #require(finalReport(in: secondEvents))
    #expect(
      secondReport.results.map(\.result) == [
        .completed(bytesReclaimed: 10),
        .completed(bytesReclaimed: 100),
        .completed(bytesReclaimed: 30),
        .completed(bytesReclaimed: 100),
      ])
    #expect(service.registerCallCount == 1, "the second run does not ask again")
    #expect(transport.handshakeCount == 1)
  }

  @Test("with the helper enabled, the same mixed plan sends only the system domain half")
  func enabledHelperReceivesOnlyTheSystemDomainHalf() async throws {
    let fileSystem = InMemoryFileSystem()
    await seedUserTargets(fileSystem)
    let transport = RecordingHelperTransport(succeedingWith: 100)
    let client = makeHelperClient(
      transport: transport,
      registration: makeRegistrationCoordinator(
        service: FakeHelperService(status: .enabled, onRegister: .succeeds(leaving: .enabled))))
    let (plan, operations) = mixedPlan()
    let executor = makeExecutor(
      fileSystem: fileSystem, denylist: try await HelperClientFixture.emptyDenylist(),
      helper: client)

    _ = await collect(executor, executing: plan)

    #expect(
      try transport.sentOperationRequests().map(\.replyOperationID)
        == [operations[1].id, operations[3].id])
  }

  // MARK: The denylist is still the last word

  @Test("a denylisted system target is never transmitted, byte for byte")
  func denylistedTargetIsNeverTransmitted() async throws {
    let fileSystem = InMemoryFileSystem()
    let payload = Data(repeating: 0x24, count: 50)
    await fileSystem.seedFile(at: HelperClientFixture.systemDenylistedTarget, contents: payload)
    await fileSystem.seedFile(
      at: HelperClientFixture.systemTarget, contents: Data(repeating: 0x25, count: 100))
    let transport = RecordingHelperTransport(succeedingWith: 100)
    let client = makeHelperClient(
      transport: transport,
      registration: makeRegistrationCoordinator(
        service: FakeHelperService(status: .enabled, onRegister: .succeeds(leaving: .enabled))))
    let blocked = HelperClientFixture.trash(HelperClientFixture.systemDenylistedTarget)
    let allowed = HelperClientFixture.trash(HelperClientFixture.systemTarget)
    let plan = HelperClientFixture.plan([blocked, allowed], totalBytes: 150)
    let executor = makeExecutor(
      fileSystem: fileSystem, denylist: try await HelperClientFixture.signedDenylist(),
      helper: client)

    let events = await collect(executor, executing: plan)

    #expect(
      transport.transmitted(text: "/Library/Blocked") == false,
      "a blocked target must not cross the boundary at all, not even to be refused there")
    #expect(try transport.sentOperationRequests().map(\.replyOperationID) == [allowed.id])
    let report = try #require(finalReport(in: events))
    #expect(
      report.results.map(\.result) == [.skippedDenylisted, .completed(bytesReclaimed: 100)])
    #expect(await fileSystem.exists(HelperClientFixture.systemDenylistedTarget))
  }

  // MARK: A bad reply mid plan

  @Test("a malformed reply mid plan fails one operation and the rest of the plan still runs")
  func malformedReplyMidPlanFailsOneOperation() async throws {
    let fileSystem = InMemoryFileSystem()
    await seedUserTargets(fileSystem)
    let (plan, operations) = mixedPlan()
    let transport = RecordingHelperTransport(
      script: [
        .rawPayload(Data([0xFF, 0xFE])),
        .message(.success(correlationID: operations[3].id, bytesReclaimed: 0)),
      ])
    let client = makeHelperClient(
      transport: transport,
      registration: makeRegistrationCoordinator(
        service: FakeHelperService(status: .enabled, onRegister: .succeeds(leaving: .enabled))))
    let executor = makeExecutor(
      fileSystem: fileSystem, denylist: try await HelperClientFixture.emptyDenylist(),
      helper: client)

    let events = await collect(executor, executing: plan)

    let report = try #require(finalReport(in: events))
    #expect(report.results[0].result == .completed(bytesReclaimed: 10))
    try expectPlainSentence(failureReason(report.results[1].result))
    #expect(report.results[2].result == .completed(bytesReclaimed: 30))
    #expect(report.results[3].result == .completed(bytesReclaimed: 0))
    #expect(helperUnavailableReason(in: events) == nil, "one bad reply is not a broken run")
    #expect(transport.overranScript == false)
  }
}
