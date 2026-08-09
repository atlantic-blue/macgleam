import SwiftUI

/// The complete colour token set. Every colour in the app resolves through
/// these cases; there is no other source of colour constants.
public enum GleamColorToken: CaseIterable, Sendable {
  case baseBackground
  case surface
  case accent
  case textPrimary
  case textSecondary
  case safe
  case review
  case dangerous

  /// Resolved colour for the given appearance.
  ///
  /// safe, review, dangerous, textPrimary and textSecondary hold at least
  /// 4.5 to 1 contrast against both baseBackground and surface in both
  /// appearances.
  public func color(for appearance: ColorScheme) -> Color {
    switch appearance {
    case .light:
      return lightColor
    default:
      return darkColor
    }
  }

  private var darkColor: Color {
    switch self {
    case .baseBackground: return Self.sRGB(0x0A, 0x0E, 0x1A)
    case .surface: return Self.sRGB(0x14, 0x1A, 0x2E)
    case .accent: return Self.sRGB(0x6F, 0xE0, 0xE8)
    case .textPrimary: return Self.sRGB(0xF2, 0xF5, 0xFA)
    case .textSecondary: return Self.sRGB(0xA8, 0xB2, 0xC7)
    case .safe: return Self.sRGB(0x4F, 0xCE, 0x7E)
    case .review: return Self.sRGB(0xE5, 0xB8, 0x4A)
    case .dangerous: return Self.sRGB(0xF0, 0x76, 0x6B)
    }
  }

  private var lightColor: Color {
    switch self {
    case .baseBackground: return Self.sRGB(0xF5, 0xF7, 0xFB)
    case .surface: return Self.sRGB(0xFF, 0xFF, 0xFF)
    case .accent: return Self.sRGB(0x0A, 0x71, 0x85)
    case .textPrimary: return Self.sRGB(0x16, 0x21, 0x3A)
    case .textSecondary: return Self.sRGB(0x4A, 0x56, 0x6E)
    case .safe: return Self.sRGB(0x1B, 0x6F, 0x40)
    case .review: return Self.sRGB(0x7A, 0x52, 0x00)
    case .dangerous: return Self.sRGB(0xB3, 0x26, 0x1E)
    }
  }

  private static func sRGB(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Color {
    Color(
      .sRGB,
      red: Double(red) / 255,
      green: Double(green) / 255,
      blue: Double(blue) / 255,
      opacity: 1
    )
  }
}
