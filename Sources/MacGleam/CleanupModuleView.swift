import CleanupModule
import GleamCore
import GleamDesign
import SwiftUI

/// The cleanup module surface: one thin view over CleanupModuleModel, adding
/// no state of its own beyond presentation (collapse, dialogs, the frozen
/// review rows the execution scene animates). All motion comes from the
/// token set, with Reduce Motion fallbacks throughout.
struct CleanupModuleView: View {
  let model: CleanupModuleModel
  let executor: CancellableCleanupExecutor
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var frozenReview: CleanupReviewState?

  var body: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(2)) {
      header
      notices
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
    .onChange(of: stateShape) { rememberReviewForExecution() }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("Cleanup")
        .font(GleamTypeToken.title.font)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Spacer()
      if model.hubEstimateBytes > 0 {
        Text(ByteFigure.string(model.hubEstimateBytes))
          .font(GleamTypeToken.body.font.weight(.semibold))
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
      CleanupIdleView(onScan: { model.startScan() })
    case .scanning(let progress):
      CleanupScanProgressView(progress: progress, onCancel: { model.cancelScan() })
    case .reviewing(let review):
      CleanupReviewView(review: review, model: model)
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
          .font(GleamTypeToken.caption.font)
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

/// The designed entry state: what a scan covers and the one action.
struct CleanupIdleView: View {
  let onScan: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: GleamSpacing.points(2)) {
      Spacer()
      Text("Reclaim space from system junk")
        .font(GleamTypeToken.title.font)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text(
        "Caches, logs, broken downloads, developer leftovers and every trash bin, itemised for your review before anything moves."
      )
      .font(GleamTypeToken.body.font)
      .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      .multilineTextAlignment(.center)
      .frame(maxWidth: 420)
      CleanupPrimaryButton(title: "Scan", action: onScan)
        .padding(.top, GleamSpacing.points(1))
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}

/// The one primary action style the module uses.
struct CleanupPrimaryButton: View {
  let title: String
  let action: () -> Void
  var isEnabled = true
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(GleamTypeToken.body.font.weight(.semibold))
        .foregroundStyle(GleamColorToken.baseBackground.color(for: colorScheme))
        .padding(.horizontal, GleamSpacing.points(3))
        .padding(.vertical, GleamSpacing.points(1))
        .background(
          Capsule().fill(
            GleamColorToken.accent.color(for: colorScheme).opacity(isEnabled ? 1 : 0.4)
          )
        )
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
  }
}
