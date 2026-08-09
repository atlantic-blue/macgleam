import GleamDesign

/// Pure mapping from mood and Reduce Motion flag to appearance. Total over
/// all ten combinations. Every animation named in a returned appearance is a
/// C2 token; with Reduce Motion on the result never contains a spring.
public enum OrbAppearanceResolver {
  public static func appearance(
    for mood: OrbMood,
    reduceMotion: Bool
  ) -> OrbAppearance {
    if reduceMotion {
      return reducedMotionAppearance(for: mood)
    }
    return fullMotionAppearance(for: mood)
  }

  private static func fullMotionAppearance(for mood: OrbMood) -> OrbAppearance {
    switch mood {
    case .idleHealthy:
      return .breathing(spring: .gentle, period: .seconds(6), sheen: .iridescent)
    case .idleAttention:
      return .breathing(spring: .gentle, period: .seconds(4), sheen: .warmedToReview)
    case .scanning:
      return .shimmerBand
    case .result:
      return .resultPulse(spring: .lively)
    case .cleanSweep:
      return .lustreBloom
    }
  }

  private static func reducedMotionAppearance(for mood: OrbMood) -> OrbAppearance {
    switch mood {
    case .scanning:
      return .determinateRing
    case .idleAttention:
      return .staticGradient(sheen: .warmedToReview, moodChangeFade: .standard)
    case .idleHealthy, .result, .cleanSweep:
      return .staticGradient(sheen: .iridescent, moodChangeFade: .standard)
    }
  }
}
