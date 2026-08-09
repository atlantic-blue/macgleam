import GleamDesign
import GleamHub
import SwiftUI

/// The hub window: the orb centre stage, the status line under it, and the
/// six module cards flanking it in `HubModule.allCases` order.
struct HubView: View {
  let model: HubModel
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: GleamSpacing.points(4)) {
      cardColumn(Array(model.cards.prefix(3)))
      statusScene
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      cardColumn(Array(model.cards.suffix(3)))
    }
    .padding(GleamSpacing.points(4))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(GleamColorToken.baseBackground.color(for: colorScheme))
  }

  private var statusScene: some View {
    VStack(spacing: GleamSpacing.points(3)) {
      OrbView(mood: model.orbMood)
      Text(model.statusLine)
        .font(GleamTypeToken.body.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .multilineTextAlignment(.center)
    }
  }

  private func cardColumn(_ cards: [HubCard]) -> some View {
    VStack(spacing: GleamSpacing.points(3)) {
      ForEach(cards) { card in
        HubCardView(card: card)
      }
    }
    .frame(width: 220)
  }
}
