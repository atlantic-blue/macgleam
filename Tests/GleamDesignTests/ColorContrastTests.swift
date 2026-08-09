import AppKit
import Foundation
import GleamDesign
import SwiftUI
import Testing

@Suite("Semantic colour contrast")
struct ColorContrastTests {

  static let foregrounds: [GleamColorToken] = [
    .safe, .review, .dangerous, .textPrimary, .textSecondary,
  ]
  static let backgrounds: [GleamColorToken] = [
    .baseBackground, .surface,
  ]

  @Test(
    "semantic and text colours hold four point five to one in light appearance",
    arguments: foregrounds, backgrounds
  )
  func semanticAndTextColoursHoldContrastInLightAppearance(
    foreground: GleamColorToken,
    background: GleamColorToken
  ) throws {
    let ratio = try contrastRatio(of: foreground, over: background, in: .light)
    #expect(
      ratio >= 4.5,
      "\(foreground) over \(background) in light reaches \(ratio), the threshold is 4.5"
    )
  }

  @Test(
    "semantic and text colours hold four point five to one in dark appearance",
    arguments: foregrounds, backgrounds
  )
  func semanticAndTextColoursHoldContrastInDarkAppearance(
    foreground: GleamColorToken,
    background: GleamColorToken
  ) throws {
    let ratio = try contrastRatio(of: foreground, over: background, in: .dark)
    #expect(
      ratio >= 4.5,
      "\(foreground) over \(background) in dark reaches \(ratio), the threshold is 4.5"
    )
  }
}

// Contrast arithmetic follows Web Content Accessibility Guidelines 2.1,
// success criterion 1.4.3 and its relative luminance definition.

private func contrastRatio(
  of foreground: GleamColorToken,
  over background: GleamColorToken,
  in appearance: ColorScheme
) throws -> Double {
  let foregroundLuminance = try relativeLuminance(of: foreground.color(for: appearance))
  let backgroundLuminance = try relativeLuminance(of: background.color(for: appearance))
  let lighter = max(foregroundLuminance, backgroundLuminance)
  let darker = min(foregroundLuminance, backgroundLuminance)
  return (lighter + 0.05) / (darker + 0.05)
}

private func relativeLuminance(of color: Color) throws -> Double {
  let resolved = try #require(
    NSColor(color).usingColorSpace(.sRGB),
    "colour must resolve into the sRGB space"
  )
  let red = linearise(Double(resolved.redComponent))
  let green = linearise(Double(resolved.greenComponent))
  let blue = linearise(Double(resolved.blueComponent))
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue
}

private func linearise(_ channel: Double) -> Double {
  channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
}
