import GleamDesign
import GleamHub
import SwiftUI

/// One module card. Renders its title and live figure, breathes on hover,
/// shows the keyboard focus ring, and enters its module on click through the
/// same resolver path as Return.
struct HubCardView: View {
  let card: HubCard
  let isFocused: Bool
  let onEnter: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isHovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(1)) {
      Text(card.module.title)
        .font(GleamTypeToken.body.font.weight(.semibold))
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text(card.figure)
        .font(GleamTypeToken.caption.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .frame(minHeight: GleamSpacing.points(2))
    }
    .padding(GleamSpacing.points(2))
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: GleamRadius.card.value)
        .fill(GleamColorToken.surface.color(for: colorScheme))
    )
    .overlay(
      RoundedRectangle(cornerRadius: GleamRadius.card.value)
        .strokeBorder(
          isFocused
            ? GleamColorToken.accent.color(for: colorScheme)
            : Color.clear,
          lineWidth: 2
        )
    )
    .opacity(card.isEnabled ? 1 : 0.5)
    .scaleEffect(isHovering ? 1.02 : 1)
    .animation(GleamSpring.snappy.animation(reduceMotion: reduceMotion), value: isHovering)
    .onHover { isHovering = $0 }
    .contentShape(RoundedRectangle(cornerRadius: GleamRadius.card.value))
    .onTapGesture(perform: onEnter)
  }
}

extension HubModule {
  var title: String {
    switch self {
    case .smartCare: return "Smart Care"
    case .cleanup: return "Cleanup"
    case .protection: return "Protection"
    case .performance: return "Performance"
    case .applications: return "Applications"
    case .myClutter: return "My Clutter"
    }
  }
}
