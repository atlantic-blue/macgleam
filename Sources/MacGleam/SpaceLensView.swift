import GleamCore
import GleamDesign
import GleamHub
import SpaceLensModule
import SwiftUI

/// The Space Lens surface: one thin view over SpaceLensModuleModel, adding
/// no state of its own beyond presentation. The streaming map renders as
/// size proportional blocks that grow as totals converge; drilling into a
/// folder resolves through HubZoomResolver so the whole app keeps one
/// navigation language; selection, review and execution follow the Cleanup
/// flow, and every motion comes from the token set with Reduce Motion
/// fallbacks.
struct SpaceLensView: View {
  let model: SpaceLensModuleModel
  let executor: CancellableCleanupExecutor
  let onClose: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var confirmingScope: PermanentDeletionScope?

  private static let defaultVolume = AbsolutePath(normalising: "/")

  var body: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(2)) {
      header
      if let failure = model.failureNotice {
        CleanupNoticeCard(
          sentences: [failure],
          tint: GleamColorToken.review.color(for: colorScheme)
        )
      }
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(GleamSpacing.points(3))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      RoundedRectangle(cornerRadius: GleamRadius.card.value)
        .fill(GleamColorToken.surface.color(for: colorScheme))
    )
    .padding(GleamSpacing.points(2))
    .animation(GleamSpring.gentle.animation(reduceMotion: reduceMotion), value: stateShape)
    .confirmationDialog(
      "Delete permanently?",
      isPresented: isConfirmingPermanent,
      presenting: confirmingScope
    ) { scope in
      Button("Delete \(itemCountLine(scope.fileCount)) Permanently", role: .destructive) {
        model.executeSelection(
          permanentConfirmation: PermanentDeletionConfirmation(
            fileCount: scope.fileCount,
            byteTotal: scope.byteTotal,
            confirmedAt: Date()
          )
        )
      }
      Button("Cancel", role: .cancel) {}
    } message: { scope in
      Text(
        "This permanently deletes \(itemCountLine(scope.fileCount)) totalling \(ByteFigure.string(scope.byteTotal)). Permanent deletions cannot be undone."
      )
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("Space Lens")
        .font(GleamTypeToken.title.font)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Spacer()
      Button("Close") { onClose() }
        .buttonStyle(.plain)
        .font(GleamTypeToken.caption.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
    }
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .idle:
      SpaceLensIdleView(onMap: { model.startMapping(volume: Self.defaultVolume) })
    case .mapping(let map):
      mapScene(map, isStreaming: true)
    case .browsing(let map):
      mapScene(map, isStreaming: false)
    case .executing(let progress):
      SpaceLensExecutionView(
        progress: progress,
        onCancel: {
          model.cancelExecution()
          executor.requestCancellation()
        }
      )
    case .result(let summary):
      SpaceLensResultView(summary: summary, onDone: { model.acknowledgeResult() })
    }
  }

  private func mapScene(_ map: SpaceLensMapState, isStreaming: Bool) -> some View {
    VStack(spacing: GleamSpacing.points(2)) {
      SpaceLensBreadcrumb(
        map: map,
        isStreaming: isStreaming,
        onDrillOut: { performDrillOut() },
        onCancel: { model.cancelMapping() }
      )
      SpaceLensMapCanvas(
        map: map,
        onToggle: { model.toggleSelection($0) },
        onDrillIn: { performDrillIn(to: $0) }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      footer(map, isStreaming: isStreaming)
    }
  }

  private func footer(_ map: SpaceLensMapState, isStreaming: Bool) -> some View {
    HStack {
      Text(selectionLine(map))
        .font(GleamTypeToken.body.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .contentTransition(.numericText())
        .animation(
          GleamSpring.snappy.animation(reduceMotion: reduceMotion),
          value: map.selectedByteTotal
        )
      Spacer()
      if !isStreaming {
        Button("Remap") { model.startMapping(volume: map.volume) }
          .buttonStyle(.plain)
          .font(GleamTypeToken.caption.font)
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      }
      CleanupPrimaryButton(
        title: "Remove",
        action: beginExecution,
        isEnabled: !isStreaming && !map.selectedPaths.isEmpty
      )
    }
  }

  private func selectionLine(_ map: SpaceLensMapState) -> String {
    let count = map.selectedPaths.count
    guard count > 0 else { return "Nothing selected" }
    return
      "\(itemCountLine(UInt32(count))) selected, \(ByteFigure.string(map.selectedByteTotal))"
  }

  private func beginExecution() {
    if let scope = model.permanentDeletionScope() {
      confirmingScope = scope
      return
    }
    model.executeSelection(permanentConfirmation: nil)
  }

  private func performDrillIn(to path: AbsolutePath) {
    var drill: SpaceLensDrill?
    withAnimation(zoomAnimation(for: .zoomIn)) {
      drill = model.drillIn(to: path)
    }
    _ = drill
  }

  private func performDrillOut() {
    withAnimation(zoomAnimation(for: .zoomOut)) {
      _ = model.drillOut()
    }
  }

  /// The same zoom language as the hub: the drill direction resolves
  /// through HubZoomResolver, so full motion is the snappy matched geometry
  /// spring and Reduce Motion is a crossfade, never a spring.
  private func zoomAnimation(for direction: HubZoomDirection) -> Animation {
    switch HubZoomResolver.appearance(for: direction, reduceMotion: reduceMotion) {
    case .matchedGeometry(let spring):
      return spring.animation(reduceMotion: false)
    case .crossfade(let fade):
      return .easeInOut(duration: seconds(of: fade.duration))
    }
  }

  private func seconds(of duration: Duration) -> Double {
    Double(duration.components.seconds)
      + Double(duration.components.attoseconds) / 1e18
  }

  private var isConfirmingPermanent: Binding<Bool> {
    Binding(
      get: { confirmingScope != nil },
      set: { isPresented in
        if !isPresented { confirmingScope = nil }
      }
    )
  }

  private func itemCountLine(_ count: UInt32) -> String {
    count == 1 ? "1 item" : "\(count) items"
  }

  private var stateShape: SpaceLensStateShape {
    switch model.state {
    case .idle: return .idle
    case .mapping: return .mapping
    case .browsing: return .browsing
    case .executing: return .executing
    case .result: return .result
    }
  }
}

enum SpaceLensStateShape {
  case idle, mapping, browsing, executing, result
}

/// The designed entry state: what a map covers and the one action.
struct SpaceLensIdleView: View {
  let onMap: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: GleamSpacing.points(2)) {
      Spacer()
      Text("See where your space went")
        .font(GleamTypeToken.title.font)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text(
        "The map builds outward from the volume root while scanning, sized by what each folder actually takes on disk. Drill in, select what should go, and review before anything moves."
      )
      .font(GleamTypeToken.body.font)
      .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      .multilineTextAlignment(.center)
      .frame(maxWidth: 460)
      CleanupPrimaryButton(title: "Map This Mac", action: onMap)
        .padding(.top, GleamSpacing.points(1))
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}

/// Where the user is in the tree, with the way back and the live caption.
struct SpaceLensBreadcrumb: View {
  let map: SpaceLensMapState
  let isStreaming: Bool
  let onDrillOut: () -> Void
  let onCancel: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: GleamSpacing.points(1)) {
      if map.focusPath != map.volume {
        Button(action: onDrillOut) {
          Image(systemName: "chevron.left")
            .foregroundStyle(GleamColorToken.accent.color(for: colorScheme))
        }
        .buttonStyle(.plain)
      }
      Text(map.focusPath.value)
        .font(GleamTypeToken.mono.font)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer()
      if isStreaming {
        Text("Mapping\u{2026}")
          .font(GleamTypeToken.caption.font)
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        Button("Cancel") { onCancel() }
          .buttonStyle(.plain)
          .font(GleamTypeToken.caption.font)
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      }
    }
  }
}

/// The focused folder's children as size proportional blocks: each block's
/// height follows its share of the focused subtree, so the map reads as
/// weight at a glance and grows as the stream revises totals upward.
struct SpaceLensMapCanvas: View {
  let map: SpaceLensMapState
  let onToggle: (AbsolutePath) -> Void
  let onDrillIn: (AbsolutePath) -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let minimumRowHeight: CGFloat = 44

  var body: some View {
    let focused = focusedNode
    ScrollView {
      VStack(spacing: GleamSpacing.points(1) / 2) {
        if let focused, !focused.children.isEmpty {
          ForEach(focused.children) { child in
            SpaceLensBlockRow(
              node: child,
              share: share(of: child, in: focused),
              isSelected: map.selectedPaths.contains(child.path),
              onToggle: { onToggle(child.path) },
              onDrillIn: { onDrillIn(child.path) }
            )
            .frame(height: rowHeight(for: child, in: focused))
          }
        } else {
          Text(focused == nil ? "Waiting for the first folders\u{2026}" : "Nothing inside yet")
            .font(GleamTypeToken.body.font)
            .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
            .frame(maxWidth: .infinity)
            .padding(GleamSpacing.points(4))
        }
      }
      .animation(GleamSpring.gentle.animation(reduceMotion: reduceMotion), value: rowShape)
    }
  }

  private var focusedNode: SpaceLensTreeNode? {
    guard let root = map.root else { return nil }
    var stack = [root]
    while let node = stack.popLast() {
      if node.path == map.focusPath { return node }
      stack.append(contentsOf: node.children)
    }
    return nil
  }

  private func share(of child: SpaceLensTreeNode, in focused: SpaceLensTreeNode) -> Double {
    let total = focused.children.reduce(UInt64(0)) { $0 + $1.allocatedBytesSoFar }
    guard total > 0 else { return 0 }
    return Double(child.allocatedBytesSoFar) / Double(total)
  }

  /// Proportional heights over a 480 point canvas, clamped so a sliver of a
  /// folder still offers a full tap target.
  private func rowHeight(for child: SpaceLensTreeNode, in focused: SpaceLensTreeNode) -> CGFloat {
    max(Self.minimumRowHeight, 480 * share(of: child, in: focused))
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

/// One block of the map: selection on the left, the name and figure, and
/// the way in for folders.
struct SpaceLensBlockRow: View {
  let node: SpaceLensTreeNode
  let share: Double
  let isSelected: Bool
  let onToggle: () -> Void
  let onDrillIn: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .font(GleamTypeToken.body.font)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer()
      Text(ByteFigure.string(node.allocatedBytesSoFar))
        .font(GleamTypeToken.caption.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
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
      }
    }
    .padding(.horizontal, GleamSpacing.points(2))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: GleamRadius.control.value)
        .fill(
          GleamColorToken.accent.color(for: colorScheme)
            .opacity(0.08 + 0.24 * share)
        )
    )
    .overlay(
      RoundedRectangle(cornerRadius: GleamRadius.control.value)
        .strokeBorder(
          isSelected
            ? GleamColorToken.accent.color(for: colorScheme)
            : Color.clear,
          lineWidth: 2
        )
    )
    .contentShape(Rectangle())
    .onTapGesture(count: 2) {
      if node.isDirectory { onDrillIn() }
    }
  }
}

/// Execution progress: the count ticking through the plan and the reclaimed
/// figure, with the one cancel that lands between items.
struct SpaceLensExecutionView: View {
  let progress: SpaceLensExecutionProgress
  let onCancel: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: GleamSpacing.points(2)) {
      Spacer()
      Text("Removing\u{2026}")
        .font(GleamTypeToken.title.font)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      ProgressView(
        value: Double(progress.finishedOperations),
        total: Double(max(progress.totalOperations, 1))
      )
      .frame(maxWidth: 320)
      Text("\(progress.finishedOperations) of \(progress.totalOperations) items")
        .font(GleamTypeToken.body.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      Text("\(ByteFigure.string(progress.bytesReclaimed)) reclaimed")
        .font(GleamTypeToken.body.font.weight(.semibold))
        .foregroundStyle(GleamColorToken.accent.color(for: colorScheme))
        .contentTransition(.numericText())
        .animation(
          GleamSpring.snappy.animation(reduceMotion: reduceMotion),
          value: progress.bytesReclaimed
        )
      Button("Cancel") { onCancel() }
        .buttonStyle(.plain)
        .font(GleamTypeToken.caption.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}

/// The result screen: the report's exact account, which says which is which.
struct SpaceLensResultView: View {
  let summary: SpaceLensResultSummary
  let onDone: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: GleamSpacing.points(2)) {
      Spacer()
      Text("\(ByteFigure.string(summary.bytesReclaimed)) reclaimed")
        .font(GleamTypeToken.title.font)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text(outcomeLine)
        .font(GleamTypeToken.body.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      if !summary.failures.isEmpty {
        CleanupNoticeCard(
          sentences: summary.failures,
          tint: GleamColorToken.review.color(for: colorScheme)
        )
        .frame(maxWidth: 460)
      }
      if !summary.skippedDenylistedNames.isEmpty {
        CleanupNoticeCard(
          sentences: [skippedLine],
          tint: GleamColorToken.safe.color(for: colorScheme)
        )
        .frame(maxWidth: 460)
      }
      CleanupPrimaryButton(title: "Done", action: onDone)
        .padding(.top, GleamSpacing.points(1))
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private var outcomeLine: String {
    var parts = ["\(summary.completedCount) removed"]
    if summary.failedCount > 0 { parts.append("\(summary.failedCount) failed") }
    if summary.notStartedCount > 0 { parts.append("\(summary.notStartedCount) not started") }
    return parts.joined(separator: ", ")
  }

  private var skippedLine: String {
    "The safety denylist kept \(summary.skippedDenylistedNames.joined(separator: ", ")) in place."
  }
}
