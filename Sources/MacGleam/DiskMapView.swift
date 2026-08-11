import DiskMapModule
import GleamCore
import GleamDesign
import GleamHub
import SwiftUI

/// The Disk Map surface: one thin view over DiskMapModuleModel, adding
/// no state of its own beyond presentation. The streaming map renders as
/// size proportional blocks that grow as totals converge; drilling into a
/// folder resolves through HubZoomResolver so the whole app keeps one
/// navigation language; selection, review and execution follow the Cleanup
/// flow, and every motion comes from the token set with Reduce Motion
/// fallbacks.
struct DiskMapView: View {
  let model: DiskMapModuleModel
  let executor: CancellableCleanupExecutor
  /// The standard pane this destination shows before a map exists. Every
  /// destination opens on the same shape.
  let idlePane: ModulePane
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var confirmingScope: PermanentDeletionScope?

  /// The volume a map opens on. The shell starts a map from the same value
  /// when the return key asks for one, so the key and the button map the
  /// same disk.
  static let defaultVolume = AbsolutePath(normalising: "/")

  var body: some View {
    Group {
      if isIdle && model.failureNotice == nil {
        ModulePaneView(
          pane: idlePane,
          onActivate: { model.startMapping(volume: Self.defaultVolume) }
        )
      } else {
        working
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

  private var isIdle: Bool {
    if case .idle = model.state { return true }
    return false
  }

  private var working: some View {
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
    .padding(.horizontal, GleamSpacing.points(6))
    .padding(.vertical, GleamSpacing.points(5))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// The rail is how you leave, so the heading carries no close control.
  private var header: some View {
    Text("Disk Map")
      .gleamType(.heading)
      .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .idle:
      DiskMapIdleInvitation(onMap: { model.startMapping(volume: Self.defaultVolume) })
    case .mapping(let map):
      mapScene(map, isStreaming: true)
    case .browsing(let map):
      mapScene(map, isStreaming: false)
    case .executing(let progress):
      DiskMapExecutionView(
        progress: progress,
        onCancel: {
          model.cancelExecution()
          executor.requestCancellation()
        }
      )
    case .result(let summary):
      DiskMapResultView(summary: summary, onDone: { model.acknowledgeResult() })
    }
  }

  private func mapScene(_ map: DiskMapState, isStreaming: Bool) -> some View {
    VStack(spacing: GleamSpacing.points(2)) {
      DiskMapBreadcrumb(
        map: map,
        isStreaming: isStreaming,
        onDrillOut: { performDrillOut() },
        onCancel: { model.cancelMapping() }
      )
      DiskMapCanvas(
        map: map,
        onToggle: { model.toggleSelection($0) },
        onDrillIn: { performDrillIn(to: $0) }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      footer(map, isStreaming: isStreaming)
    }
  }

  private func footer(_ map: DiskMapState, isStreaming: Bool) -> some View {
    HStack {
      Text(selectionLine(map))
        .gleamType(.body)
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
          .gleamType(.caption)
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      }
      PrimaryButton(
        title: "Remove",
        action: beginExecution,
        isEnabled: !isStreaming && !map.selectedPaths.isEmpty
      )
    }
  }

  private func selectionLine(_ map: DiskMapState) -> String {
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
    var drill: DiskMapDrill?
    withAnimation(DiskMapZoom.animation(for: .zoomIn, reduceMotion: reduceMotion)) {
      drill = model.drillIn(to: path)
    }
    _ = drill
  }

  private func performDrillOut() {
    withAnimation(DiskMapZoom.animation(for: .zoomOut, reduceMotion: reduceMotion)) {
      _ = model.drillOut()
    }
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

  private var stateShape: DiskMapStateShape {
    switch model.state {
    case .idle: return .idle
    case .mapping: return .mapping
    case .browsing: return .browsing
    case .executing: return .executing
    case .result: return .result
    }
  }
}

enum DiskMapStateShape {
  case idle, mapping, browsing, executing, result
}

/// The designed entry state: what a map covers and the one action.
struct DiskMapIdleInvitation: View {
  let onMap: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: GleamSpacing.points(2)) {
      Spacer()
      Text("See where your space went")
        .gleamType(.title)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text(
        "The map builds outward from the volume root while scanning, sized by what each folder actually takes on disk. Drill in, select what should go, and review before anything moves."
      )
      .gleamType(.body)
      .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      .multilineTextAlignment(.center)
      .frame(maxWidth: 460)
      PrimaryButton(title: "Map This Mac", action: onMap)
        .padding(.top, GleamSpacing.points(1))
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}

/// Where the user is in the tree, with the way back and the live caption.
struct DiskMapBreadcrumb: View {
  let map: DiskMapState
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
        .gleamType(.mono)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer()
      if isStreaming {
        Text("Mapping\u{2026}")
          .gleamType(.caption)
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        Button("Cancel") { onCancel() }
          .buttonStyle(.plain)
          .gleamType(.caption)
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      }
    }
  }
}

/// Execution progress: the count ticking through the plan and the reclaimed
/// figure, with the one cancel that lands between items.
struct DiskMapExecutionView: View {
  let progress: DiskMapExecutionProgress
  let onCancel: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: GleamSpacing.points(2)) {
      Spacer()
      Text("Removing\u{2026}")
        .gleamType(.title)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      ProgressView(
        value: Double(progress.finishedOperations),
        total: Double(max(progress.totalOperations, 1))
      )
      .frame(maxWidth: 320)
      Text("\(progress.finishedOperations) of \(progress.totalOperations) items")
        .gleamType(.body)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      Text("\(ByteFigure.string(progress.bytesReclaimed)) reclaimed")
        .gleamType(.body)
        .fontWeight(.semibold)
        .foregroundStyle(GleamColorToken.accent.color(for: colorScheme))
        .contentTransition(.numericText())
        .animation(
          GleamSpring.snappy.animation(reduceMotion: reduceMotion),
          value: progress.bytesReclaimed
        )
      Button("Cancel") { onCancel() }
        .buttonStyle(.plain)
        .gleamType(.caption)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}

/// The result screen: the report's exact account, which says which is which.
struct DiskMapResultView: View {
  let summary: DiskMapResultSummary
  let onDone: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: GleamSpacing.points(2)) {
      Spacer()
      Text("\(ByteFigure.string(summary.bytesReclaimed)) reclaimed")
        .gleamType(.title)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text(outcomeLine)
        .gleamType(.body)
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
      PrimaryButton(title: "Done", action: onDone)
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
