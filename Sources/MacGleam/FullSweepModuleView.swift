import FullSweepModule
import GleamCore
import GleamDesign
import GleamHub
import SwiftUI

/// Smart Care: one button, one combined answer.
///
/// The whole point of this screen is that it asks nothing. A sweep starts what
/// three modules would each have started, keeps exactly what each of them
/// chose to offer, and shows one figure. Every row is still there to untick,
/// because a sweep narrows what it does and never widens it.
struct FullSweepModuleView: View {
  let model: FullSweepModuleModel
  let idlePane: ModulePane
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Group {
      if case .idle = model.state, model.failureNotice == nil {
        ModulePaneView(pane: idlePane, onActivate: { model.startSweep() })
      } else {
        working
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(GleamSpring.gentle.animation(reduceMotion: reduceMotion), value: shape)
  }

  private var working: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(2)) {
      Text("Full Sweep")
        .gleamType(.heading)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      if let failure = model.failureNotice {
        CleanupNoticeCard(
          sentences: [failure], tint: GleamColorToken.review.color(for: colorScheme))
      }
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(.horizontal, GleamSpacing.points(6))
    .padding(.vertical, GleamSpacing.points(5))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .idle:
      ModulePaneView(pane: idlePane, onActivate: { model.startSweep() })
    case .scanning(let progress):
      FullSweepScanningView(progress: progress, onCancel: { model.cancelSweep() })
    case .reviewing(let review):
      FullSweepReviewView(
        review: review,
        onToggle: { model.toggleFinding($0) },
        onRun: { model.run() })
    case .executing(let finished, let total):
      FullSweepRunningView(finished: finished, total: total)
    case .result(let summary):
      FullSweepResultView(summary: summary, onDone: { model.acknowledgeResult() })
    case .cleanSweep:
      FullSweepCleanView(onDone: { model.acknowledgeResult() })
    }
  }

  private var shape: Int {
    switch model.state {
    case .idle: return 0
    case .scanning: return 1
    case .reviewing: return 2
    case .executing: return 3
    case .result: return 4
    case .cleanSweep: return 5
    }
  }
}

struct FullSweepScanningView: View {
  let progress: FullSweepProgress
  let onCancel: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(1)) {
      Text("Checking your Mac")
        .gleamType(.body)
        .fontWeight(.semibold)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text(line)
        .gleamType(.caption)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .contentTransition(.numericText())
      Spacer()
      HStack {
        Spacer()
        Button("Stop", action: onCancel)
          .buttonStyle(.plain)
          .gleamType(.caption)
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      }
    }
  }

  private var line: String {
    guard progress.bytesReclaimable > 0 else { return "\(progress.filesSeen) files read." }
    return "\(ByteFigure.string(progress.bytesReclaimable)) so far, "
      + "\(progress.filesSeen) files read."
  }
}

/// The combined review, grouped by job. A job that could not run says so where
/// its rows would have been, rather than looking like a job that found
/// nothing.
struct FullSweepReviewView: View {
  let review: FullSweepReview
  let onToggle: (UUID) -> Void
  let onRun: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: GleamSpacing.points(2)) {
      ScrollView {
        VStack(alignment: .leading, spacing: GleamSpacing.points(2)) {
          ForEach(review.jobs) { job in
            section(job)
          }
        }
      }
      footer
    }
  }

  @ViewBuilder
  private func section(_ job: FullSweepJobFindings) -> some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(1)) {
      Text(job.job.title)
        .gleamType(.body)
        .fontWeight(.semibold)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      if let failure = job.failure {
        Text(failure)
          .gleamType(.caption)
          .foregroundStyle(GleamColorToken.review.color(for: colorScheme))
      } else if job.findings.isEmpty {
        Text("Nothing to do here.")
          .gleamType(.caption)
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      } else {
        ForEach(job.findings, id: \.id) { finding in
          row(finding)
        }
      }
    }
  }

  private func row(_ finding: Finding) -> some View {
    HStack(alignment: .top, spacing: GleamSpacing.points(1)) {
      CleanupCheckmark(
        isSelected: review.selectedFindingIDs.contains(finding.id),
        reduceMotion: reduceMotion,
        action: { onToggle(finding.id) })
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: GleamSpacing.points(1)) {
          CleanupRiskDot(risk: finding.risk)
          Text(finding.paths.first?.lastComponent ?? finding.explanation)
            .gleamType(.body)
            .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
          Spacer()
          Text(ByteFigure.string(finding.byteSize))
            .gleamType(.caption)
            .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        }
        Text(finding.explanation)
          .gleamType(.caption)
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      }
    }
    .padding(GleamSpacing.points(1))
  }

  private var footer: some View {
    HStack {
      Text(selectionLine)
        .gleamType(.body)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .contentTransition(.numericText())
      Spacer()
      PrimaryButton(
        title: "Run", action: onRun, isEnabled: !review.selectedFindingIDs.isEmpty)
    }
  }

  private var selectionLine: String {
    let count = review.selectedFindingIDs.count
    guard count > 0 else { return "Nothing selected" }
    return "\(count) selected, \(ByteFigure.string(review.selectedByteTotal))"
  }
}

struct FullSweepRunningView: View {
  let finished: UInt32
  let total: UInt32
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(1)) {
      Text("Working")
        .gleamType(.body)
        .fontWeight(.semibold)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text("\(finished) of \(total) done.")
        .gleamType(.caption)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .contentTransition(.numericText())
      Spacer()
    }
  }
}

struct FullSweepResultView: View {
  let summary: FullSweepRunSummary
  let onDone: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(2)) {
      Text(ByteFigure.string(summary.bytesReclaimed) + " reclaimed")
        .gleamType(.heading)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      if !summary.failures.isEmpty {
        CleanupNoticeCard(
          sentences: summary.failures,
          tint: GleamColorToken.review.color(for: colorScheme))
      }
      Spacer()
      HStack {
        Spacer()
        PrimaryButton(title: "Done", action: onDone, isEnabled: true)
      }
    }
  }
}

/// The empty answer as the good one. It is the reward state the orb blooms
/// for, so the screen behind it says the same thing rather than showing a list
/// with nothing in it.
struct FullSweepCleanView: View {
  let onDone: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(1)) {
      Text("Nothing to do")
        .gleamType(.heading)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text("Your Mac is in good shape. Nothing worth removing turned up.")
        .gleamType(.caption)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      Spacer()
      HStack {
        Spacer()
        PrimaryButton(title: "Done", action: onDone, isEnabled: true)
      }
    }
  }
}
