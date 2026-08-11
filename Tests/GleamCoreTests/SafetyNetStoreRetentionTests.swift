import Foundation
import GleamCore
import Testing

/// C18, retention. Expiry marks eligibility and does nothing else: an expired
/// item is still there and still restorable. Removing it for good is a
/// separate, deliberate act that demands counts matching the items being
/// removed, the same shape as the permanent deletion confirmation in C6.
///
/// Every instant here is an argument. Nothing reads a clock.
@Suite("SafetyNet store: retention")
struct SafetyNetStoreRetentionTests {

  private static let origin = Fixture.path("/Users/julian/Downloads/agent")
  private static let secondOrigin = Fixture.path("/Users/julian/Downloads/loader")

  private static let justBeforeExpiry = SafetyNetFixture.expiryInstant.addingTimeInterval(-1)
  private static let justAfterExpiry = SafetyNetFixture.expiryInstant.addingTimeInterval(1)

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

  // MARK: - Expiry marks eligibility only

  @Test("reports nothing eligible a second before the item expires")
  func nothingIsEligibleBeforeExpiry() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    _ = try await storedAgent(seed: 100, in: fileSystem, store: store)

    let eligible = try await store.purgeEligibleItems(asOf: Self.justBeforeExpiry)

    #expect(eligible.isEmpty)
  }

  @Test("reports the item eligible a second after it expires")
  func theItemIsEligibleAfterExpiry() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 101, in: fileSystem, store: store)

    let eligible = try await store.purgeEligibleItems(asOf: Self.justAfterExpiry)

    #expect(safetyNetIdentifiers(eligible) == [stored.item.id])
  }

  @Test("keeps an expired item in the listing")
  func anExpiredItemIsStillListed() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 102, in: fileSystem, store: store)

    _ = try await store.purgeEligibleItems(asOf: Self.justAfterExpiry)

    let listed = try await store.items(includingRestored: false)
    #expect(safetyNetItem(stored.item.id, in: listed) == stored.item)
    #expect(await fileSystem.exists(stored.item.storedPath))
  }

  @Test("restores an expired item exactly, because time deletes nothing")
  func anExpiredItemIsStillRestorable() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 103, in: fileSystem, store: store)
    _ = try await store.purgeEligibleItems(asOf: Self.justAfterExpiry)

    try await store.restore(itemID: stored.item.id)

    let after = try await safetyNetState(of: Self.origin, in: fileSystem)
    expectSameFile(after, stored.before)
  }

  @Test("changes nothing when asked which items are eligible")
  func askingWhatIsEligibleMovesNothing() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 104, in: fileSystem, store: store)
    let payloadBefore = try await safetyNetState(of: stored.item.storedPath, in: fileSystem)

    _ = try await store.purgeEligibleItems(asOf: Self.justAfterExpiry)

    let payloadAfter = try await safetyNetState(of: stored.item.storedPath, in: fileSystem)
    expectSameFile(payloadAfter, payloadBefore)
    let history = try await store.items(includingRestored: true)
    #expect(safetyNetIdentifiers(history) == [stored.item.id])
  }

  // MARK: - Purge demands matching counts

  @Test("purges when the confirmation counts match")
  func matchingConfirmationPurges() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 105, in: fileSystem, store: store)
    let confirmation = try await safetyNetConfirmation(for: [stored.item], in: fileSystem)

    try await store.purge(itemIDs: [stored.item.id], confirmation: confirmation)

    #expect(!(await fileSystem.exists(stored.item.storedPath)))
    let history = try await store.items(includingRestored: true)
    #expect(history.isEmpty)
  }

  @Test("purges only the identifiers it was given")
  func purgeLeavesTheItemsItWasNotGiven() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 106, in: fileSystem, store: store)
    try await safetyNetSeedFile(in: fileSystem, at: Self.secondOrigin, seed: 107)
    let kept = try await store.store(Self.secondOrigin, source: .malwareQuarantine, groupID: nil)
    let confirmation = try await safetyNetConfirmation(for: [stored.item], in: fileSystem)

    try await store.purge(itemIDs: [stored.item.id], confirmation: confirmation)

    let history = try await store.items(includingRestored: true)
    #expect(safetyNetIdentifiers(history) == [kept.id])
    #expect(await fileSystem.exists(kept.storedPath))
  }

  @Test("refuses a confirmation whose item count does not match")
  func mismatchedItemCountIsRefused() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 108, in: fileSystem, store: store)
    let matching = try await safetyNetConfirmation(for: [stored.item], in: fileSystem)
    let wrongCount = PurgeConfirmation(
      itemCount: matching.itemCount + 1,
      byteTotal: matching.byteTotal,
      confirmedAt: matching.confirmedAt
    )

    await #expect(throws: SafetyNetError.confirmationMismatch) {
      try await store.purge(itemIDs: [stored.item.id], confirmation: wrongCount)
    }
    #expect(await fileSystem.exists(stored.item.storedPath))
    let history = try await store.items(includingRestored: true)
    #expect(safetyNetIdentifiers(history) == [stored.item.id])
  }

  @Test("refuses a confirmation whose byte total does not match")
  func mismatchedByteTotalIsRefused() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 109, in: fileSystem, store: store)
    let matching = try await safetyNetConfirmation(for: [stored.item], in: fileSystem)
    let wrongBytes = PurgeConfirmation(
      itemCount: matching.itemCount,
      byteTotal: matching.byteTotal + 1,
      confirmedAt: matching.confirmedAt
    )

    await #expect(throws: SafetyNetError.confirmationMismatch) {
      try await store.purge(itemIDs: [stored.item.id], confirmation: wrongBytes)
    }
    #expect(await fileSystem.exists(stored.item.storedPath))
    let history = try await store.items(includingRestored: true)
    #expect(safetyNetIdentifiers(history) == [stored.item.id])
  }

  @Test("refuses a confirmation that covers more items than were asked for")
  func confirmationForABiggerSetIsRefused() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 110, in: fileSystem, store: store)
    try await safetyNetSeedFile(in: fileSystem, at: Self.secondOrigin, seed: 111)
    let second = try await store.store(Self.secondOrigin, source: .malwareQuarantine, groupID: nil)
    let confirmationForBoth = try await safetyNetConfirmation(
      for: [stored.item, second], in: fileSystem)

    await #expect(throws: SafetyNetError.confirmationMismatch) {
      try await store.purge(itemIDs: [stored.item.id], confirmation: confirmationForBoth)
    }
    #expect(await fileSystem.exists(stored.item.storedPath))
    #expect(await fileSystem.exists(second.storedPath))
  }

  @Test("throws itemNotFound when one identifier of the batch is unknown")
  func unknownIdentifierInABatchIsNotFound() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 112, in: fileSystem, store: store)
    let unknown = Fixture.uuid(0xEF)
    let confirmation = try await safetyNetConfirmation(for: [stored.item], in: fileSystem)

    await #expect(throws: SafetyNetError.itemNotFound(unknown)) {
      try await store.purge(itemIDs: [stored.item.id, unknown], confirmation: confirmation)
    }
  }

  @Test("purges nothing when one identifier of the batch is unknown")
  func unknownIdentifierInABatchPurgesNothing() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)
    let stored = try await storedAgent(seed: 113, in: fileSystem, store: store)
    let confirmation = try await safetyNetConfirmation(for: [stored.item], in: fileSystem)

    try? await store.purge(
      itemIDs: [stored.item.id, Fixture.uuid(0xEF)], confirmation: confirmation)

    #expect(await fileSystem.exists(stored.item.storedPath))
    let history = try await store.items(includingRestored: true)
    #expect(safetyNetIdentifiers(history) == [stored.item.id])
  }
}
