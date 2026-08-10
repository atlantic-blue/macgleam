import GleamDesign

/// Which way a zoom goes. Space Lens drills into a folder and back out with
/// this, so one motion grammar covers every place the app pushes the user
/// deeper into something and returns them.
public enum HubZoomDirection: String, CaseIterable, Codable, Sendable, Equatable {
  case zoomIn
  case zoomOut
}

/// What the zoom does, as data.
public enum HubZoomAppearance: Sendable, Equatable {
  /// Full motion: the matched geometry zoom with a C2 spring.
  case matchedGeometry(spring: GleamSpring)
  /// Reduce Motion: a crossfade with a C2 fade token.
  case crossfade(fade: GleamFade)
}

/// Pure mapping from zoom direction and Reduce Motion flag to the animation
/// the view performs. With full motion both directions are matchedGeometry
/// with the snappy spring, so leaving is the exact reverse of entering.
/// With Reduce Motion both directions are a crossfade with the standard
/// fade; the result never contains a spring.
public enum HubZoomResolver {
  public static func appearance(
    for direction: HubZoomDirection,
    reduceMotion: Bool
  ) -> HubZoomAppearance {
    if reduceMotion {
      return .crossfade(fade: .standard)
    }
    switch direction {
    case .zoomIn, .zoomOut:
      return .matchedGeometry(spring: .snappy)
    }
  }
}
