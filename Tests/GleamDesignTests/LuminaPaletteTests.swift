import AppKit
import Foundation
import GleamDesign
import SwiftUI
import Testing

/// Both appearances are checked hex for hex against their own specification,
/// Lumina Utility for dark and Clinical Precision for light, so a drive by
/// tweak to either fails here. Two things the tables below do not cover, said
/// plainly because a comment nobody can turn into a test is a comment that
/// gets deleted:
///
/// Three light values are pinned to what the code ships rather than to a
/// specification hex, because the Clinical Precision specification does not
/// name them. They live in their own table and their own test, and they prove
/// no conformance at all.
///
/// The dark semantic trio, safe, review and dangerous, is named in Lumina
/// Utility only as green, amber and red, so it carries no dark hex to check
/// against and none is pinned. What holds it is the contrast suite and the
/// cross appearance check below.
///
/// Where a specification's palette and its prose disagree, the prose wins,
/// per DECISIONS.md, 2026-08-11. The light rows that take a prose value say so
/// and give the frontmatter value they passed over.
@Suite("Lumina palette")
struct LuminaPaletteTests {

  static let specifiedDarkHexes: [(GleamColorToken, String)] = [
    (.baseBackground, "0A0E1A"),
    (.surfaceLowest, "050E1E"),
    (.surfaceLow, "121C2C"),
    (.surface, "141A2E"),
    (.surfaceHigh, "202A3B"),
    (.surfaceBright, "303A4B"),
    (.primary, "A9F9FF"),
    (.onPrimary, "00373A"),
    (.accent, "6FE0E8"),
    (.textPrimary, "D9E3F9"),
    (.textSecondary, "BCC9CA"),
    (.outline, "869394"),
    (.outlineVariant, "3D494A"),
  ]

  /// Light values the Clinical Precision specification names. The trailing
  /// comment on each row is the key or the sentence it comes from.
  static let specifiedLightHexes: [(GleamColorToken, String)] = [
    // Prose, level 0 of the elevation ladder. Frontmatter background is FAF8FF.
    (.baseBackground, "F5F7FB"),
    (.surfaceLowest, "FFFFFF"),  // surface-container-lowest
    (.surfaceLow, "F2F3FF"),  // surface-container-low
    // Prose, level 1, "pure white card surfaces". Frontmatter
    // surface-container is E9EDFF.
    (.surface, "FFFFFF"),
    (.surfaceHigh, "E1E7FF"),  // surface-container-high
    (.primary, "005767"),  // primary
    (.onPrimary, "FFFFFF"),  // on-primary
    // Prose, "a professional Teal accent". Frontmatter carries the same value
    // under primary-container, and its own primary is the darker 005767.
    (.accent, "0A7185"),
    // Prose, "a deep Navy primary text". Frontmatter on-surface is 101B34.
    (.textPrimary, "16213A"),
    // Prose, "use Secondary text for metadata, labels, and helper text".
    // Frontmatter on-surface-variant is 3F484B.
    (.textSecondary, "4A566E"),
    (.outline, "6F797C"),  // outline
    (.outlineVariant, "BEC8CC"),  // outline-variant
    (.dangerous, "BA1A1A"),  // error
  ]

  /// The light values the Clinical Precision specification does not give.
  /// These are pinned to the hex the code ships today, which stops one drifting
  /// unnoticed; none of them is evidence that the code matches a design,
  /// because there is no design value to match. Safe and review are named in
  /// the specification as the words green and amber and nothing more, so both
  /// were picked by hand to clear contrast on white. The specification's own
  /// surface-bright, FAF8FF, is a shade off its canvas, which would leave the
  /// top of the light container ramp indistinguishable from the bottom, so the
  /// ramp takes surface-container-highest instead.
  static let unspecifiedLightHexes: [(GleamColorToken, String)] = [
    (.surfaceBright, "D9E2FF"),  // surface-container-highest, not surface-bright
    (.safe, "1B6F40"),
    (.review, "7A5200"),
  ]

  @Test(
    "every specified token resolves to its specification hex in dark", arguments: specifiedDarkHexes
  )
  func everySpecifiedTokenResolvesToItsSpecificationHexInDark(
    token: GleamColorToken,
    expected: String
  ) throws {
    #expect(try hexString(of: token.color(for: .dark)) == expected)
  }

  @Test(
    "every specified token resolves to its specification hex in light",
    arguments: specifiedLightHexes
  )
  func everySpecifiedTokenResolvesToItsSpecificationHexInLight(
    token: GleamColorToken,
    expected: String
  ) throws {
    #expect(try hexString(of: token.color(for: .light)) == expected)
  }

  /// Pinning, not conformance. See the table's own note.
  @Test(
    "every light token the specification leaves unnamed still ships its pinned hex",
    arguments: unspecifiedLightHexes
  )
  func everyUnspecifiedLightTokenShipsItsPinnedHex(
    token: GleamColorToken,
    expected: String
  ) throws {
    #expect(try hexString(of: token.color(for: .light)) == expected)
  }

  /// Without this, a token added later would resolve in light with nothing
  /// checking the value, which is the hole these tables exist to close.
  @Test("every colour token has a light value in exactly one of the two tables")
  func everyColourTokenHasALightValueInExactlyOneTable() {
    let specified = Self.specifiedLightHexes.map(\.0)
    let pinned = Self.unspecifiedLightHexes.map(\.0)
    #expect(Set(specified).isDisjoint(with: Set(pinned)))
    #expect(Set(specified).union(pinned) == Set(GleamColorToken.allCases))
    #expect(specified.count + pinned.count == GleamColorToken.allCases.count)
  }

  /// Light is a specified appearance rather than the dark one with the lights
  /// turned up, so no token carries a value through unchanged. A token that
  /// legitimately should would be listed here as an exception; today none is.
  @Test(
    "no token resolves to the same colour in both appearances",
    arguments: GleamColorToken.allCases
  )
  func noTokenResolvesToTheSameColourInBothAppearances(token: GleamColorToken) throws {
    let dark = try hexString(of: token.color(for: .dark))
    let light = try hexString(of: token.color(for: .light))
    #expect(dark != light, "\(token) is \(dark) in both appearances")
  }

  @Test("the colour token case list is exactly the contract list")
  func theColourTokenCaseListIsExactlyTheContractList() {
    #expect(
      GleamColorToken.allCases == [
        .baseBackground,
        .surfaceLowest,
        .surfaceLow,
        .surface,
        .surfaceHigh,
        .surfaceBright,
        .primary,
        .onPrimary,
        .accent,
        .textPrimary,
        .textSecondary,
        .outline,
        .outlineVariant,
        .safe,
        .review,
        .dangerous,
      ])
  }

  @Test("the container ramp climbs in luminance from the canvas up")
  func theContainerRampClimbsInLuminanceFromTheCanvasUp() throws {
    let ramp: [GleamColorToken] = [.baseBackground, .surface, .surfaceHigh, .surfaceBright]
    let luminances = try ramp.map { try relativeLuminance(of: $0.color(for: .dark)) }
    #expect(luminances == luminances.sorted())
  }

  /// surfaceLow is brighter than surface as a raw token, and the design shows
  /// the navigation rail darker than a card. Both are true: the rail is drawn
  /// at 80 percent over the canvas and only the composite is ever seen.
  @Test("the navigation rail drawn at its specified opacity lands darker than a card")
  func theNavigationRailDrawnAtItsOpacityLandsDarkerThanACard() throws {
    let rail = try composite(
      GleamColorToken.surfaceLow.color(for: .dark),
      atOpacity: 0.8,
      over: GleamColorToken.baseBackground.color(for: .dark)
    )
    #expect(try hexString(of: rail) == "101928")
    #expect(
      try relativeLuminance(of: rail)
        < relativeLuminance(of: GleamColorToken.surface.color(for: .dark)))
  }

  @Test("primary and accent are different colours serving different roles")
  func primaryAndAccentAreDifferentColours() throws {
    let primary = try hexString(of: GleamColorToken.primary.color(for: .dark))
    let accent = try hexString(of: GleamColorToken.accent.color(for: .dark))
    #expect(primary != accent)
  }

  @Test("text on a primary fill clears four point five to one against it")
  func textOnAPrimaryFillClearsContrastAgainstIt() throws {
    for appearance in [ColorScheme.dark, .light] {
      let ratio = try contrastRatio(
        of: .onPrimary, over: .primary, in: appearance)
      #expect(ratio >= 4.5, "on primary over primary in \(appearance) reaches \(ratio)")
    }
  }
}

@Suite("Half step spacing")
struct HalfStepSpacingTests {

  @Test("half returns the count multiplied by four", arguments: [0, 1, 2, 3, 5, 6, 12])
  func halfReturnsTheCountMultipliedByFour(count: Int) {
    #expect(GleamSpacing.half(count) == CGFloat(count) * 4)
  }

  @Test("two half steps are one grid unit")
  func twoHalfStepsAreOneGridUnit() {
    #expect(GleamSpacing.half(2) == GleamSpacing.points(1))
  }
}

@Suite("Radius scale")
struct RadiusScaleTests {

  @Test("exactly three corner radii exist")
  func exactlyThreeCornerRadiiExist() {
    #expect(GleamRadius.allCases.count == 3)
  }

  @Test("the radii nest from control through item to card")
  func theRadiiNestFromControlThroughItemToCard() {
    #expect(GleamRadius.control.value < GleamRadius.item.value)
    #expect(GleamRadius.item.value < GleamRadius.card.value)
  }

  @Test("the radii are the specified values")
  func theRadiiAreTheSpecifiedValues() {
    #expect(GleamRadius.card.value == 12)
    #expect(GleamRadius.item.value == 8)
    #expect(GleamRadius.control.value == 6)
  }
}

@Suite("Type scale")
struct TypeScaleTests {

  static let specifiedMetrics: [(GleamTypeToken, CGFloat, CGFloat, CGFloat)] = [
    // role, point size, tracking, line height
    (.display, 56, -0.02 * 56, 64),
    (.heading, 34, -0.01 * 34, 40),
    (.title, 22, -0.01 * 22, 28),
    (.headline, 15, 0, 20),
    (.label, 14, 0, 20),
    (.body, 13, 0, 18),
    (.caption, 11, 0, 14),
    (.mono, 12, 0, 16),
  ]

  @Test("exactly eight type roles exist")
  func exactlyEightTypeRolesExist() {
    #expect(GleamTypeToken.allCases.count == 8)
  }

  @Test("every role carries its specified metrics", arguments: specifiedMetrics)
  func everyRoleCarriesItsSpecifiedMetrics(
    role: GleamTypeToken,
    size: CGFloat,
    tracking: CGFloat,
    lineHeight: CGFloat
  ) {
    #expect(role.size == size)
    #expect(abs(role.tracking - tracking) < 0.0001)
    #expect(role.lineSpacing == lineHeight - size)
  }

  @Test("only the display sizes carry negative tracking")
  func onlyTheDisplaySizesCarryNegativeTracking() {
    let tightened = GleamTypeToken.allCases.filter { $0.tracking < 0 }
    #expect(Set(tightened) == [.display, .heading, .title])
  }

  @Test("the roles descend in size with no two the same")
  func theRolesDescendInSizeWithNoTwoTheSame() {
    let textRoles = GleamTypeToken.allCases.filter { $0 != .mono }
    let sizes = textRoles.map(\.size)
    #expect(sizes == sizes.sorted(by: >))
    #expect(Set(sizes).count == sizes.count)
  }

  @Test("every type role resolves a distinct font")
  func everyTypeRoleResolvesADistinctFont() {
    let fonts = Set(GleamTypeToken.allCases.map(\.font))
    #expect(fonts.count == GleamTypeToken.allCases.count)
  }
}

@Suite("Elevation")
struct ElevationTests {

  @Test("a resting card casts nothing in dark, where tone does the separating")
  func aRestingCardCastsNothingInDark() {
    #expect(GleamElevation.low.shadow(for: .dark) == .none)
  }

  @Test("every level casts something in light, where there is no tone left above white")
  func everyLevelCastsSomethingInLight() {
    for level in GleamElevation.allCases {
      #expect(level.shadow(for: .light).opacity > 0)
      #expect(level.shadow(for: .light).radius > 0)
    }
  }

  @Test("shadow strength climbs with the level in both appearances")
  func shadowStrengthClimbsWithTheLevel() {
    for appearance in [ColorScheme.dark, .light] {
      let low = GleamElevation.low.shadow(for: appearance)
      let medium = GleamElevation.medium.shadow(for: appearance)
      let high = GleamElevation.high.shadow(for: appearance)
      #expect(low.opacity <= medium.opacity)
      #expect(medium.opacity <= high.opacity)
      #expect(low.radius <= medium.radius)
      #expect(medium.radius <= high.radius)
    }
  }

  @Test("the dark floating shadow is the one its specification names")
  func theDarkFloatingShadowIsTheOneItsSpecificationNames() {
    let shadow = GleamElevation.high.shadow(for: .dark)
    #expect(shadow.opacity == 0.5)
    #expect(shadow.radius == 12)
    #expect(shadow.offsetY == 4)
  }

  @Test("the light card and overlay shadows are the ones their specification names")
  func theLightShadowsAreTheOnesTheirSpecificationNames() {
    let card = GleamElevation.low.shadow(for: .light)
    #expect(card.opacity == 0.05)
    #expect(card.radius == 12)
    #expect(card.offsetY == 4)
    let overlay = GleamElevation.high.shadow(for: .light)
    #expect(overlay.opacity == 0.12)
    #expect(overlay.radius == 32)
    #expect(overlay.offsetY == 12)
  }

  @Test("a light shadow is cast in the text navy, never in black")
  func aLightShadowIsCastInTheTextNavy() throws {
    #expect(try hexString(of: GleamElevation.low.shadow(for: .light).color) == "16213A")
    #expect(try hexString(of: GleamElevation.high.shadow(for: .dark).color) == "000000")
  }

  @Test("a resting surface draws an edge and a lifted one does not need to")
  func aRestingSurfaceDrawsAnEdge() throws {
    for appearance in [ColorScheme.dark, .light] {
      #expect(try opacity(of: GleamElevation.low.edge(for: appearance)) > 0)
    }
  }

  @Test("the dark edge is white and the light edge is the specified separator")
  func theEdgeColourMatchesItsAppearance() throws {
    #expect(try hexString(of: GleamElevation.low.edge(for: .dark)) == "FFFFFF")
    #expect(try hexString(of: GleamElevation.low.edge(for: .light)) == "E1E5ED")
  }

  @Test("a dark edge stays faint enough to read as an edge, not a border")
  func aDarkEdgeStaysFaint() throws {
    for level in GleamElevation.allCases {
      #expect(try opacity(of: level.edge(for: .dark)) <= 0.2)
    }
  }
}

// Contrast arithmetic follows Web Content Accessibility Guidelines 2.1,
// success criterion 1.4.3 and its relative luminance definition.

func contrastRatio(
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

func relativeLuminance(of color: Color) throws -> Double {
  let resolved = try resolvedComponents(of: color)
  return 0.2126 * linearise(resolved.red) + 0.7152 * linearise(resolved.green)
    + 0.0722 * linearise(resolved.blue)
}

/// Source over composite, the same arithmetic a browser does for a colour
/// drawn at partial opacity on an opaque background.
func composite(_ top: Color, atOpacity opacity: Double, over bottom: Color) throws -> Color {
  let over = try resolvedComponents(of: top)
  let under = try resolvedComponents(of: bottom)
  return Color(
    .sRGB,
    red: over.red * opacity + under.red * (1 - opacity),
    green: over.green * opacity + under.green * (1 - opacity),
    blue: over.blue * opacity + under.blue * (1 - opacity),
    opacity: 1
  )
}

func opacity(of color: Color) throws -> Double {
  let resolved = try #require(
    NSColor(color).usingColorSpace(.sRGB), "colour must resolve into the sRGB space")
  return Double(resolved.alphaComponent)
}

func hexString(of color: Color) throws -> String {
  let resolved = try resolvedComponents(of: color)
  let channels = [resolved.red, resolved.green, resolved.blue]
    .map { String(format: "%02X", Int((($0 * 255).rounded()))) }
  return channels.joined()
}

private func resolvedComponents(of color: Color) throws -> (
  red: Double, green: Double, blue: Double
) {
  let resolved = try #require(
    NSColor(color).usingColorSpace(.sRGB),
    "colour must resolve into the sRGB space"
  )
  return (
    Double(resolved.redComponent), Double(resolved.greenComponent),
    Double(resolved.blueComponent)
  )
}

private func linearise(_ channel: Double) -> Double {
  channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
}
