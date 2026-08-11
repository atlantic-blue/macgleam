import GleamDesign
import GleamHub
import SwiftUI

/// The thin bar along the window's bottom edge: what the machine is doing on
/// the left, which build this is on the right.
struct StatusBarView: View {
  let statusLine: String
  let mood: OrbMood
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: GleamSpacing.points(1)) {
      dot
      Text(statusLine)
        .gleamType(.caption)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .lineLimit(1)
      Spacer(minLength: GleamSpacing.points(2))
      Text(Self.versionLine)
        .gleamType(.caption)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme).opacity(0.6))
    }
    .padding(.horizontal, GleamSpacing.points(3))
    .frame(height: GleamSpacing.points(4))
    .frame(maxWidth: .infinity)
    .background(GleamColorToken.baseBackground.color(for: colorScheme))
    .overlay(alignment: .top) {
      Rectangle()
        .fill(GleamElevation.low.edge(for: colorScheme))
        .frame(height: 1)
    }
  }

  /// A steady light, never a pulsing one. Pulsing says work is happening,
  /// and nothing here is working: the colour is the whole message.
  private var dot: some View {
    Circle()
      .fill(dotColor)
      .frame(width: GleamSpacing.half(1) + 2, height: GleamSpacing.half(1) + 2)
  }

  private var dotColor: Color {
    switch mood {
    case .idleAttention: return GleamColorToken.review.color(for: colorScheme)
    default: return GleamColorToken.accent.color(for: colorScheme)
    }
  }

  private static let versionLine: String = {
    let bundle = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    return bundle.map { "MacGleam \($0)" } ?? "MacGleam"
  }()
}
