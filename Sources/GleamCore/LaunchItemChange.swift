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
}
