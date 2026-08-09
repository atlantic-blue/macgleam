import GleamDesign
import SwiftUI
import Testing

@Suite("Token cardinality")
struct TokenCardinalityTests {

  @Test("exactly three springs exist")
  func exactlyThreeSpringsExist() {
    #expect(GleamSpring.allCases.count == 3)
  }

  @Test("exactly two fades exist")
  func exactlyTwoFadesExist() {
    #expect(GleamFade.allCases.count == 2)
  }

  @Test("exactly two corner radii exist")
  func exactlyTwoCornerRadiiExist() {
    #expect(GleamRadius.allCases.count == 2)
  }

  @Test("exactly three elevation levels exist")
  func exactlyThreeElevationLevelsExist() {
    #expect(GleamElevation.allCases.count == 3)
  }

  @Test("exactly five type roles exist")
  func exactlyFiveTypeRolesExist() {
    #expect(GleamTypeToken.allCases.count == 5)
  }

  @Test("the colour token case list is exactly the contract list")
  func theColourTokenCaseListIsExactlyTheContractList() {
    #expect(
      GleamColorToken.allCases == [
        .baseBackground,
        .surface,
        .accent,
        .textPrimary,
        .textSecondary,
        .safe,
        .review,
        .dangerous,
      ])
  }
}

@Suite("Spacing grid")
struct SpacingGridTests {

  @Test("the grid unit is eight points")
  func theGridUnitIsEightPoints() {
    #expect(GleamSpacing.unit == 8)
  }

  @Test(
    "points returns the count multiplied by eight",
    arguments: [0, 1, 2, 3, 4, 6, 10, 25]
  )
  func pointsReturnsTheCountMultipliedByEight(count: Int) {
    #expect(GleamSpacing.points(count) == CGFloat(count) * 8)
  }
}

@Suite("Radii and type roles")
struct RadiusAndTypeRoleTests {

  @Test("the control radius is strictly smaller than the card radius")
  func theControlRadiusIsStrictlySmallerThanTheCardRadius() {
    #expect(GleamRadius.control.value < GleamRadius.card.value)
  }

  @Test("every type role resolves a distinct font")
  func everyTypeRoleResolvesADistinctFont() {
    let fonts = Set(GleamTypeToken.allCases.map(\.font))
    #expect(fonts.count == GleamTypeToken.allCases.count)
  }
}
