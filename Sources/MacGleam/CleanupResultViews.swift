import CleanupModule
import GleamCore
import GleamDesign
import SwiftUI

/// The execution scene: the reclaimed figure ticking up in real time while
/// the selected rows lift and fly toward it as operations complete. Failures
/// keep their place on the result screen with the review colour and their
/// sentence. Under Reduce Motion rows crossfade out instead of flying.
struct CleanupExecutionView: View {
  let progress: CleanupExecutionProgress
  let rows: [Finding]
  let onCancel: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: GleamSpacing.points(2)) {
      reclaimedFigure
      operationLine
      ScrollView {
        VStack(spacing: GleamSpacing.points(1)) {
          ForEach(Array(rows.enumerated()), id: \.element.id) { index, finding in
            executingRow(finding, isDone: index < doneRowCount)
          }
        }
        .padding(.vertical, GleamSpacing.points(1))
      }
      Button("Stop After This Item", action: onCancel)
        .buttonStyle(.plain)
        .font(GleamTypeToken.caption.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
    }
  }

  private var reclaimedFigure: some View {
    VStack(spacing: 2) {
      Text(ByteFigure.string(progress.bytesReclaimed))
        .font(GleamTypeToken.display.font)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
        .contentTransition(.numericText())
        .animation(
          GleamSpring.snappy.animation(reduceMotion: reduceMotion),
          value: progress.bytesReclaimed
        )
      Text("reclaimed")
        .font(GleamTypeToken.caption.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
    }
  }

  private var operationLine: some View {
    Text("\(progress.finishedOperations) of \(progress.totalOperations) operations")
      .font(GleamTypeToken.caption.font)
      .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      .contentTransition(.numericText())
      .animation(
        GleamSpring.gentle.animation(reduceMotion: reduceMotion),
        value: progress.finishedOperations
      )
  }

  private func executingRow(_ finding: Finding, isDone: Bool) -> some View {
    HStack {
      Text(
        finding.paths.count == 1 ? finding.paths[0].lastComponent : "\(finding.paths.count) files"
      )
      .font(GleamTypeToken.body.font)
      .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Spacer()
      Text(ByteFigure.string(finding.byteSize))
        .font(GleamTypeToken.caption.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
    }
    .padding(GleamSpacing.points(1))
    .background(
      RoundedRectangle(cornerRadius: GleamRadius.control.value)
        .fill(GleamColorToken.baseBackground.color(for: colorScheme).opacity(0.5))
    )
    .opacity(isDone ? 0 : 1)
    .offset(y: isDone && !reduceMotion ? -GleamSpacing.points(4) : 0)
    .scaleEffect(isDone && !reduceMotion ? 0.85 : 1)
    .animation(GleamSpring.gentle.animation(reduceMotion: reduceMotion), value: isDone)
  }

  /// How many rows read as flown: the finished fraction of the plan mapped
  /// onto the row count, so the list drains in step with the counter.
  private var doneRowCount: Int {
    guard progress.totalOperations > 0, !rows.isEmpty else { return 0 }
    let fraction = Double(progress.finishedOperations) / Double(progress.totalOperations)
    return Int((fraction * Double(rows.count)).rounded(.down))
  }
}

/// The result screen: the summary figure landing on the lively spring, per
/// category outcomes in review order, failures in place with the review
/// colour and their sentence, and denylist skips reported as the safety
/// system working.
struct CleanupResultView: View {
  let summary: CleanupResultSummary
  let onDone: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasLanded = false

  var body: some View {
    VStack(spacing: GleamSpacing.points(2)) {
      Spacer(minLength: GleamSpacing.points(2))
      figure
      ScrollView {
        VStack(alignment: .leading, spacing: GleamSpacing.points(1)) {
          ForEach(Array(summary.categoryOutcomes.enumerated()), id: \.offset) { _, outcome in
            outcomeRow(outcome)
          }
          failureRows
          skippedNote
        }
        .padding(.vertical, GleamSpacing.points(1))
      }
      .frame(maxWidth: 480)
      PrimaryButton(title: "Done", action: onDone)
      Spacer(minLength: GleamSpacing.points(2))
    }
    .frame(maxWidth: .infinity)
    .onAppear {
      withAnimation(GleamSpring.lively.animation(reduceMotion: reduceMotion)) {
        hasLanded = true
      }
    }
  }

  private var figure: some View {
    VStack(spacing: 2) {
      Text(ByteFigure.string(summary.bytesReclaimed))
        .font(GleamTypeToken.display.font)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text("reclaimed")
        .font(GleamTypeToken.body.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
    }
    .scaleEffect(hasLanded || reduceMotion ? 1 : 0.8)
    .opacity(hasLanded ? 1 : 0)
  }

  private func outcomeRow(_ outcome: CleanupCategoryOutcome) -> some View {
    HStack {
      Text(outcome.category.cleanupTitle)
        .font(GleamTypeToken.body.font)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Spacer()
      Text(outcomeLine(outcome))
        .font(GleamTypeToken.caption.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
    }
    .padding(.horizontal, GleamSpacing.points(1))
  }

  @ViewBuilder
  private var failureRows: some View {
    ForEach(summary.failures, id: \.self) { sentence in
      Text(sentence)
        .font(GleamTypeToken.caption.font)
        .foregroundStyle(GleamColorToken.review.color(for: colorScheme))
        .padding(.horizontal, GleamSpacing.points(1))
    }
  }

  @ViewBuilder
  private var skippedNote: some View {
    if !summary.skippedDenylistedNames.isEmpty {
      Text(
        "Left in place by the safety list: \(summary.skippedDenylistedNames.joined(separator: ", "))."
      )
      .font(GleamTypeToken.caption.font)
      .foregroundStyle(GleamColorToken.safe.color(for: colorScheme))
      .padding(.horizontal, GleamSpacing.points(1))
    }
  }

  private func outcomeLine(_ outcome: CleanupCategoryOutcome) -> String {
    var parts: [String] = []
    if outcome.completedCount > 0 {
      parts.append(
        "\(outcome.completedCount) removed, \(ByteFigure.string(outcome.bytesReclaimed))")
    }
    if outcome.failedCount > 0 { parts.append("\(outcome.failedCount) failed") }
    if outcome.skippedCount > 0 { parts.append("\(outcome.skippedCount) left in place") }
    if outcome.notStartedCount > 0 { parts.append("\(outcome.notStartedCount) not started") }
    guard !parts.isEmpty else { return "nothing to do" }
    return parts.joined(separator: ", ")
  }
}

/// The clean sweep reward: a calm lustre bloom around the accent, saying
/// exactly what was checked, never a blank panel.
struct CleanupCleanSweepView: View {
  let filesChecked: UInt64
  let onDone: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasBloomed = false

  var body: some View {
    VStack(spacing: GleamSpacing.points(2)) {
      Spacer()
      bloom
      Text("Nothing to clean")
        .font(GleamTypeToken.title.font)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text(checkedLine)
        .font(GleamTypeToken.body.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      PrimaryButton(title: "Done", action: onDone)
        .padding(.top, GleamSpacing.points(1))
      Spacer()
    }
    .frame(maxWidth: .infinity)
    .onAppear {
      withAnimation(GleamSpring.gentle.animation(reduceMotion: reduceMotion)) {
        hasBloomed = true
      }
    }
  }

  private var bloom: some View {
    let accent = GleamColorToken.accent.color(for: colorScheme)
    return ZStack {
      Circle()
        .fill(accent.opacity(0.12))
        .frame(width: 120, height: 120)
        .scaleEffect(hasBloomed || reduceMotion ? 1 : 0.6)
      Circle()
        .fill(accent.opacity(0.25))
        .frame(width: 76, height: 76)
        .scaleEffect(hasBloomed || reduceMotion ? 1 : 0.6)
      Image(systemName: "sparkles")
        .font(.system(size: 28))
        .foregroundStyle(accent)
    }
    .opacity(hasBloomed ? 1 : 0)
  }

  private var checkedLine: String {
    filesChecked == 1
      ? "Checked 1 file and found nothing to reclaim."
      : "Checked \(filesChecked) files and found nothing to reclaim."
  }
}
