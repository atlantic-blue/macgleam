import CoreGraphics

/// Three nested radii. A container holds items, an item holds controls, and
/// each step in is sharper than the one around it.
public enum GleamRadius: CaseIterable, Sendable {
  case card
  case item
  case control

  public var value: CGFloat {
    switch self {
    case .card: return 12
    case .item: return 8
    case .control: return 6
    }
  }
}
