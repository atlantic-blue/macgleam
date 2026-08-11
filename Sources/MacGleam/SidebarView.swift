import GleamDesign
import GleamHub
import SwiftUI

/// The navigation rail: the app's mark with its live health light, then every
/// destination in rail order with a gap before the group that sits apart.
struct SidebarView: View {
  let selection: HubDestination
  let orbMood: OrbMood
  let onSelect: (HubDestination) -> Void
  @Environment(\.colorScheme) private var colorScheme

  static let width: CGFloat = 240

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      brand
        .padding(.horizontal, GleamSpacing.half(1))
        .padding(.bottom, GleamSpacing.points(4))
        // The title bar is hidden, so the close, minimise and zoom buttons
        // float over this corner. The inset is the room they need.
        .padding(.top, GleamSpacing.points(4))
      ForEach(Array(HubDestination.allCases.enumerated()), id: \.element) { row, destination in
        if startsANewGroup(at: row) {
          Spacer(minLength: GleamSpacing.points(2))
        }
        RailItem(
          destination: destination,
          isSelected: destination == selection,
          onSelect: { onSelect(destination) }
        )
      }
      Spacer(minLength: 0)
    }
    .padding(GleamSpacing.points(2))
    .frame(width: Self.width, alignment: .leading)
    .frame(maxHeight: .infinity)
    .background(railFill)
    .overlay(alignment: .trailing) {
      Rectangle()
        .fill(Color.white.opacity(GleamElevation.low.borderOpacity))
        .frame(width: 1)
    }
  }

  /// The rail is specified as a translucent panel at 80 percent. Nothing
  /// scrolls behind it, so the composite is drawn directly and lands on the
  /// exact colour the specification renders.
  private var railFill: Color {
    GleamColorToken.surfaceLow.color(for: colorScheme)
      .opacity(0.8)
  }

  private func startsANewGroup(at row: Int) -> Bool {
    guard row > 0 else { return false }
    return HubDestination.allCases[row].group != HubDestination.allCases[row - 1].group
  }

  private var brand: some View {
    HStack(spacing: GleamSpacing.half(3)) {
      OrbView(mood: orbMood, diameter: GleamSpacing.points(5))
      VStack(alignment: .leading, spacing: GleamSpacing.half(1) / 2) {
        Text("MacGleam")
          .gleamType(.headline)
          .foregroundStyle(GleamColorToken.primary.color(for: colorScheme))
        Text("Pro Version")
          .gleamType(.caption)
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      }
    }
  }
}

/// One row of the rail. Selected rows carry the accent wash and accent text;
/// the rest lift on hover only.
private struct RailItem: View {
  let destination: HubDestination
  let isSelected: Bool
  let onSelect: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isHovering = false

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: GleamSpacing.half(3)) {
        Image(systemName: destination.symbolName)
          .font(.system(size: 16, weight: .medium))
          .frame(width: 20, alignment: .center)
        Text(destination.title)
          .gleamType(.label)
        Spacer(minLength: 0)
      }
      .foregroundStyle(foreground)
      .padding(.horizontal, GleamSpacing.half(3))
      .padding(.vertical, GleamSpacing.points(1))
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: GleamRadius.item.value)
          .fill(background)
      )
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .animation(GleamSpring.snappy.animation(reduceMotion: reduceMotion), value: isHovering)
    .animation(GleamSpring.snappy.animation(reduceMotion: reduceMotion), value: isSelected)
  }

  private var foreground: Color {
    if isSelected {
      return GleamColorToken.primary.color(for: colorScheme)
    }
    return GleamColorToken.textSecondary.color(for: colorScheme)
  }

  private var background: Color {
    if isSelected {
      return GleamColorToken.primary.color(for: colorScheme).opacity(0.10)
    }
    return isHovering ? Color.white.opacity(0.05) : .clear
  }
}
