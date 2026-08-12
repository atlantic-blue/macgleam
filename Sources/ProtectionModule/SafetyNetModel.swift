import Foundation
import GleamCore
import Observation

/// What the SafetyNet screen shows: everything MacGleam is holding, and the
/// two things a person can do with each of them.
///
/// Restore is one click because that is the whole promise. Purge is not: it
/// takes a confirmation naming the exact counts, because it is the one
/// irreversible thing in this app that acts on something already taken.
@MainActor @Observable
public final class SafetyNetModel {
  public private(set) var items: [SafetyNetItem] = []
  public private(set) var notice: String?
  public private(set) var isWorking = false

  @ObservationIgnored private let store: any SafetyNetStoring
  @ObservationIgnored private let now: @Sendable () -> Date

  public init(store: any SafetyNetStoring, now: @escaping @Sendable () -> Date = { Date() }) {
    self.store = store
    self.now = now
  }

  /// Everything still held, newest first, so the thing somebody just
  /// quarantined is the row they are looking for.
  public func reload() async {
    await work {
      items = try await store.items(includingRestored: false)
        .sorted { $0.storedAt > $1.storedAt }
    }
  }

  /// Puts one item back and reloads. An origin something else now occupies
  /// refuses and says so, rather than replacing whatever is there.
  public func restore(itemID: UUID) async {
    await work {
      try await store.restore(itemID: itemID)
      items = try await store.items(includingRestored: false)
        .sorted { $0.storedAt > $1.storedAt }
    }
  }

  /// Puts a whole uninstall back at once, or none of it.
  public func restoreGroup(groupID: UUID) async {
    await work {
      try await store.restoreGroup(groupID: groupID)
      items = try await store.items(includingRestored: false)
        .sorted { $0.storedAt > $1.storedAt }
    }
  }

  /// The exact scope a purge of these items needs confirming: the count and
  /// the bytes recorded when they were stored. The screen shows these numbers
  /// and the confirmation carries them back, so somebody agreed to a figure
  /// rather than to a word.
  public func purgeScope(itemIDs: [UUID]) -> PermanentDeletionScope? {
    let targets = items.filter { itemIDs.contains($0.id) }
    guard !targets.isEmpty else { return nil }
    return PermanentDeletionScope(
      fileCount: UInt32(targets.count),
      byteTotal: targets.reduce(0) { $0 + $1.allocatedBytes })
  }

  /// Purges only when the confirmation matches the scope exactly. A mismatch
  /// changes nothing and says so.
  @discardableResult
  public func purge(itemIDs: [UUID], confirmation: PermanentDeletionConfirmation?) async -> Bool {
    guard let scope = purgeScope(itemIDs: itemIDs), let confirmation else { return false }
    guard confirmation.fileCount == scope.fileCount, confirmation.byteTotal == scope.byteTotal
    else {
      notice = "Those numbers do not match what is being removed, so nothing was removed."
      return false
    }
    var purged = false
    await work {
      try await store.purge(
        itemIDs: itemIDs,
        confirmation: PurgeConfirmation(
          itemCount: scope.fileCount,
          byteTotal: scope.byteTotal,
          confirmedAt: confirmation.confirmedAt))
      items = try await store.items(includingRestored: false)
        .sorted { $0.storedAt > $1.storedAt }
      purged = true
    }
    return purged
  }

  /// What is past its thirty days and could be purged. Nothing here purges
  /// anything by itself: expiry marks eligibility and a person still decides.
  public func expiredItems() async -> [SafetyNetItem] {
    (try? await store.purgeEligibleItems(asOf: now())) ?? []
  }

  private func work(_ body: () async throws -> Void) async {
    isWorking = true
    notice = nil
    do {
      try await body()
    } catch {
      notice = Self.sentence(for: error)
    }
    isWorking = false
  }

  private static func sentence(for error: any Error) -> String {
    guard let described = (error as? any LocalizedError)?.errorDescription, !described.isEmpty
    else { return "The SafetyNet could not do that." }
    return described
  }
}
