import DiskMapModule
import GleamCore
import GleamDesign
import SwiftUI

/// The map: a squarified treemap over the focused folder's children, and
/// beneath it a list of the same children at a readable row height.
///
/// The treemap answers where the space went at a glance. The list answers
/// what each entry is called and exactly how much it holds, which a tile too
/// small to carry a label cannot. Selection and drilling work the same way in
/// both, so neither is the second class one.
struct DiskMapMapCanvas: View {
  let map: DiskMapMapState
  let onToggle: (AbsolutePath) -> Void
  let onDrillIn: (AbsolutePath) -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let listRowHeight: CGFloat = GleamSpacing.points(5)
  private static let listMaxHeight: CGFloat = GleamSpacing.points(30)

  var body: some View {
    if let focused = focusedNode, !focused.children.isEmpty {
      VStack(spacing: GleamSpacing.points(2)) {
        treemap(focused)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        list(focused)
          .frame(maxHeight: Self.listMaxHeight)
      }
      .animation(GleamSpring.gentle.animation(reduceMotion: reduceMotion), value: rowShape)
    } else {
      Text(focusedNode == nil ? "Waiting for the first folders\u{2026}" : "Nothing inside yet")
        .gleamType(.body)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func treemap(_ focused: DiskMapTreeNode) -> some View {
    GeometryReader { proxy in
      let tiles = TreemapLayout.tiles(
        for: focused.children.map { TreemapItem(id: $0.path, weight: $0.allocatedBytesSoFar) },
        in: CGRect(origin: .zero, size: proxy.size)
      )
      ZStack(alignment: .topLeading) {
        ForEach(tiles, id: \.id) { tile in
          if let node = focused.children.first(where: { $0.path == tile.id }) {
            DiskMapTile(
              node: node,
              share: share(of: node, in: focused),
              isSelected: map.selectedPaths.contains(node.path),
              onToggle: { onToggle(node.path) },
              onDrillIn: { onDrillIn(node.path) }
            )
            .frame(width: max(tile.rect.width - 2, 0), height: max(tile.rect.height - 2, 0))
            .offset(x: tile.rect.minX + 1, y: tile.rect.minY + 1)
          }
        }
      }
    }
  }

  private func list(_ focused: DiskMapTreeNode) -> some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(focused.children) { child in
          DiskMapListRow(
            node: child,
            share: share(of: child, in: focused),
            isSelected: map.selectedPaths.contains(child.path),
            onToggle: { onToggle(child.path) },
            onDrillIn: { onDrillIn(child.path) }
          )
          .frame(height: Self.listRowHeight)
        }
      }
    }
  }

  private var focusedNode: DiskMapTreeNode? {
    guard let root = map.root else { return nil }
    var stack = [root]
    while let node = stack.popLast() {
      if node.path == map.focusPath { return node }
      stack.append(contentsOf: node.children)
    }
    return nil
  }

  private func share(of child: DiskMapTreeNode, in focused: DiskMapTreeNode) -> Double {
    let total = focused.children.reduce(UInt64(0)) { $0 + $1.allocatedBytesSoFar }
    guard total > 0 else { return 0 }
    return Double(child.allocatedBytesSoFar) / Double(total)
  }

  /// The identity the growth animation tracks: paths and their current
  /// totals.
  private var rowShape: [AbsolutePath: UInt64] {
    guard let focused = focusedNode else { return [:] }
    return Dictionary(
      uniqueKeysWithValues: focused.children.map { ($0.path, $0.allocatedBytesSoFar) }
    )
  }
}

/// One tile of the treemap. It carries its name and figure when it has the
/// room, its name alone when it has less, and nothing when it is small, at
/// which point the list underneath is where you read it.
struct DiskMapTile: View {
  let node: DiskMapTreeNode
  let share: Double
  let isSelected: Bool
  let onToggle: () -> Void
  let onDrillIn: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  private static let widthForAName: CGFloat = 56
  private static let heightForAName: CGFloat = 24
  private static let heightForAFigure: CGFloat = 44

  var body: some View {
    GeometryReader { proxy in
      RoundedRectangle(cornerRadius: GleamRadius.control.value)
        .fill(fill)
        .overlay(
          RoundedRectangle(cornerRadius: GleamRadius.control.value)
            .strokeBorder(
              isSelected
                ? GleamColorToken.accent.color(for: colorScheme)
                : Color.white.opacity(GleamElevation.low.borderOpacity),
              lineWidth: isSelected ? 2 : 1
            )
        )
        .overlay(alignment: .topLeading) {
          label(in: proxy.size)
            .padding(GleamSpacing.half(2))
        }
    }
    .contentShape(Rectangle())
    .onTapGesture(count: 2) {
      if node.isDirectory { onDrillIn() }
    }
    .onTapGesture {
      if node.isSelectable { onToggle() }
    }
    .help(helpLine)
  }

  @ViewBuilder
  private func label(in size: CGSize) -> some View {
    if size.width >= Self.widthForAName && size.height >= Self.heightForAName {
      VStack(alignment: .leading, spacing: 2) {
        Text(node.path.lastComponent)
          .gleamType(.caption)
          .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
          .lineLimit(1)
          .truncationMode(.middle)
        if size.height >= Self.heightForAFigure {
          Text(ByteFigure.string(node.allocatedBytesSoFar))
            .gleamType(.caption)
            .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        }
      }
    }
  }

  /// Every tile says what it is on hover, however small it is drawn.
  private var helpLine: String {
    let percent = Int((share * 100).rounded())
    return
      "\(node.path.lastComponent), \(ByteFigure.string(node.allocatedBytesSoFar)), \(percent) percent"
  }

  /// Brighter with size, so the eye lands on what is worth looking at, and
  /// never so bright that the label stops reading against it.
  private var fill: Color {
    GleamColorToken.accent.color(for: colorScheme).opacity(0.10 + 0.30 * share)
  }
}

/// One row of the list under the map: the same entry, at a height that never
/// changes, with a bar carrying its share.
struct DiskMapListRow: View {
  let node: DiskMapTreeNode
  let share: Double
  let isSelected: Bool
  let onToggle: () -> Void
  let onDrillIn: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isHovering = false

  private static let barWidth: CGFloat = GleamSpacing.points(14)

  var body: some View {
    HStack(spacing: GleamSpacing.points(1)) {
      if node.isSelectable {
        CleanupCheckmark(
          isSelected: isSelected,
          reduceMotion: reduceMotion,
          action: onToggle
        )
      } else {
        Image(systemName: "lock")
          .font(.system(size: 12))
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
          .help("Protected by the safety denylist; the map shows it but never offers it.")
      }
      Image(systemName: node.isDirectory ? "folder.fill" : "doc")
        .foregroundStyle(GleamColorToken.accent.color(for: colorScheme).opacity(0.8))
      Text(node.path.lastComponent)
        .gleamType(.body)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer(minLength: GleamSpacing.points(2))
      shareBar
      Text(ByteFigure.string(node.allocatedBytesSoFar))
        .gleamType(.caption)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .frame(width: GleamSpacing.points(9), alignment: .trailing)
        .contentTransition(.numericText())
        .animation(
          GleamSpring.snappy.animation(reduceMotion: reduceMotion),
          value: node.allocatedBytesSoFar
        )
      if node.isDirectory {
        Button(action: onDrillIn) {
          Image(systemName: "chevron.right")
            .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        }
        .buttonStyle(.plain)
      } else {
        Color.clear.frame(width: GleamSpacing.points(1))
      }
    }
    .padding(.horizontal, GleamSpacing.points(2))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: GleamRadius.control.value)
        .fill(isHovering ? Color.white.opacity(0.05) : .clear)
    )
    .onHover { isHovering = $0 }
    .contentShape(Rectangle())
    .onTapGesture(count: 2) {
      if node.isDirectory { onDrillIn() }
    }
  }

  /// The share as a bar rather than a number, so a column of entries can be
  /// compared without reading any of them.
  private var shareBar: some View {
    ZStack(alignment: .leading) {
      Capsule()
        .fill(GleamColorToken.surfaceHigh.color(for: colorScheme))
      Capsule()
        .fill(GleamColorToken.accent.color(for: colorScheme))
        .frame(width: max(2, Self.barWidth * share))
    }
    .frame(width: Self.barWidth, height: 4)
  }
}
