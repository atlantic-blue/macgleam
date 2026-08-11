import Foundation
import GleamCore
import Testing

/// C18, restoring a single item. The whole promise of the store is that what
/// it took can come back exactly as it was, so fidelity is asserted attribute
/// by attribute. A file that merely exists again at the origin path is a
/// copy, not a restore.
@Suite("SafetyNet store: restoring")
struct SafetyNetStoreRestoreTests {

  private static let origin = Fixture.path("/Users/julian/Downloads/agent")

  /// Seeds the fixture, stores it, and hands back what the file looked like
  /// before, which is what restore has to reproduce.
  private func storedAgent(
    seed: UInt8,
    in fileSystem: InMemoryFileSystem,
    store: SafetyNetStore
  ) async throws -> (before: SafetyNetPathState, item: SafetyNetItem) {
    let before = try await safetyNetSeedFile(
      in: fileSystem, at: Self.origin, seed: seed, isExecutable: true)
    let item = try await store.store(Self.origin, source: .malwareQuarantine, groupID: nil)
    return (before, item)
  }

  @Test("puts the payload back at its origin path")
  func restoreReinstatesTheOriginPath() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 30, in: fileSystem, store: store)

    try await store.restore(itemID: stored.item.id)

    #expect(await fileSystem.exists(Self.origin))
  }

  @Test("restores the contents byte for byte")
  func restoreReinstatesContents() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 31, in: fileSystem, store: store)

    try await store.restore(itemID: stored.item.id)

    let after = try await safetyNetState(of: Self.origin, in: fileSystem)
    #expect(after.contents == stored.before.contents)
  }

  @Test("restores the permission mode exactly, execute bits included")
  func restoreReinstatesPermissionMode() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 32, in: fileSystem, store: store)

    try await store.restore(itemID: stored.item.id)

    let after = try await safetyNetState(of: Self.origin, in: fileSystem)
    #expect(after.posixPermissions == stored.before.posixPermissions)
    #expect(after.posixPermissions & 0o111 != 0)
  }

  @Test("restores every extended attribute exactly")
  func restoreReinstatesExtendedAttributes() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 33, in: fileSystem, store: store)

    try await store.restore(itemID: stored.item.id)

    let after = try await safetyNetState(of: Self.origin, in: fileSystem)
    #expect(after.extendedAttributes == stored.before.extendedAttributes)
  }

  @Test("restores the creation and modification dates exactly")
  func restoreReinstatesDates() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 34, in: fileSystem, store: store)

    try await store.restore(itemID: stored.item.id)

    let after = try await safetyNetState(of: Self.origin, in: fileSystem)
    #expect(after.created == stored.before.created)
    #expect(after.modified == stored.before.modified)
  }

  @Test("restores every attribute at once, so nothing is lost in combination")
  func restoreIsFaithfulAcrossEveryAttribute() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 35, in: fileSystem, store: store)

    try await store.restore(itemID: stored.item.id)

    let after = try await safetyNetState(of: Self.origin, in: fileSystem)
    expectSameFile(after, stored.before)
  }

  @Test("takes the payload out of the store directory")
  func restoreRemovesTheStoredPayload() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 36, in: fileSystem, store: store)

    try await store.restore(itemID: stored.item.id)

    #expect(!(await fileSystem.exists(stored.item.storedPath)))
  }

  @Test("marks the item restored and keeps it in the history")
  func restoredItemStaysInTheHistory() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 37, in: fileSystem, store: store)

    try await store.restore(itemID: stored.item.id)

    let history = try await store.items(includingRestored: true)
    #expect(safetyNetItem(stored.item.id, in: history)?.isRestored == true)
  }

  @Test("excludes a restored item from the default listing")
  func restoredItemLeavesTheDefaultListing() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 38, in: fileSystem, store: store)

    try await store.restore(itemID: stored.item.id)

    let listed = try await store.items(includingRestored: false)
    #expect(safetyNetItem(stored.item.id, in: listed) == nil)
  }

  @Test("refuses a second restore with alreadyRestored")
  func secondRestoreIsRefused() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 39, in: fileSystem, store: store)
    try await store.restore(itemID: stored.item.id)

    await #expect(throws: SafetyNetError.alreadyRestored(stored.item.id)) {
      try await store.restore(itemID: stored.item.id)
    }
  }

  @Test("leaves the already restored file untouched when it refuses")
  func secondRestoreChangesNothing() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 40, in: fileSystem, store: store)
    try await store.restore(itemID: stored.item.id)

    try? await store.restore(itemID: stored.item.id)

    let after = try await safetyNetState(of: Self.origin, in: fileSystem)
    expectSameFile(after, stored.before)
  }

  @Test("throws itemNotFound for an identifier it never issued")
  func unknownIdentifierIsNotFound() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    _ = try await storedAgent(seed: 41, in: fileSystem, store: store)
    let unknown = Fixture.uuid(0xEE)

    await #expect(throws: SafetyNetError.itemNotFound(unknown)) {
      try await store.restore(itemID: unknown)
    }
  }

  // MARK: - An occupied origin

  /// Stores the agent, then puts a different file where it used to live. This
  /// is the case where a naive restore overwrites somebody's work.
  private func storedAgentWithOccupiedOrigin(
    seed: UInt8,
    in fileSystem: InMemoryFileSystem,
    store: SafetyNetStore
  ) async throws -> (item: SafetyNetItem, occupier: SafetyNetPathState) {
    let stored = try await storedAgent(seed: seed, in: fileSystem, store: store)
    let occupier = try await safetyNetSeedFile(
      in: fileSystem,
      at: Self.origin,
      seed: seed &+ 100,
      extendedAttributes: [SafetyNetFixture.tagAttributeName: Data([0xAB, 0xCD])],
      created: SafetyNetFixture.createdDate.addingTimeInterval(5_000),
      modified: SafetyNetFixture.modifiedDate.addingTimeInterval(5_000)
    )
    return (stored.item, occupier)
  }

  @Test("refuses an occupied origin, naming the path")
  func occupiedOriginIsRefused() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let scene = try await storedAgentWithOccupiedOrigin(seed: 42, in: fileSystem, store: store)

    await #expect(throws: SafetyNetError.originOccupied(Self.origin)) {
      try await store.restore(itemID: scene.item.id)
    }
  }

  @Test("leaves the file already at the origin exactly as it was")
  func occupierSurvivesARefusedRestore() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let scene = try await storedAgentWithOccupiedOrigin(seed: 43, in: fileSystem, store: store)

    try? await store.restore(itemID: scene.item.id)

    let after = try await safetyNetState(of: Self.origin, in: fileSystem)
    expectSameFile(after, scene.occupier)
  }

  @Test("keeps the payload in the store when it refuses")
  func payloadStaysStoredAfterARefusedRestore() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let scene = try await storedAgentWithOccupiedOrigin(seed: 44, in: fileSystem, store: store)

    try? await store.restore(itemID: scene.item.id)

    #expect(await fileSystem.exists(scene.item.storedPath))
    let listed = try await store.items(includingRestored: false)
    #expect(safetyNetItem(scene.item.id, in: listed)?.isRestored == false)
  }

  @Test("restores once the occupying file is out of the way")
  func restoreSucceedsAfterTheOccupierIsRemoved() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let before = try await safetyNetSeedFile(
      in: fileSystem, at: Self.origin, seed: 45, isExecutable: true)
    let item = try await store.store(Self.origin, source: .malwareQuarantine, groupID: nil)
    try await safetyNetSeedFile(in: fileSystem, at: Self.origin, seed: 145)
    try? await store.restore(itemID: item.id)

    try await fileSystem.delete(Self.origin)
    try await store.restore(itemID: item.id)

    let after = try await safetyNetState(of: Self.origin, in: fileSystem)
    expectSameFile(after, before)
  }
}
