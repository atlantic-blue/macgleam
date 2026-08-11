import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// C24: "`setEnabled` disables or enables, never deletes, and returns a
/// `LaunchItemChange` recording the prior state. The app persists these
/// records so re enabling is one click and survives relaunch." GRAPH.md's open
/// question 5 settles where that record lives: the app persists it.
///
/// The promise a person is given is that turning something off is safe because
/// turning it back on is one click, days later, after a restart. That promise
/// is worth nothing if the prior state lived in memory, and it is actively
/// wrong if re enabling means "on" rather than "whatever it was": an item that
/// was already off before MacGleam touched it must come back off. Every test
/// here drives persistence through a store that encodes its records, so a
/// record held in memory fails rather than passes.
@Suite("Performance login items: the recorded prior state")
struct LaunchItemChangeRoundTripTests {

  // MARK: Recording

  @Test("disabling an item returns the state it was in before")
  func disablingReturnsThePriorState() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.updaterAgent

    let change = try await world.manager.setEnabled(false, item: item.identifier)

    #expect(
      change
        == LaunchItemChange(
          item: item.identifier,
          previousEnabled: true,
          newEnabled: false,
          changedAt: LaunchItemFixture.userChangeInstant))
  }

  @Test("the record is persisted, not held in memory")
  func theRecordIsPersisted() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.updaterAgent

    let change = try await world.manager.setEnabled(false, item: item.identifier)

    #expect(
      try await persistedChanges(in: world.file) == [change],
      "the record has to survive the process, so it goes through the store, not a property")
  }

  @Test("records accumulate in the order they were made")
  func recordsAccumulateInOrder() async throws {
    let world = LaunchItemWorld()
    let first = LaunchItemFixture.updaterAgent.identifier
    let second = LaunchItemFixture.notesHelper.identifier

    _ = try await world.manager.setEnabled(false, item: first)
    _ = try await world.manager.setEnabled(false, item: second)

    let records = try await world.store.recordedChanges()
    #expect(records.map(\.item) == [first, second])
    #expect(records.allSatisfy { $0.previousEnabled == true && $0.newEnabled == false })
  }

  @Test("a change that could not be made records nothing")
  func aFailedChangeRecordsNothing() async throws {
    let world = LaunchItemWorld()

    _ = try? await world.manager.setEnabled(false, item: LaunchItemFixture.ghostUserItem)

    #expect(try await persistedChanges(in: world.file).isEmpty)
  }

  @Test("a change made on the privileged side is recorded exactly as that side reported it")
  func aPrivilegedChangeIsRecordedAsReported() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.backupDaemon

    let change = try await world.manager.setEnabled(false, item: item.identifier)

    #expect(change.changedAt == LaunchItemFixture.privilegedChangeInstant)
    #expect(change.previousEnabled == true)
    #expect(try await persistedChanges(in: world.file) == [change])
  }

  // MARK: Reading the prior state back

  @Test("an item MacGleam has never changed has no recorded prior state")
  func anUntouchedItemHasNoPriorState() async throws {
    let world = LaunchItemWorld()

    _ = try await world.manager.setEnabled(false, item: LaunchItemFixture.updaterAgent.identifier)

    let records = try await world.store.recordedChanges()
    #expect(
      LaunchItemChange.stateBeforeFirstChange(
        of: LaunchItemFixture.notesHelper.identifier, in: records) == nil,
      "nothing to restore reads as nothing, never as enabled")
  }

  @Test("the state before the first change survives every later change")
  func thePriorStateSurvivesLaterChanges() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.updaterAgent.identifier

    _ = try await world.manager.setEnabled(false, item: item)
    _ = try await world.manager.setEnabled(true, item: item)
    _ = try await world.manager.setEnabled(false, item: item)

    let records = try await world.store.recordedChanges()
    #expect(
      LaunchItemChange.stateBeforeFirstChange(of: item, in: records) == true,
      "the state to restore is the one MacGleam found, not the one it left behind")
  }

  @Test("the prior state of an item that was already off reads as off")
  func thePriorStateOfADormantItemReadsAsOff() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.dormantAgent.identifier

    let change = try await world.manager.setEnabled(false, item: item)

    #expect(change.previousEnabled == false)
    let records = try await world.store.recordedChanges()
    #expect(LaunchItemChange.stateBeforeFirstChange(of: item, in: records) == false)
  }

  // MARK: The round trip, across a relaunch

  @Test("a second launch of the app re enables a user scope item to exactly its prior state")
  func aRelaunchRestoresAUserScopeItem() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.updaterAgent.identifier
    _ = try await world.manager.setEnabled(false, item: item)
    #expect(world.source.isEnabled(item) == false)

    let next = world.relaunched()
    let prior = try #require(
      LaunchItemChange.stateBeforeFirstChange(
        of: item, in: try await next.store.recordedChanges()),
      "the record survives the process it was written in")
    let restored = try await next.manager.setEnabled(prior, item: item)

    #expect(restored.newEnabled == true)
    #expect(restored.changedAt == LaunchItemFixture.relaunchInstant)
    #expect(world.source.isEnabled(item) == true)
  }

  @Test("a second launch of the app re enables a system scope item to exactly its prior state")
  func aRelaunchRestoresASystemScopeItem() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.backupDaemon.identifier
    _ = try await world.manager.setEnabled(false, item: item)

    let next = world.relaunched()
    let prior = try #require(
      LaunchItemChange.stateBeforeFirstChange(
        of: item, in: try await next.store.recordedChanges()))
    _ = try await next.manager.setEnabled(prior, item: item)

    #expect(world.source.isEnabled(item) == true)
    #expect(
      world.privileged.handovers.map(\.enabled) == [false, true],
      "restoring a system item goes back out the same way it went out")
  }

  @Test("an item that was already off comes back off, not on")
  func anItemThatWasAlreadyOffComesBackOff() async throws {
    let world = LaunchItemWorld()
    let item = LaunchItemFixture.dormantAgent.identifier
    _ = try await world.manager.setEnabled(false, item: item)

    let next = world.relaunched()
    let prior = try #require(
      LaunchItemChange.stateBeforeFirstChange(
        of: item, in: try await next.store.recordedChanges()))
    _ = try await next.manager.setEnabled(prior, item: item)

    #expect(prior == false)
    #expect(
      world.source.isEnabled(item) == false,
      "one click restores what was there; it does not start something the person had turned off")
  }

  @Test("disabling every login item and restoring after a relaunch returns the machine exactly")
  func theWholeMachineRoundTrips() async throws {
    let world = LaunchItemWorld()
    let before = world.source.currentItems
    for item in before {
      _ = try await world.manager.setEnabled(false, item: item.identifier)
    }
    #expect(world.source.currentItems.allSatisfy { $0.isEnabled == false })

    let next = world.relaunched()
    let records = try await next.store.recordedChanges()
    for item in before {
      let prior = try #require(
        LaunchItemChange.stateBeforeFirstChange(of: item.identifier, in: records))
      _ = try await next.manager.setEnabled(prior, item: item.identifier)
    }

    #expect(
      world.source.currentItems == before,
      "every item is back where it was, in both scopes, including the one that was already off")
    #expect(try await next.manager.list() == before)
  }
}
