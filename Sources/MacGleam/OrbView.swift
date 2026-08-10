import GleamDesign
import GleamHub
import SwiftUI

/// Renders the orb from its resolved `OrbAppearance`. Breathing scale runs on
/// a timeline at the resolved period; mood transitions animate with the
/// resolved C2 token. Under Reduce Motion the gradient is static and mood
/// changes crossfade.
struct OrbView: View {
  let mood: OrbMood
  var diameter: CGFloat = GleamSpacing.points(5)
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    switch OrbAppearanceResolver.appearance(for: mood, reduceMotion: reduceMotion) {
    case .breathing(let spring, let period, let sheen):
      breathingOrb(spring: spring, period: period, sheen: sheen)
    case .staticGradient(let sheen, let moodChangeFade):
      orbCircle(sheen: sheen)
        .animation(.easeInOut(duration: seconds(of: moodChangeFade.duration)), value: mood)
    case .shimmerBand, .determinateRing, .resultPulse, .lustreBloom:
      orbCircle(sheen: .iridescent)
    }
  }

  private func breathingOrb(spring: GleamSpring, period: Duration, sheen: OrbSheen)
    -> some View
  {
    TimelineView(.animation) { context in
      let elapsed = context.date.timeIntervalSinceReferenceDate
      let phase = sin(elapsed * 2 * .pi / seconds(of: period))
      orbCircle(sheen: sheen)
        .scaleEffect(1 + 0.02 * phase)
    }
    .animation(spring.animation(reduceMotion: false), value: mood)
  }

  private func orbCircle(sheen: OrbSheen) -> some View {
    let tint = sheenColor(sheen)
    let surface = GleamColorToken.surface.color(for: colorScheme)
    return ZStack {
      Circle()
        .fill(
          RadialGradient(
            colors: [tint.opacity(0.85), tint.opacity(0.3), surface],
            center: UnitPoint(x: 0.35, y: 0.3),
            startRadius: diameter * 0.05,
            endRadius: diameter * 0.65
          )
        )
      Circle()
        .strokeBorder(tint.opacity(0.4), lineWidth: 1)
    }
    .frame(width: diameter, height: diameter)
  }

  private func sheenColor(_ sheen: OrbSheen) -> Color {
    switch sheen {
    case .iridescent:
      return GleamColorToken.accent.color(for: colorScheme)
    case .warmedToReview:
      return GleamColorToken.review.color(for: colorScheme)
    }
  }

  private func seconds(of duration: Duration) -> Double {
    Double(duration.components.seconds)
      + Double(duration.components.attoseconds) / 1e18
  }
}
