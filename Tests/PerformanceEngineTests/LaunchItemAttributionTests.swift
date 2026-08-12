import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// Every privileged launch item change says who asked for it, and the two
/// kinds stay apart: a plan operation is reconciled against its plan, and a
/// switch somebody flipped is reconciled against itself.
///
/// The half these cover is the one C30 version one could not carry: the
/// attribution crossing the privileged boundary. What crosses is asserted at
/// the boundary itself rather than at the manager, because the manager
/// honouring it and the wire dropping it is exactly the gap this closes.
@Suite("Launch item change attribution")
struct LaunchItemAttributionTests {

  @Test("a planned change carries the plan and the operation the executor is running")
  func aPlannedChangeCarriesThePlanAndTheOperation() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.backupDaemon.identifier
    let plan = makeLaunchItemPlan([makeLaunchItemOperation(item: item, privilege: .root)])
    let executor = makeLaunchItemExecutor(
      manager: world.manager, denylist: try await performanceDenylist())

    _ = await executorCollect(executor, executing: plan)

    let operation = try #require(plan.operations.first)
    let handover = try #require(world.privileged.handovers.first)
    #expect(handover.attribution == .operation(planID: plan.id, operationID: operation.id))
  }

  @Test("a change made in the interface carries an identifier that names nothing else")
  func aDirectChangeCarriesAnIdentifierThatNamesNothingElse() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.backupDaemon.identifier
    let plan = makeLaunchItemPlan([
      makeLaunchItemOperation(item: LaunchItemFixture.updaterAgent.identifier, privilege: .user)
    ])
    let executor = makeLaunchItemExecutor(
      manager: world.manager, denylist: try await performanceDenylist())
    let events = await executorCollect(executor, executing: plan)
    let report = try #require(executorFinalReport(in: events))

    _ = try await world.manager.setEnabled(false, item: item)

    let handover = try #require(world.privileged.handovers.last)
    let changeID = handover.attribution.correlationID
    #expect(handover.attribution == .directChange(changeID: changeID))
    #expect(handover.attribution.planID == nil)
    #expect(plan.id != changeID)
    #expect(!plan.operations.contains { $0.id == changeID || $0.findingID == changeID })
    #expect(!report.results.contains { $0.operationID == changeID })
  }

  @Test("two changes made by hand are two identifiers, so neither stands for the other")
  func twoDirectChangesAreTwoIdentifiers() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.backupDaemon.identifier

    _ = try await world.manager.setEnabled(false, item: item)
    _ = try await world.manager.setEnabled(true, item: item)

    let identifiers = world.privileged.handovers.map(\.attribution.correlationID)
    #expect(identifiers.count == 2)
    #expect(Set(identifiers).count == 2)
  }

  @Test("the attribution the manager was given is the one that crosses, unaltered")
  func theAttributionTheManagerWasGivenIsTheOneThatCrosses() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.backupDaemon.identifier
    let attribution = ChangeAttribution.operation(
      planID: PerformanceFixture.uuid(0xC1), operationID: PerformanceFixture.uuid(0xC2))

    _ = try await world.manager.setEnabled(false, item: item, attribution: attribution)

    #expect(world.privileged.handovers.map(\.attribution) == [attribution])
  }

  @Test("a user scope change reaches the privileged side not at all, attributed or otherwise")
  func aUserScopeChangeReachesThePrivilegedSideNotAtAll() async throws {
    let world = LaunchItemWorld()

    _ = try await world.manager.setEnabled(
      false, item: LaunchItemFixture.updaterAgent.identifier)

    #expect(world.privileged.sawNothing)
  }
}
