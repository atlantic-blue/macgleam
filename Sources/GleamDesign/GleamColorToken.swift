import SwiftUI

/// The complete colour token set. Every colour in the app resolves through
/// these cases; there is no other source of colour constants.
///
/// Each appearance has its own specification and its values are those hexes
/// exactly: Lumina Utility for dark, Clinical Precision for light. Where a
/// specification's palette and its prose disagree, the prose wins, because it
/// is the part that says what the colour is for.
public enum GleamColorToken: CaseIterable, Sendable {
  case baseBackground
  case surfaceLowest
  case surfaceLow
  case surface
  case surfaceHigh
  case surfaceBright
  case primary
  case onPrimary
  case accent
  case textPrimary
  case textSecondary
  case outline
  case outlineVariant
  case safe
  case review
  case dangerous

  /// Resolved colour for the given appearance.
  ///
  /// safe, review, dangerous, primary, accent, textPrimary and textSecondary
  /// hold at least 4.5 to 1 contrast against every surface running text sits
  /// on, in both appearances.
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
    case .surfaceLowest: return Self.sRGB(0x05, 0x0E, 0x1E)
    case .surfaceLow: return Self.sRGB(0x12, 0x1C, 0x2C)
    case .surface: return Self.sRGB(0x14, 0x1A, 0x2E)
    case .surfaceHigh: return Self.sRGB(0x20, 0x2A, 0x3B)
    case .surfaceBright: return Self.sRGB(0x30, 0x3A, 0x4B)
    case .primary: return Self.sRGB(0xA9, 0xF9, 0xFF)
    case .onPrimary: return Self.sRGB(0x00, 0x37, 0x3A)
    case .accent: return Self.sRGB(0x6F, 0xE0, 0xE8)
    case .textPrimary: return Self.sRGB(0xD9, 0xE3, 0xF9)
    case .textSecondary: return Self.sRGB(0xBC, 0xC9, 0xCA)
    case .outline: return Self.sRGB(0x86, 0x93, 0x94)
    case .outlineVariant: return Self.sRGB(0x3D, 0x49, 0x4A)
    case .safe: return Self.sRGB(0x4F, 0xCE, 0x7E)
    case .review: return Self.sRGB(0xE5, 0xB8, 0x4A)
    case .dangerous: return Self.sRGB(0xF0, 0x76, 0x6B)
    }
  }

  private var lightColor: Color {
    switch self {
    case .baseBackground: return Self.sRGB(0xF5, 0xF7, 0xFB)
    case .surfaceLowest: return Self.sRGB(0xFF, 0xFF, 0xFF)
    case .surfaceLow: return Self.sRGB(0xF2, 0xF3, 0xFF)
    case .surface: return Self.sRGB(0xFF, 0xFF, 0xFF)
    case .surfaceHigh: return Self.sRGB(0xE1, 0xE7, 0xFF)
    case .surfaceBright: return Self.sRGB(0xD9, 0xE2, 0xFF)
    case .primary: return Self.sRGB(0x00, 0x57, 0x67)
    case .onPrimary: return Self.sRGB(0xFF, 0xFF, 0xFF)
    case .accent: return Self.sRGB(0x0A, 0x71, 0x85)
    case .textPrimary: return Self.sRGB(0x16, 0x21, 0x3A)
    case .textSecondary: return Self.sRGB(0x4A, 0x56, 0x6E)
    case .outline: return Self.sRGB(0x6F, 0x79, 0x7C)
    case .outlineVariant: return Self.sRGB(0xBE, 0xC8, 0xCC)
    case .safe: return Self.sRGB(0x1B, 0x6F, 0x40)
    case .review: return Self.sRGB(0x7A, 0x52, 0x00)
    case .dangerous: return Self.sRGB(0xBA, 0x1A, 0x1A)
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
