import Foundation
import GleamCore
import ProtectionModule
import Testing
import os

/// The SafetyNet screen: what is being held, and the two things a person can
/// do with it.
///
/// The asymmetry is the whole design. Restore is one click, because putting
/// something back is the promise. Purge takes a confirmation carrying the
/// exact count and the exact bytes, because it is the one irreversible thing
/// this app does to something it has already taken.
@MainActor
@Suite("SafetyNet surface")
struct SafetyNetModelTests {

  private func model(_ store: RecordingSafetyNetStore) -> SafetyNetModel {
    SafetyNetModel(store: store, now: { SafetyNetSurfaceFixture.instant })
  }

  @Test("what is held is listed newest first")
  func whatIsHeldIsListedNewestFirst() async throws {
    let store = RecordingSafetyNetStore(items: [
      SafetyNetSurfaceFixture.item(name: "older", storedAt: SafetyNetSurfaceFixture.instant),
      SafetyNetSurfaceFixture.item(
        name: "newer", storedAt: SafetyNetSurfaceFixture.instant.addingTimeInterval(60)),
    ])
    let model = model(store)

    await model.reload()

    #expect(model.items.map { $0.originPath.lastComponent } == ["newer", "older"])
  }

  @Test("a restore puts one back and it leaves the list")
  func aRestorePutsOneBack() async throws {
    let item = SafetyNetSurfaceFixture.item(name: "agent.plist")
    let store = RecordingSafetyNetStore(items: [item])
    let model = model(store)
    await model.reload()

    await model.restore(itemID: item.id)

    #expect(await store.restored == [item.id])
    #expect(model.items.isEmpty)
    #expect(model.notice == nil)
  }

  @Test("a restore that cannot happen says so and keeps the row")
  func aRestoreThatCannotHappenSaysSo() async throws {
    let item = SafetyNetSurfaceFixture.item(name: "agent.plist")
    let store = RecordingSafetyNetStore(
      items: [item], failingWith: SafetyNetError.originOccupied(item.originPath))
    let model = model(store)
    await model.reload()

    await model.restore(itemID: item.id)

    let notice = try #require(model.notice)
    #expect(notice.contains(item.originPath.value))
  }

  @Test("an uninstall goes back as one group")
  func anUninstallGoesBackAsOneGroup() async throws {
    let groupID = UUID()
    let store = RecordingSafetyNetStore(items: [
      SafetyNetSurfaceFixture.item(name: "App.app", groupID: groupID),
      SafetyNetSurfaceFixture.item(name: "prefs.plist", groupID: groupID),
    ])
    let model = model(store)
    await model.reload()

    await model.restoreGroup(groupID: groupID)

    #expect(await store.restoredGroups == [groupID])
  }

  // MARK: - Purging

  @Test("the scope a purge needs confirming is the recorded count and bytes")
  func theScopeIsTheRecordedCountAndBytes() async throws {
    let first = SafetyNetSurfaceFixture.item(name: "one", allocatedBytes: 1_000)
    let second = SafetyNetSurfaceFixture.item(name: "two", allocatedBytes: 2_500)
    let model = model(RecordingSafetyNetStore(items: [first, second]))
    await model.reload()

    let scope = try #require(model.purgeScope(itemIDs: [first.id, second.id]))

    #expect(scope.fileCount == 2)
    #expect(scope.byteTotal == 3_500)
  }

  @Test("a purge with no confirmation removes nothing")
  func aPurgeWithNoConfirmationRemovesNothing() async throws {
    let item = SafetyNetSurfaceFixture.item(name: "one")
    let store = RecordingSafetyNetStore(items: [item])
    let model = model(store)
    await model.reload()

    let purged = await model.purge(itemIDs: [item.id], confirmation: nil)

    #expect(!purged)
    #expect(await store.purged.isEmpty)
    #expect(model.items.count == 1)
  }

  @Test("a purge whose numbers do not match removes nothing and says so")
  func aPurgeWhoseNumbersDoNotMatchRemovesNothing() async throws {
    let item = SafetyNetSurfaceFixture.item(name: "one", allocatedBytes: 1_000)
    let store = RecordingSafetyNetStore(items: [item])
    let model = model(store)
    await model.reload()

    let purged = await model.purge(
      itemIDs: [item.id],
      confirmation: PermanentDeletionConfirmation(
        fileCount: 1, byteTotal: 999, confirmedAt: SafetyNetSurfaceFixture.instant))

    #expect(!purged)
    #expect(await store.purged.isEmpty)
    #expect(model.notice != nil)
  }

  @Test("a purge with the exact numbers removes it")
  func aPurgeWithTheExactNumbersRemovesIt() async throws {
    let item = SafetyNetSurfaceFixture.item(name: "one", allocatedBytes: 1_000)
    let store = RecordingSafetyNetStore(items: [item])
    let model = model(store)
    await model.reload()

    let purged = await model.purge(
      itemIDs: [item.id],
      confirmation: PermanentDeletionConfirmation(
        fileCount: 1, byteTotal: 1_000, confirmedAt: SafetyNetSurfaceFixture.instant))

    #expect(purged)
    #expect(await store.purged == [[item.id]])
    #expect(model.items.isEmpty)
  }

  @Test("what is past thirty days is offered as expired and purged by nobody")
  func whatIsPastThirtyDaysIsOfferedAsExpired() async throws {
    let item = SafetyNetSurfaceFixture.item(name: "old")
    let store = RecordingSafetyNetStore(items: [item], expired: [item])
    let model = model(store)

    let expired = await model.expiredItems()

    #expect(expired.map(\.id) == [item.id])
    #expect(await store.purged.isEmpty, "expiry marks eligibility and never removes anything")
  }
}

enum SafetyNetSurfaceFixture {
  static let instant = Date(timeIntervalSince1970: 1_726_000_000)

  static func item(
    name: String,
    groupID: UUID? = nil,
    allocatedBytes: UInt64 = 512,
    storedAt: Date = SafetyNetSurfaceFixture.instant
  ) -> SafetyNetItem {
    let identifier = UUID()
    return SafetyNetItem(
      id: identifier,
      originPath: AbsolutePath(normalising: "/Users/gleam/Library/LaunchAgents/\(name)"),
      storedPath: AbsolutePath(normalising: "/store/payloads/\(identifier.uuidString)"),
      source: .malwareQuarantine,
      groupID: groupID,
      metadata: FileMetadataSnapshot(
        posixPermissions: 0o644, extendedAttributes: [:], created: nil, modified: nil),
      allocatedBytes: allocatedBytes,
      storedAt: storedAt,
      expiresAt: storedAt.addingTimeInterval(SafetyNetItem.retentionInterval),
      isRestored: false)
  }
}

/// The store at the boundary the surface sees, recording what it was asked to
/// do so a test can tell a screen that acted from one that only said it did.
actor RecordingSafetyNetStore: SafetyNetStoring {
  private var held: [SafetyNetItem]
  private let expired: [SafetyNetItem]
  private let failure: (any Error)?
  private(set) var restored: [UUID] = []
  private(set) var restoredGroups: [UUID] = []
  private(set) var purged: [[UUID]] = []

  init(
    items: [SafetyNetItem], expired: [SafetyNetItem] = [], failingWith failure: (any Error)? = nil
  ) {
    self.held = items
    self.expired = expired
    self.failure = failure
  }

  func store(
    _ path: AbsolutePath,
    source: SafetyNetItem.Source,
    groupID: UUID?
  ) async throws -> SafetyNetItem {
    throw SafetyNetError.itemNotFound(UUID())
  }

  func items(includingRestored: Bool) async throws -> [SafetyNetItem] { held }

  func restore(itemID: UUID) async throws {
    if let failure { throw failure }
    restored.append(itemID)
    held.removeAll { $0.id == itemID }
  }

  func restoreGroup(groupID: UUID) async throws {
    if let failure { throw failure }
    restoredGroups.append(groupID)
    held.removeAll { $0.groupID == groupID }
  }

  func purge(itemIDs: [UUID], confirmation: PurgeConfirmation) async throws {
    if let failure { throw failure }
    purged.append(itemIDs)
    held.removeAll { itemIDs.contains($0.id) }
  }

  func purgeEligibleItems(asOf now: Date) async throws -> [SafetyNetItem] { expired }
}
