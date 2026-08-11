import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// C24: "User scope items change in process; system scope items route through
/// the helper (C30). The caller does not choose; the implementation routes by
/// scope." C31 adds the other half of least privilege: the helper refuses a
/// user domain target, because it never does work the user process could do
/// itself.
///
/// So the scope of the item decides, and nothing a caller says can move that
/// decision. A plan built ten minutes ago, or tampered with, can claim any
/// privilege it likes; the change still happens where the item lives, exactly
/// as path ownership overrides an operation's claimed privilege for the file
/// operations (C17). Both doubles here record what reached them, so each
/// direction is proved from the side that was used and the side that was not.
@Suite("Performance login items: user scope stays in, system scope goes out")
struct LaunchItemScopeRoutingTests {

  // MARK: The manager routes by scope

  @Test("a user scope change is made in this process and never reaches the privileged side")
  func aUserScopeChangeStaysInProcess() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.updaterAgent.identifier

    _ = try await world.manager.setEnabled(false, item: item)

    #expect(world.source.attempts == [.init(item: item, enabled: false)])
    #expect(
      world.privileged.sawNothing,
      "the helper runs as root and never does work this process could do itself")
    #expect(world.source.isEnabled(item) == false)
  }

  @Test("a system scope change goes to the privileged side and is never attempted in this process")
  func aSystemScopeChangeGoesOut() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.backupDaemon.identifier

    _ = try await world.manager.setEnabled(false, item: item)

    #expect(world.privileged.handovers == [.init(item: item, enabled: false)])
    #expect(
      world.source.sawNoAttempt,
      "this process cannot change a system registration, so it must not try")
    #expect(world.source.isEnabled(item) == false)
  }

  @Test("routing follows the scope for every item on the machine, in both directions")
  func routingFollowsTheScopeForEveryItem() async throws {
    let world = LaunchItemWorld()

    for item in LaunchItemFixture.inventory {
      _ = try await world.manager.setEnabled(false, item: item.identifier)
    }

    let userItems = LaunchItemFixture.inventory.filter { $0.scope == .user }.map(\.identifier)
    let systemItems = LaunchItemFixture.inventory.filter { $0.scope == .system }.map(\.identifier)
    #expect(world.source.attempts.map(\.item) == userItems)
    #expect(world.privileged.handovers.map(\.item) == systemItems)
  }

  @Test("with no privileged side available a system scope change fails and changes nothing")
  func aSystemScopeChangeWithNoPrivilegedSideFails() async throws {
    let source = FakeLaunchItemSource()
    let file = LaunchItemChangeFile()
    let manager = makeLaunchItemManager(
      source: source, privileged: nil, store: FakeLaunchItemChangeStore(file: file))
    let item = LaunchItemFixture.backupDaemon.identifier

    let thrown = await #expect(throws: LaunchItemError.self) {
      _ = try await manager.setEnabled(false, item: item)
    }

    guard case .changeFailed(let reason) = try #require(thrown) else {
      Issue.record("expected changeFailed, got \(String(describing: thrown))")
      return
    }
    expectPlainSentence(reason)
    #expect(source.sawNoAttempt, "a system item is never changed in process as a fallback")
    #expect(source.isEnabled(item) == true)
    #expect(try await persistedChanges(in: file).isEmpty)
  }

  @Test("the privileged side failing to resolve the item is reported as the item being gone")
  func anUnresolvableItemOnThePrivilegedSideReadsAsItemNotFound() async throws {
    let item = LaunchItemFixture.backupDaemon.identifier
    let world = LaunchItemWorld(privilegedFailures: [item: .itemUnresolvable])

    await #expect(throws: LaunchItemError.itemNotFound(item: item)) {
      _ = try await world.manager.setEnabled(false, item: item)
    }

    #expect(
      world.privileged.handovers.map(\.item) == [item],
      "C31 refuses malformedRequest and C24 maps it, so the request was made and then refused")
    #expect(try await world.store.recordedChanges().isEmpty)
    #expect(world.source.isEnabled(item) == true)
  }

  @Test("the privileged side refusing for another reason is a plain sentence, not a lost item")
  func aPrivilegedRefusalReadsAsAFailure() async throws {
    let item = LaunchItemFixture.backupDaemon.identifier
    let world = LaunchItemWorld(
      privilegedFailures: [item: .refused(reason: "The item is protected.")])

    let thrown = await #expect(throws: LaunchItemError.self) {
      _ = try await world.manager.setEnabled(false, item: item)
    }

    guard case .changeFailed(let reason) = try #require(thrown) else {
      Issue.record("expected changeFailed, got \(String(describing: thrown))")
      return
    }
    expectPlainSentence(reason)
    #expect(world.source.isEnabled(item) == true)
  }

  // MARK: The plan says which privilege it expects

  @Test("a user scope item is planned at user privilege and a system scope item at root")
  func planPrivilegeFollowsTheScope() async throws {
    let world = LaunchItemWorld()

    let (plan, _) = try await planLoginItems(
      [LaunchItemFixture.updaterAgent.identifier, LaunchItemFixture.backupDaemon.identifier],
      inventory: world.inventoryOnly)

    #expect(plan.operations.map(\.privilege) == [.user, .root])
  }

  // MARK: The operation's claimed privilege routes nothing

  @Test("a user scope item never reaches the helper, even when the operation claims root")
  func aUserScopeItemNeverReachesTheHelperAtRoot() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.updaterAgent.identifier
    let plan = makeLaunchItemPlan([makeLaunchItemOperation(item: item, privilege: .root)])
    let helper = FakeHelper()
    let executor = makeLaunchItemExecutor(
      manager: world.manager, helper: helper, denylist: try await performanceDenylist())

    let events = await executorCollect(executor, executing: plan)

    #expect(
      world.privileged.sawNothing,
      "the item lives in this user's own domain, so the change stays here")
    #expect(helper.sawNothing)
    #expect(world.source.attempts == [.init(item: item, enabled: false)])
    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.result) == [.completed(bytesReclaimed: 0)])
  }

  @Test("a system scope item still routes out, even when the operation claims user privilege")
  func aSystemScopeItemStillRoutesOutAtUserPrivilege() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.backupDaemon.identifier
    let plan = makeLaunchItemPlan([makeLaunchItemOperation(item: item, privilege: .user)])
    let executor = makeLaunchItemExecutor(
      manager: world.manager, helper: FakeHelper(), denylist: try await performanceDenylist())

    _ = await executorCollect(executor, executing: plan)

    #expect(world.privileged.handovers == [.init(item: item, enabled: false)])
    #expect(world.source.sawNoAttempt)
  }

  @Test("no login item change is handed to the maintenance helper")
  func loginItemChangesNeverGoThroughTheMaintenanceHelper() async throws {
    let world = LaunchItemWorld()
    let plan = makeLaunchItemPlan([
      makeLaunchItemOperation(
        item: LaunchItemFixture.updaterAgent.identifier,
        privilege: .user,
        id: PerformanceFixture.uuid(0xB2)),
      makeLaunchItemOperation(
        item: LaunchItemFixture.backupDaemon.identifier,
        privilege: .root,
        id: PerformanceFixture.uuid(0xB3)),
    ])
    let helper = FakeHelper()
    let executor = makeLaunchItemExecutor(
      manager: world.manager, helper: helper, denylist: try await performanceDenylist())

    _ = await executorCollect(executor, executing: plan)

    #expect(
      helper.sawNothing,
      "the change is the launch item manager's to route; it knows the scope and the helper does not"
    )
    #expect(world.privileged.handovers.count == 1)
  }

  // MARK: What the run reports

  @Test("a disable that succeeded reports completed and reclaims nothing")
  func aSuccessfulDisableReclaimsNothing() async throws {
    let world = LaunchItemWorld()
    let (plan, _) = try await planLoginItems(
      [LaunchItemFixture.updaterAgent.identifier], inventory: world.inventoryOnly)
    let executor = makeLaunchItemExecutor(
      manager: world.manager, denylist: try await performanceDenylist())

    let events = await executorCollect(executor, executing: plan)

    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.map(\.result) == [.completed(bytesReclaimed: 0)])
    #expect(report.bytesReclaimed == 0)
  }

  @Test("an item that has gone costs that operation and not the run")
  func aMissingItemCostsOneOperation() async throws {
    let world = LaunchItemWorld()
    let plan = makeLaunchItemPlan([
      makeLaunchItemOperation(
        item: LaunchItemFixture.updaterAgent.identifier,
        privilege: .user,
        id: PerformanceFixture.uuid(0xB4)),
      makeLaunchItemOperation(
        item: LaunchItemFixture.ghostUserItem,
        privilege: .user,
        id: PerformanceFixture.uuid(0xB5)),
      makeLaunchItemOperation(
        item: LaunchItemFixture.notesHelper.identifier,
        privilege: .user,
        id: PerformanceFixture.uuid(0xB6)),
    ])
    let executor = makeLaunchItemExecutor(
      manager: world.manager, denylist: try await performanceDenylist())

    let events = await executorCollect(executor, executing: plan)

    let report = try #require(executorFinalReport(in: events))
    #expect(report.results.count == 3)
    #expect(report.results[0].result == .completed(bytesReclaimed: 0))
    guard case .failed(let reason) = report.results[1].result else {
      Issue.record("expected the missing item to fail, got \(report.results[1].result)")
      return
    }
    expectPlainSentence(reason)
    #expect(report.results[2].result == .completed(bytesReclaimed: 0))
    #expect(executorRefusal(in: events) == nil, "one item being gone is not the run failing")
    #expect(world.source.isEnabled(LaunchItemFixture.notesHelper.identifier) == false)
  }

  @Test("a login item plan runs with no maintenance helper wired, because it never needs one")
  func aLoginItemPlanNeedsNoMaintenanceHelper() async throws {
    let world = LaunchItemWorld()
    let (plan, _) = try await planLoginItems(
      [LaunchItemFixture.updaterAgent.identifier, LaunchItemFixture.backupDaemon.identifier],
      inventory: world.inventoryOnly)
    let executor = makeLaunchItemExecutor(
      manager: world.manager, helper: nil, denylist: try await performanceDenylist())

    let events = await executorCollect(executor, executing: plan)

    #expect(
      executorRefusal(in: events) == nil,
      "the privileged side a login item change needs is the manager's, not the executor's helper")
    let report = try #require(executorFinalReport(in: events))
    let completed = OperationResult.completed(bytesReclaimed: 0)
    #expect(report.results.map(\.result) == [completed, completed])
    // The two the plan named are off, and nothing else moved. Asserting that
    // every item ended disabled would demand disabling registrations the plan
    // never named, which is what this slice exists to prevent.
    #expect(world.source.isEnabled(LaunchItemFixture.updaterAgent.identifier) == false)
    #expect(world.source.isEnabled(LaunchItemFixture.backupDaemon.identifier) == false)
    let named: Set<LaunchItemID> = [
      LaunchItemFixture.updaterAgent.identifier,
      LaunchItemFixture.backupDaemon.identifier,
    ]
    let untouched = world.source.currentItems.filter { !named.contains($0.identifier) }
    #expect(untouched.contains { $0.isEnabled }, "the fixture must hold items the plan left alone")
    #expect(
      untouched.allSatisfy { item in
        item.isEnabled
          == LaunchItemFixture.inventory.first { $0.identifier == item.identifier }?.isEnabled
      },
      "an item the plan never named keeps exactly the state it started in")
  }

  @Test("a change made through a plan is recorded exactly as one made directly")
  func aPlannedChangeIsRecordedToo() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.updaterAgent.identifier
    let (plan, _) = try await planLoginItems([item], inventory: world.inventoryOnly)
    let executor = makeLaunchItemExecutor(
      manager: world.manager, denylist: try await performanceDenylist())

    _ = await executorCollect(executor, executing: plan)

    #expect(
      try await persistedChanges(in: world.file).map(\.previousEnabled) == [true],
      "one click re enables what a review disabled, so a planned change is recorded like any other")
  }
}
