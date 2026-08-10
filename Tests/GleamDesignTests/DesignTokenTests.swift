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

  @Test("exactly three elevation levels exist")
  func exactlyThreeElevationLevelsExist() {
    #expect(GleamElevation.allCases.count == 3)
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
