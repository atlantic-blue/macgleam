import Foundation

/// One recorded change to a login or background item: which item, what it was,
/// what it became and when. A plain value type carrying no behaviour; how a
/// change is produced, recorded, persisted or replayed belongs to C24.
public struct LaunchItemChange: Codable, Sendable, Equatable {
  public let item: LaunchItemID
  public let previousEnabled: Bool
  public let newEnabled: Bool
  public let changedAt: Date

  public init(item: LaunchItemID, previousEnabled: Bool, newEnabled: Bool, changedAt: Date) {
    self.item = item
    self.previousEnabled = previousEnabled
    self.newEnabled = newEnabled
    self.changedAt = changedAt
  }

  /// What the item was before MacGleam first changed it, read from the append
  /// only history rather than from the latest record: an item disabled twice
  /// with an enable in between was still disabled to begin with, and restoring
  /// it means leaving it disabled.
  ///
  /// Nil when the history holds no change for the item, which is nothing to
  /// restore rather than enabled. Reading nil as enabled is how a one click
  /// restore turns into switching on something the person never had on.
  public static func stateBeforeFirstChange(
    of item: LaunchItemID,
    in history: [LaunchItemChange]
  ) -> Bool? {
    history
      .filter { $0.item == item }
      .min { $0.changedAt < $1.changedAt }?
      .previousEnabled
  }
}
