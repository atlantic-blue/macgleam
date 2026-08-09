import Foundation
import GleamDesign
import GleamHub
import Testing

@Suite("Hub zoom appearance")
struct HubZoomAppearanceTests {

  @Test(
    "full motion is matched geometry with the snappy spring for both directions",
    arguments: HubZoomDirection.allCases
  )
  func fullMotionIsMatchedGeometryWithTheSnappySpringForBothDirections(
    direction: HubZoomDirection
  ) {
    #expect(
      HubZoomResolver.appearance(for: direction, reduceMotion: false)
        == .matchedGeometry(spring: .snappy)
    )
  }

  @Test("leaving uses the same token as entering under full motion")
  func leavingUsesTheSameTokenAsEnteringUnderFullMotion() {
    let entering = HubZoomResolver.appearance(for: .zoomIn, reduceMotion: false)
    let leaving = HubZoomResolver.appearance(for: .zoomOut, reduceMotion: false)
    #expect(entering == leaving)
  }

  @Test(
    "reduce motion is a crossfade with the standard fade for both directions",
    arguments: HubZoomDirection.allCases
  )
  func reduceMotionIsACrossfadeWithTheStandardFadeForBothDirections(
    direction: HubZoomDirection
  ) {
    #expect(
      HubZoomResolver.appearance(for: direction, reduceMotion: true)
        == .crossfade(fade: .standard)
    )
  }

  @Test(
    "reduce motion never returns matched geometry for any direction",
    arguments: HubZoomDirection.allCases
  )
  func reduceMotionNeverReturnsMatchedGeometryForAnyDirection(direction: HubZoomDirection) {
    let appearance = HubZoomResolver.appearance(for: direction, reduceMotion: true)
    if case .matchedGeometry = appearance {
      Issue.record("reduce motion returned matched geometry for \(direction)")
    }
  }

  @Test(
    "the resolver is total and deterministic over all four direction and reduce motion pairs",
    arguments: HubZoomDirection.allCases, [false, true]
  )
  func theResolverIsTotalAndDeterministicOverAllFourPairs(
    direction: HubZoomDirection,
    reduceMotion: Bool
  ) {
    let first = HubZoomResolver.appearance(for: direction, reduceMotion: reduceMotion)
    let second = HubZoomResolver.appearance(for: direction, reduceMotion: reduceMotion)
    #expect(first == second)
  }
}
