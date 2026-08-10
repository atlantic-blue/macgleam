import GleamDesign
import GleamHub
import SwiftUI

/// The window's top bar: the app name, a search well, and the small controls
/// that belong to the window rather than to any one module.
struct TopBarView: View {
  @Binding var searchText: String
  let onOpenSettings: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @FocusState private var searchHasFocus: Bool

  static let height: CGFloat = GleamSpacing.points(8)

  var body: some View {
    HStack(spacing: GleamSpacing.points(2)) {
      Text("MacGleam")
        .gleamType(.title)
        .fontWeight(.bold)
        .foregroundStyle(GleamColorToken.primary.color(for: colorScheme))
      Spacer(minLength: GleamSpacing.points(2))
      searchWell
      IconControl(symbolName: "gearshape", help: "Settings", action: onOpenSettings)
    }
    // The title bar is hidden, so the close, minimise and zoom buttons float
    // over this row's leading edge. The inset is the room they need.
    .padding(.leading, GleamSpacing.points(10))
    .padding(.trailing, GleamSpacing.points(3))
    .frame(height: Self.height)
    .frame(maxWidth: .infinity)
    .background(GleamColorToken.baseBackground.color(for: colorScheme))
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.white.opacity(GleamElevation.low.borderOpacity))
        .frame(height: 1)
    }
  }

  private var searchWell: some View {
    HStack(spacing: GleamSpacing.points(1)) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      TextField("Search tools", text: $searchText)
        .textFieldStyle(.plain)
        .gleamType(.body)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
        .focused($searchHasFocus)
        .frame(width: GleamSpacing.points(24))
    }
    .padding(.horizontal, GleamSpacing.half(3))
    .padding(.vertical, GleamSpacing.half(3) / 2)
    .background(
      RoundedRectangle(cornerRadius: GleamRadius.item.value)
        .fill(Color.black.opacity(0.2))
    )
    .overlay(
      RoundedRectangle(cornerRadius: GleamRadius.item.value)
        .strokeBorder(
          searchHasFocus
            ? GleamColorToken.accent.color(for: colorScheme).opacity(0.5)
            : Color.white.opacity(GleamElevation.low.borderOpacity),
          lineWidth: searchHasFocus ? 2 : 1
        )
    )
  }
}

/// A bare glyph control: no chrome until the pointer arrives.
struct IconControl: View {
  let symbolName: String
  let help: String
  let action: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbolName)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .frame(width: GleamSpacing.points(4), height: GleamSpacing.points(4))
        .background(
          Circle().fill(isHovering ? Color.white.opacity(0.1) : .clear)
        )
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help(help)
  }
}
