import CleanupModule
import GleamCore
import GleamDesign
import GleamHub
import SwiftUI

/// The cleanup module surface: one thin view over CleanupModuleModel, adding
/// no state of its own beyond presentation (collapse, dialogs, the frozen
/// review rows the execution scene animates). All motion comes from the
/// token set, with Reduce Motion fallbacks throughout.
struct CleanupModuleView: View {
  let model: CleanupModuleModel
  let executor: CancellableCleanupExecutor
  /// The folds the review list shows, kept outside the view so the rail
  /// cannot destroy them on the way past.
  let presentation: CleanupPresentation
  /// The standard pane this module shows before any work starts. Every
  /// module opens on the same shape; the module's own screens take over once
  /// a scan is running.
  let idlePane: ModulePane
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var frozenReview: CleanupReviewState?

  var body: some View {
    Group {
      if isIdle && model.degradedNotices.isEmpty && model.failureNotice == nil {
        ModulePaneView(pane: idlePane, onActivate: { model.startScan() })
      } else {
        working
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(GleamSpring.gentle.animation(reduceMotion: reduceMotion), value: stateShape)
    .onChange(of: stateShape) { rememberReviewForExecution() }
  }

  private var isIdle: Bool {
    if case .idle = model.state { return true }
    return false
  }

  private var working: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(2)) {
      header
      notices
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(.horizontal, GleamSpacing.points(6))
    .padding(.vertical, GleamSpacing.points(5))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("Cleanup")
        .gleamType(.heading)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Spacer()
      if model.hubEstimateBytes > 0 {
        Text(ByteFigure.string(model.hubEstimateBytes))
          .gleamType(.body)
          .fontWeight(.semibold)
          .foregroundStyle(GleamColorToken.accent.color(for: colorScheme))
          .contentTransition(.numericText())
          .animation(
            GleamSpring.snappy.animation(reduceMotion: reduceMotion),
            value: model.hubEstimateBytes
          )
      }
    }
  }

  @ViewBuilder
  private var notices: some View {
    if !model.degradedNotices.isEmpty {
      CleanupNoticeCard(
        sentences: model.degradedNotices,
        tint: GleamColorToken.review.color(for: colorScheme)
      )
    }
    if let failure = model.failureNotice {
      CleanupNoticeCard(
        sentences: [failure],
        tint: GleamColorToken.review.color(for: colorScheme)
      )
    }
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .idle:
      CleanupIdleInvitation(onScan: { model.startScan() })
    case .scanning(let progress):
      CleanupScanProgressView(progress: progress, onCancel: { model.cancelScan() })
    case .reviewing(let review):
      CleanupReviewView(review: review, model: model, presentation: presentation)
    case .executing(let progress):
      CleanupExecutionView(
        progress: progress,
        rows: frozenReview?.selectedRows ?? [],
        onCancel: {
          model.cancelExecution()
          executor.requestCancellation()
        }
      )
    case .result(let summary):
      CleanupResultView(summary: summary, onDone: { model.acknowledgeResult() })
    case .cleanSweep(let filesChecked):
      CleanupCleanSweepView(filesChecked: filesChecked, onDone: { model.acknowledgeResult() })
    }
  }

  /// The lifecycle shape only, so scene transitions animate once per state
  /// change rather than on every counter tick.
  private var stateShape: CleanupStateShape {
    switch model.state {
    case .idle: return .idle
    case .scanning: return .scanning
    case .reviewing: return .reviewing
    case .executing: return .executing
    case .result: return .result
    case .cleanSweep: return .cleanSweep
    }
  }

  /// Freezes the review rows the moment execution begins, so the execution
  /// scene has rows to lift and fly while the model's state is progress only.
  private func rememberReviewForExecution() {
    if case .reviewing(let review) = model.state {
      frozenReview = review
    }
  }
}

enum CleanupStateShape {
  case idle, scanning, reviewing, executing, result, cleanSweep
}

extension CleanupReviewState {
  /// The selected findings in review order: the order execution follows.
  var selectedRows: [Finding] {
    categories.flatMap(\.findings).filter { selectedFindingIDs.contains($0.id) }
  }
}

/// An inline notice card: plain sentences, one per line, never a modal wall.
struct CleanupNoticeCard: View {
  let sentences: [String]
  let tint: Color
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(1) / 2) {
      ForEach(sentences, id: \.self) { sentence in
        Text(sentence)
          .gleamType(.caption)
          .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      }
    }
    .padding(GleamSpacing.points(2))
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: GleamRadius.control.value)
        .fill(tint.opacity(0.12))
    )
    .overlay(
      RoundedRectangle(cornerRadius: GleamRadius.control.value)
        .strokeBorder(tint.opacity(0.4), lineWidth: 1)
    )
  }
}

/// The entry state as it appears under a degraded or failure notice, where
/// the standard pane would push the notice off the top of the screen.
struct CleanupIdleInvitation: View {
  let onScan: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: GleamSpacing.points(2)) {
      Spacer()
      Text("Reclaim space from system junk")
        .gleamType(.title)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text(
        "Caches, logs, broken downloads, developer leftovers and every trash bin, itemised for your review before anything moves."
      )
      .gleamType(.body)
      .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      .multilineTextAlignment(.center)
      .frame(maxWidth: 420)
      PrimaryButton(title: "Scan", action: onScan)
        .padding(.top, GleamSpacing.points(1))
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}
