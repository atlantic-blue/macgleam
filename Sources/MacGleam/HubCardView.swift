import GleamDesign
import GleamHub
import SwiftUI

/// One module card. Renders its title and live figure; entering the module is
/// later slice territory.
struct HubCardView: View {
  let card: HubCard
  @Environment(\.colorScheme) private var colorScheme

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
    .opacity(card.isEnabled ? 1 : 0.5)
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
