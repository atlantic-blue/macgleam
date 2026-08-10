import GleamDesign
import GleamHub
import SwiftUI

/// The screen a module shows until its real surface ships: the module title,
/// its live figure, and one line naming the slice that delivers it.
struct ModulePlaceholderView: View {
  let card: HubCard
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: GleamSpacing.points(2)) {
      Text(card.module.title)
        .font(GleamTypeToken.title.font)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      if !card.figure.isEmpty {
        Text(card.figure)
          .font(GleamTypeToken.body.font)
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      }
      Text(card.module.shippingSliceLine)
        .font(GleamTypeToken.caption.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      RoundedRectangle(cornerRadius: GleamRadius.card.value)
        .fill(GleamColorToken.surface.color(for: colorScheme))
    )
    .padding(GleamSpacing.points(2))
  }
}

extension HubModule {
  var shippingSliceLine: String {
    switch self {
    case .fullSweep: return "The Full Sweep surface ships with slice s6b."
    case .cleanup: return "The Cleanup module ships with slice s1g."
    case .protection: return "The Protection module ships with slice s5b."
    case .performance: return "The Performance module ships with slice s3c."
    case .applications: return "The Applications module ships with slice s4c."
    case .leftovers: return "The Leftovers module ships with slice s2a."
    }
  }
}
