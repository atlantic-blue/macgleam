import CoreGraphics

/// Depth comes from tonal layering and a luminous hairline, not from heavy
/// shadows. A resting card casts nothing at all; only a lifted or floating
/// surface casts, and then sharply.
public enum GleamElevation: CaseIterable, Sendable {
  case low
  case medium
  case high

  /// Opacity of the white hairline drawn at the surface's edge.
  public var borderOpacity: Double {
    switch self {
    case .low: return 0.05
    case .medium: return 0.10
    case .high: return 0.10
    }
  }

  public var shadowOpacity: Double {
    switch self {
    case .low: return 0
    case .medium, .high: return 0.5
    }
  }

  public var shadowRadius: CGFloat {
    switch self {
    case .low: return 0
    case .medium, .high: return 12
    }
  }

  public var shadowOffsetY: CGFloat {
    switch self {
    case .low: return 0
    case .medium, .high: return 4
    }
  }
}
