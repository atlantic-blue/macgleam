import GleamCore
import GleamDesign
import ProtectionModule
import SwiftUI

/// The scan, while it runs. It says what it is reading rather than showing a
/// bar with no content: a protection scan takes a while and silence during it
/// reads as a hang.
struct ProtectionScanningView: View {
  let progress: ProtectionScanProgress
  let onCancel: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(2)) {
      Text("Checking this Mac")
        .gleamType(.body)
        .fontWeight(.semibold)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text("\(progress.counters.filesSeen) files read so far.")
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
}

/// The review: threats above, traces below, and one action.
struct ProtectionReviewView: View {
  let review: ProtectionReviewState
  let onToggle: (UUID) -> Void
  let onRun: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: GleamSpacing.points(2)) {
      ScrollView {
        VStack(alignment: .leading, spacing: GleamSpacing.points(2)) {
          if !review.threats.isEmpty {
            section(
              "Threats",
              note: "Removing these holds them in the SafetyNet, where they cannot run and "
                + "can be put back for thirty days.",
              findings: review.threats)
          }
          if !review.traces.isEmpty {
            section(
              "Traces",
              note: "These are cleared rather than held. Nothing here is ticked for you.",
              findings: review.traces)
          }
        }
      }
      footer
    }
  }

  private func section(_ title: String, note: String, findings: [Finding]) -> some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(1)) {
      Text(title)
        .gleamType(.body)
        .fontWeight(.semibold)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text(note)
        .gleamType(.caption)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      ForEach(findings, id: \.id) { finding in
        row(finding)
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
          Text(title(of: finding))
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
        if let path = finding.paths.first {
          Text(path.value)
            .gleamType(.mono)
            .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme).opacity(0.7))
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    }
    .padding(GleamSpacing.points(1))
  }

  private var footer: some View {
    HStack {
      Text(selectionLine)
        .gleamType(.body)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      Spacer()
      PrimaryButton(
        title: "Remove",
        action: onRun,
        isEnabled: !review.selectedFindingIDs.isEmpty)
    }
  }

  private var selectionLine: String {
    let count = review.selectedFindingIDs.count
    guard count > 0 else { return "Nothing selected" }
    return "\(count) selected, \(ByteFigure.string(review.selectedByteTotal))"
  }

  /// What the row is called: the signature for malware, the browser and the
  /// kind for a trace, and the file's own name otherwise.
  private func title(of finding: Finding) -> String {
    switch finding.category {
    case .malware(let signature): return signature
    case .adwareLaunchItem: return "Launch item"
    case .suspiciousBrowserExtension: return "Browser extension"
    case .unwantedAppPath: return "Unwanted application"
    case .browserHistory(let browser): return "\(browser) history"
    case .browserCookies(let browser): return "\(browser) cookies"
    case .browserSiteData(let browser): return "\(browser) site data"
    case .recentItemsList: return "Recent items"
    case .wifiNetworkHistory: return "Wireless networks"
    default: return finding.paths.first?.lastComponent ?? ""
    }
  }
}

struct ProtectionExecutingView: View {
  let progress: ProtectionExecutionProgress
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(1)) {
      Text("Removing")
        .gleamType(.body)
        .fontWeight(.semibold)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text("\(progress.finishedOperations) of \(progress.totalOperations) done.")
        .gleamType(.caption)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .contentTransition(.numericText())
      Spacer()
    }
  }
}

/// The result, with contained and cleared counted apart, because one of them
/// can be undone and the other cannot.
struct ProtectionResultView: View {
  let summary: ProtectionResultSummary
  let onDone: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(2)) {
      Text(headline)
        .gleamType(.heading)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      if summary.containedCount > 0 {
        Text(
          "What was held is in the SafetyNet for thirty days, where it cannot run and can be "
            + "put back."
        )
        .gleamType(.caption)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      }
      if !summary.skippedDenylistedNames.isEmpty {
        CleanupNoticeCard(
          sentences: [
            "Protected by MacGleam and left alone: "
              + summary.skippedDenylistedNames.joined(separator: ", ") + "."
          ],
          tint: GleamColorToken.review.color(for: colorScheme))
      }
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

  private var headline: String {
    switch (summary.containedCount, summary.clearedCount) {
    case (0, 0): return "Nothing was removed"
    case (let held, 0): return "\(held) held in the SafetyNet"
    case (0, let cleared): return "\(cleared) cleared"
    case (let held, let cleared): return "\(held) held, \(cleared) cleared"
    }
  }
}

/// The empty result as a reward rather than a blank panel.
struct ProtectionAllClearView: View {
  let filesChecked: UInt64
  let onDone: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(1)) {
      Text("Nothing to worry about")
        .gleamType(.heading)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text(
        "\(filesChecked) files read, and none of them matches anything MacGleam knows to be "
          + "unwanted."
      )
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

/// What MacGleam is holding, and the one click that puts a row back.
struct SafetyNetSection: View {
  let model: SafetyNetModel
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(1)) {
      Text("The SafetyNet")
        .gleamType(.body)
        .fontWeight(.semibold)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      if model.items.isEmpty {
        Text("Nothing is being held. Anything MacGleam removes goes here first.")
          .gleamType(.caption)
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: GleamSpacing.points(1)) {
            ForEach(model.items, id: \.id) { item in
              row(item)
            }
          }
        }
      }
      if let notice = model.notice {
        CleanupNoticeCard(
          sentences: [notice], tint: GleamColorToken.review.color(for: colorScheme))
      }
      Spacer()
    }
  }

  private func row(_ item: SafetyNetItem) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: GleamSpacing.points(1)) {
      VStack(alignment: .leading, spacing: 2) {
        Text(item.originPath.lastComponent)
          .gleamType(.body)
          .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
        Text(item.originPath.value)
          .gleamType(.mono)
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme).opacity(0.7))
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer()
      Text(ByteFigure.string(item.allocatedBytes))
        .gleamType(.caption)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      Button("Put back") {
        Task { await model.restore(itemID: item.id) }
      }
      .buttonStyle(.plain)
      .gleamType(.caption)
      .foregroundStyle(GleamColorToken.accent.color(for: colorScheme))
    }
    .padding(GleamSpacing.points(1))
  }
}
