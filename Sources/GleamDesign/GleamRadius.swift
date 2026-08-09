import CoreGraphics

public enum GleamRadius: CaseIterable, Sendable {
  case card
  case control

  public var value: CGFloat {
    switch self {
    case .card: return 12
    case .control: return 6
    }
  }
}
