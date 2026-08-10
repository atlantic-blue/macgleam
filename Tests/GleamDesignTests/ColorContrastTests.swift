import AppKit
import Foundation
import GleamDesign
import SwiftUI
import Testing

@Suite("Semantic colour contrast")
struct ColorContrastTests {

  static let foregrounds: [GleamColorToken] = [
    .safe, .review, .dangerous, .textPrimary, .textSecondary, .primary, .accent,
  ]
  /// Every surface text is allowed to sit on. surfaceLowest and surfaceBright
  /// are wells that hold a glyph or an image, never running text.
  static let backgrounds: [GleamColorToken] = [
    .baseBackground, .surfaceLow, .surface, .surfaceHigh,
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
