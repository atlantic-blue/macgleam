import CoreGraphics
import SwiftUI

/// A surface's shadow, as data.
public struct GleamShadow: Sendable, Equatable {
  public let color: Color
  public let opacity: Double
  public let radius: CGFloat
  public let offsetY: CGFloat

  public init(color: Color, opacity: Double, radius: CGFloat, offsetY: CGFloat) {
    self.color = color
    self.opacity = opacity
    self.radius = radius
    self.offsetY = offsetY
  }

  /// No shadow at all, which is what a resting surface casts in dark.
  public static let none = GleamShadow(color: .black, opacity: 0, radius: 0, offsetY: 0)
}

/// How far a surface sits above the one behind it.
///
/// The two appearances raise a surface differently, and this is not a detail
/// that can be averaged. Dark separates layers by tone and a luminous
/// hairline, so a resting card casts nothing and only a floating one casts,
/// sharply. Light has no tone left to spend above white, so every card casts a
/// soft ambient shadow and an overlay casts a much wider one.
public enum GleamElevation: CaseIterable, Sendable {
  /// A resting card.
  case low
  /// A hovered or focused card.
  case medium
  /// A floating menu, popover or modal.
  case high

  /// The hairline drawn at the surface's edge, already at its opacity. Light
  /// pulls a card away from white with a grey stroke; dark lifts it with a
  /// white one.
  public func edge(for appearance: ColorScheme) -> Color {
    if appearance == .light {
      return Self.lightEdge.opacity(self == .low ? 1 : 0)
    }
    return .white.opacity(self == .low ? 0.05 : 0.10)
  }

  public func shadow(for appearance: ColorScheme) -> GleamShadow {
    if appearance == .light {
      switch self {
      case .low: return GleamShadow(color: Self.lightShadow, opacity: 0.05, radius: 12, offsetY: 4)
      case .medium:
        return GleamShadow(color: Self.lightShadow, opacity: 0.08, radius: 20, offsetY: 8)
      case .high:
        return GleamShadow(color: Self.lightShadow, opacity: 0.12, radius: 32, offsetY: 12)
      }
    }
    switch self {
    case .low: return .none
    case .medium, .high:
      return GleamShadow(color: .black, opacity: 0.5, radius: 12, offsetY: 4)
    }
  }

  /// The separator the light specification names for white on white edges.
  private static let lightEdge = Color(.sRGB, red: 0xE1 / 255, green: 0xE5 / 255, blue: 0xED / 255)

  /// Light shadows are cast in the primary text navy, not in black, so they
  /// read as depth rather than as dirt.
  private static let lightShadow = Color(
    .sRGB, red: 0x16 / 255, green: 0x21 / 255, blue: 0x3A / 255)
}

extension View {
  /// Applies an elevation's shadow for the given appearance.
  public func gleamShadow(_ level: GleamElevation, for appearance: ColorScheme) -> some View {
    let shadow = level.shadow(for: appearance)
    return self.shadow(
      color: shadow.color.opacity(shadow.opacity),
      radius: shadow.radius,
      y: shadow.offsetY
    )
  }
}
