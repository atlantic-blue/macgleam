import Foundation
import GleamCore
import ProtectionEngine
import Testing

/// The quarantine flow end to end: a detection found, contained, listed, put
/// back, and only then and only with a matching confirmation, gone.
///
/// Every other suite here proves one component. This one drives the real
/// engine into the real plan executor into the real SafetyNet store over one
/// file system, because the promise a person is being sold is the whole chain
/// and not any link of it: nothing is deleted, what is taken can be run
/// nowhere, and it comes back exactly as it left.
@Suite("Quarantine flow")
struct QuarantineFlowTests {

  private static let storeDirectory = ProtectionFixture.path(
    "\(ProtectionFixture.home)/Library/Application Support/MacGleam/SafetyNet")
  private static let quarantineInstant = Date(timeIntervalSince1970: 1_726_000_000)

  private struct World {
    let fileSystem: InMemoryFileSystem
    let store: SafetyNetStore
    let executor: PlanExecutor
    let catalog: RuleCatalog
  }

  private func world() async throws -> World {
    let fileSystem = await makeProtectionDisk()
    await fileSystem.seedDirectory(at: Self.storeDirectory)
    let catalog = try makeSignedProtectionCatalog()
    let store = SafetyNetStore(
      directory: Self.storeDirectory,
      fileSystem: fileSystem,
      denylist: catalog.denylist,
      ownership: ProtectionOwnershipPolicy(),
      environment: OwnershipEnvironment(
        currentUserHome: ProtectionFixture.path(ProtectionFixture.home), currentUserID: 501),
      now: { Self.quarantineInstant })
    let executor = PlanExecutor(
      fileSystem: fileSystem,
      denylist: catalog.denylist,
      ownershipPolicy: ProtectionOwnershipPolicy(),
      environment: OwnershipEnvironment(
        currentUserHome: ProtectionFixture.path(ProtectionFixture.home), currentUserID: 501),
      safetyNet: store,
      now: { Self.quarantineInstant },
      isCancelled: { false })
    return World(fileSystem: fileSystem, store: store, executor: executor, catalog: catalog)
  }

  /// One detection this process can move on its own: the adware launch agent
  /// in the fixture home. The privileged path has its own suite; what this
  /// proves is the flow, which is the same on both sides of that boundary.
  private func adwareFinding(in outcome: ProtectionScanOutcome) throws -> Finding {
    try #require(
      outcome.findings.first {
        $0.category == .adwareLaunchItem
          && $0.paths.contains(ProtectionFixture.path(ProtectionFixture.adwareAgent))
      })
  }

  private func run(_ world: World, _ plan: OperationPlan) async -> ExecutionReport? {
    var report: ExecutionReport?
    for await event in world.executor.execute(plan) {
      if case .planCompleted(let completed) = event { report = completed }
    }
    return report
  }

  // MARK: - Found and contained

  @Test("a detection ends up in the SafetyNet, listed, and gone from where it was")
  func aDetectionEndsUpInTheSafetyNet() async throws {
    let world = try await world()
    let outcome = try await runProtectionScan(
      engine: ProtectionEngine(), over: world.fileSystem, rules: world.catalog)
    let plan = try ProtectionEngine().plan(
      selection: [try adwareFinding(in: outcome)],
      context: makeProtectionPlanContext(rules: world.catalog))

    let report = try #require(await run(world, plan))

    #expect(report.results.allSatisfy { $0.result.isCompleted })
    let held = try await world.store.items(includingRestored: false)
    #expect(held.map(\.originPath) == [ProtectionFixture.path(ProtectionFixture.adwareAgent)])
    #expect(await !world.fileSystem.exists(ProtectionFixture.path(ProtectionFixture.adwareAgent)))
    #expect(await world.fileSystem.exists(try #require(held.first).storedPath))
  }

  @Test("what is held cannot be run from where it is held")
  func whatIsHeldCannotBeRun() async throws {
    let world = try await world()
    let outcome = try await runProtectionScan(
      engine: ProtectionEngine(), over: world.fileSystem, rules: world.catalog)
    let plan = try ProtectionEngine().plan(
      selection: [try adwareFinding(in: outcome)],
      context: makeProtectionPlanContext(rules: world.catalog))
    _ = await run(world, plan)

    let item = try #require(try await world.store.items(includingRestored: false).first)
    let mode = try await world.fileSystem.posixPermissions(at: item.storedPath)

    #expect(
      mode & 0o111 == 0,
      "containment is the execute bits being gone, not the file being somewhere else")
  }

  @Test("nothing is deleted anywhere along the way")
  func nothingIsDeletedAlongTheWay() async throws {
    let world = try await world()
    let outcome = try await runProtectionScan(
      engine: ProtectionEngine(), over: world.fileSystem, rules: world.catalog)
    let detections = outcome.findings.filter {
      QuarantineFixture.isDetection($0.category)
    }
    let plan = try ProtectionEngine().plan(
      selection: detections, context: makeProtectionPlanContext(rules: world.catalog))

    #expect(!plan.operations.isEmpty)
    #expect(
      plan.operations.allSatisfy {
        if case .quarantine = $0.kind { return true }
        return false
      })

    _ = await run(world, plan)

    // This world has no privileged half, so the system domain detections
    // refuse rather than move. That is the case worth asserting: every path
    // is either held by the store or exactly where it was, and none of them
    // is gone. A run that half worked must never be a run that deleted.
    let held = Set(try await world.store.items(includingRestored: true).map(\.originPath))
    for path in Set(detections.flatMap(\.paths)) {
      let stillThere = await world.fileSystem.exists(path)
      #expect(
        held.contains(path) != stillThere,
        "\(path.value) is either in the SafetyNet or where it was, and never neither")
    }
    #expect(!held.isEmpty, "a run that stored nothing proves nothing about what it stored")
  }

  // MARK: - Put back

  @Test("one restore puts it back exactly where it was, attribute for attribute")
  func oneRestorePutsItBackExactly() async throws {
    let world = try await world()
    let origin = ProtectionFixture.path(ProtectionFixture.adwareAgent)
    let before = try await world.fileSystem.posixPermissions(at: origin)
    let contents = try await world.fileSystem.readData(at: origin, maxBytes: .max)
    let outcome = try await runProtectionScan(
      engine: ProtectionEngine(), over: world.fileSystem, rules: world.catalog)
    let plan = try ProtectionEngine().plan(
      selection: [try adwareFinding(in: outcome)],
      context: makeProtectionPlanContext(rules: world.catalog))
    _ = await run(world, plan)
    let item = try #require(try await world.store.items(includingRestored: false).first)

    try await world.store.restore(itemID: item.id)

    #expect(await world.fileSystem.exists(origin))
    #expect(try await world.fileSystem.posixPermissions(at: origin) == before)
    #expect(try await world.fileSystem.readData(at: origin, maxBytes: .max) == contents)
    #expect(try await world.store.items(includingRestored: false).isEmpty)
  }

  @Test("a restored item is not offered again, and cannot be restored twice")
  func aRestoredItemIsNotOfferedAgain() async throws {
    let world = try await world()
    let outcome = try await runProtectionScan(
      engine: ProtectionEngine(), over: world.fileSystem, rules: world.catalog)
    let plan = try ProtectionEngine().plan(
      selection: [try adwareFinding(in: outcome)],
      context: makeProtectionPlanContext(rules: world.catalog))
    _ = await run(world, plan)
    let item = try #require(try await world.store.items(includingRestored: false).first)
    try await world.store.restore(itemID: item.id)

    await #expect(throws: SafetyNetError.alreadyRestored(item.id)) {
      try await world.store.restore(itemID: item.id)
    }
  }

  @Test("an item stays restorable for thirty days and becomes purgeable after them")
  func anItemStaysRestorableForThirtyDays() async throws {
    let world = try await world()
    let outcome = try await runProtectionScan(
      engine: ProtectionEngine(), over: world.fileSystem, rules: world.catalog)
    let plan = try ProtectionEngine().plan(
      selection: [try adwareFinding(in: outcome)],
      context: makeProtectionPlanContext(rules: world.catalog))
    _ = await run(world, plan)

    let dayTwentyNine = Self.quarantineInstant.addingTimeInterval(29 * 24 * 60 * 60)
    let dayThirtyOne = Self.quarantineInstant.addingTimeInterval(31 * 24 * 60 * 60)

    #expect(try await world.store.purgeEligibleItems(asOf: dayTwentyNine).isEmpty)
    #expect(try await world.store.purgeEligibleItems(asOf: dayThirtyOne).count == 1)
  }

  // MARK: - Gone, and only deliberately

  @Test("a purge without a matching confirmation removes nothing")
  func aPurgeWithoutAMatchingConfirmationRemovesNothing() async throws {
    let world = try await world()
    let outcome = try await runProtectionScan(
      engine: ProtectionEngine(), over: world.fileSystem, rules: world.catalog)
    let plan = try ProtectionEngine().plan(
      selection: [try adwareFinding(in: outcome)],
      context: makeProtectionPlanContext(rules: world.catalog))
    _ = await run(world, plan)
    let item = try #require(try await world.store.items(includingRestored: false).first)

    await #expect(throws: SafetyNetError.confirmationMismatch) {
      try await world.store.purge(
        itemIDs: [item.id],
        confirmation: PurgeConfirmation(
          itemCount: 1, byteTotal: item.allocatedBytes + 1, confirmedAt: Self.quarantineInstant))
    }
    #expect(try await world.store.items(includingRestored: false).count == 1)
    #expect(await world.fileSystem.exists(item.storedPath))
  }

  @Test("a purge with the exact counts removes it, and only then")
  func aPurgeWithTheExactCountsRemovesIt() async throws {
    let world = try await world()
    let outcome = try await runProtectionScan(
      engine: ProtectionEngine(), over: world.fileSystem, rules: world.catalog)
    let plan = try ProtectionEngine().plan(
      selection: [try adwareFinding(in: outcome)],
      context: makeProtectionPlanContext(rules: world.catalog))
    _ = await run(world, plan)
    let item = try #require(try await world.store.items(includingRestored: false).first)

    try await world.store.purge(
      itemIDs: [item.id],
      confirmation: PurgeConfirmation(
        itemCount: 1, byteTotal: item.allocatedBytes, confirmedAt: Self.quarantineInstant))

    #expect(try await world.store.items(includingRestored: true).isEmpty)
    #expect(await !world.fileSystem.exists(item.storedPath))
  }

  @Test("a denylisted detection is skipped rather than quarantined, and the run carries on")
  func aDenylistedDetectionIsSkipped() async throws {
    let world = try await world()
    let denylisted = Finding(
      id: UUID(),
      sessionID: ProtectionFixture.sessionID,
      category: .adwareLaunchItem,
      entries: [
        PathEntry(
          path: ProtectionFixture.path(ProtectionFixture.denylistedAdware), allocatedBytes: 512)
      ],
      risk: .dangerous,
      explanation: "A fixture row.",
      isPreselected: true)
    let outcome = try await runProtectionScan(
      engine: ProtectionEngine(), over: world.fileSystem, rules: world.catalog)

    let plan = try ProtectionEngine().plan(
      selection: [denylisted, try adwareFinding(in: outcome)],
      context: makeProtectionPlanContext(rules: world.catalog))
    let report = try #require(await run(world, plan))

    #expect(
      await world.fileSystem.exists(ProtectionFixture.path(ProtectionFixture.denylistedAdware)),
      "the denylist wins wherever it and a detection disagree")
    #expect(report.results.contains { $0.result.isCompleted })
  }
}

enum QuarantineFixture {
  static func isDetection(_ category: FindingCategory) -> Bool {
    switch category {
    case .malware, .adwareLaunchItem, .suspiciousBrowserExtension, .unwantedAppPath:
      return true
    default:
      return false
    }
  }
}

extension OperationResult {
  var isCompleted: Bool {
    if case .completed = self { return true }
    return false
  }
}
