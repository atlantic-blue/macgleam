import Foundation
import GleamCore

/// The one way the app changes a login or background item, whether a plan
/// asked for it or a person flipped a switch.
///
/// It discovers, mutates and stores nothing itself: it holds the inventory,
/// the two changing sides and the store of prior state, and its whole job is
/// deciding which side a change goes to and remembering what the item was
/// before.
///
/// The scope it routes on is read from the item in the current inventory at
/// the moment of the change, never from what the caller passed in, so a stale
/// plan cannot decide which side of the privileged boundary a change lands on.
/// An item that is no longer in the inventory is refused by name before
/// anything is attempted.
public struct LaunchItemManager: LaunchItemManaging {
  private let source: any LaunchItemSourcing
  private let privileged: (any PrivilegedLaunchItemChanging)?
  private let store: any LaunchItemChangeRecording
  private let now: @Sendable () -> Date

  public init(
    source: any LaunchItemSourcing,
    privileged: (any PrivilegedLaunchItemChanging)? = nil,
    store: any LaunchItemChangeRecording,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.source = source
    self.privileged = privileged
    self.store = store
    self.now = now
  }

  public func list() async throws -> [LaunchItem] {
    try await source.items()
  }

  public func setEnabled(
    _ enabled: Bool,
    item: LaunchItemID,
    attribution: ChangeAttribution
  ) async throws -> LaunchItemChange {
    let target = try await resolve(item)
    let change = try await change(target, to: enabled, attribution: attribution)
    try await store.record(change)
    return change
  }

  /// The change somebody made in the interface, which belongs to no plan. The
  /// identifier is minted here, at the moment of the change, and names nothing
  /// else: no plan carries it and no `ExecutionReport` names it, so a direct
  /// change is attributable to itself rather than to a plan that never
  /// existed.
  ///
  /// This entry point exists on the manager and not on `LaunchItemManaging`,
  /// so a caller holding the protocol, the executor above all, still cannot
  /// make a change without saying which plan operation it is running.
  @discardableResult
  public func setEnabled(
    _ enabled: Bool,
    item: LaunchItemID
  ) async throws -> LaunchItemChange {
    try await setEnabled(enabled, item: item, attribution: .directChange(changeID: UUID()))
  }

  // MARK: - Resolution

  /// The item as the machine has it now. Everything downstream reads this and
  /// not the identifier the caller passed, which is what keeps the scope
  /// honest.
  private func resolve(_ item: LaunchItemID) async throws -> LaunchItem {
    let inventory: [LaunchItem]
    do {
      inventory = try await source.items()
    } catch {
      throw LaunchItemError.changeFailed(reason: Self.inventoryUnreadableSentence)
    }
    guard let target = inventory.first(where: { $0.identifier == item }) else {
      throw LaunchItemError.itemNotFound(item: item)
    }
    return target
  }

  // MARK: - Routing

  private func change(
    _ item: LaunchItem,
    to enabled: Bool,
    attribution: ChangeAttribution
  ) async throws -> LaunchItemChange {
    switch item.scope {
    case .user:
      return try await changeInProcess(item, to: enabled)
    case .system:
      return try await changeThroughHelper(item, to: enabled, attribution: attribution)
    }
  }

  /// The in process change, and the record of it. The prior state is the one
  /// the inventory reported a moment ago, which is why the record is minted
  /// here rather than by the side that performed the change: this is the only
  /// place that has read what the item was.
  private func changeInProcess(
    _ item: LaunchItem,
    to enabled: Bool
  ) async throws -> LaunchItemChange {
    do {
      try await source.setEnabled(enabled, item: item.identifier)
    } catch let error as LaunchItemError {
      throw error
    } catch {
      throw LaunchItemError.changeFailed(reason: Self.sentence(for: error, item: item))
    }
    return LaunchItemChange(
      item: item.identifier,
      previousEnabled: item.isEnabled,
      newEnabled: enabled,
      changedAt: now())
  }

  private func changeThroughHelper(
    _ item: LaunchItem,
    to enabled: Bool,
    attribution: ChangeAttribution
  ) async throws -> LaunchItemChange {
    guard let privileged else {
      throw LaunchItemError.changeFailed(reason: Self.helperMissingSentence(for: item))
    }
    do {
      return try await privileged.setLaunchItemEnabled(
        enabled, item: item.identifier, attribution: attribution)
    } catch let failure as PrivilegedLaunchItemFailure {
      throw Self.error(for: failure, item: item)
    } catch let error as LaunchItemError {
      throw error
    } catch {
      throw LaunchItemError.changeFailed(reason: Self.sentence(for: error, item: item))
    }
  }

  // MARK: - Sentences

  /// The privileged side's vocabulary, translated once. An item the helper
  /// cannot resolve is the item being gone, said in those words, rather than a
  /// protocol error shown to a person.
  private static func error(
    for failure: PrivilegedLaunchItemFailure,
    item: LaunchItem
  ) -> LaunchItemError {
    switch failure {
    case .itemUnresolvable:
      return .itemNotFound(item: item.identifier)
    case .refused(let reason):
      return .changeFailed(reason: reason)
    }
  }

  private static let inventoryUnreadableSentence =
    "The list of login items could not be read, so nothing was changed."

  private static func helperMissingSentence(for item: LaunchItem) -> String {
    "The privileged helper is not available, so \(item.label), which runs for "
      + "everybody on this Mac, was left unchanged."
  }

  private static func sentence(for error: any Error, item: LaunchItem) -> String {
    let description = error.localizedDescription
    guard description.isEmpty else { return description }
    return "The change to \(item.label) did not take effect, for an unknown reason."
  }
}
