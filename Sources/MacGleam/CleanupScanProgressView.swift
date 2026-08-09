import CleanupModule
import GleamCore
import GleamDesign
import SwiftUI

/// The three phase scan choreography: an indeterminate sweep, determinate
/// progress with live counters, then a settle where the counters resolve
/// with the gentle spring. Counters only ever count up, which the model
/// guarantees; the view adds the numeric text transition on top. Under
/// Reduce Motion the sweep becomes a plain indeterminate bar.
struct CleanupScanProgressView: View {
  let progress: CleanupScanProgress
  let onCancel: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isConfirmingCancel = false

  var body: some View {
    VStack(spacing: GleamSpacing.points(3)) {
      Spacer()
      phaseBar
        .frame(maxWidth: 420)
      counters
      Button("Stop Scan") { isConfirmingCancel = true }
        .buttonStyle(.plain)
        .font(GleamTypeToken.caption.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      Spacer()
    }
    .frame(maxWidth: .infinity)
    .confirmationDialog(
      "Stop this scan?",
      isPresented: $isConfirmingCancel
    ) {
      Button("Stop Scan", role: .destructive, action: onCancel)
      Button("Keep Scanning", role: .cancel) {}
    } message: {
      Text("Scanning is read only, so stopping loses nothing but the findings so far.")
    }
  }

  @ViewBuilder
  private var phaseBar: some View {
    switch progress.phase {
    case .indeterminate:
      if reduceMotion {
        ProgressView()
          .progressViewStyle(.linear)
          .tint(GleamColorToken.accent.color(for: colorScheme))
      } else {
        CleanupSweepBar()
      }
    case .determinate(let estimatedTotalFiles):
      ProgressView(value: determinateFraction(estimatedTotalFiles: estimatedTotalFiles))
        .progressViewStyle(.linear)
        .tint(GleamColorToken.accent.color(for: colorScheme))
        .animation(
          GleamSpring.gentle.animation(reduceMotion: reduceMotion),
          value: progress.counters.filesSeen
        )
    case .settling:
      ProgressView(value: 1)
        .progressViewStyle(.linear)
        .tint(GleamColorToken.accent.color(for: colorScheme))
        .animation(GleamSpring.gentle.animation(reduceMotion: reduceMotion), value: 1)
    }
  }

  private var counters: some View {
    VStack(spacing: GleamSpacing.points(1) / 2) {
      Text(ByteFigure.string(progress.counters.bytesReclaimable))
        .font(GleamTypeToken.display.font)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
        .contentTransition(.numericText())
        .animation(
          GleamSpring.gentle.animation(reduceMotion: reduceMotion),
          value: progress.counters.bytesReclaimable
        )
      Text(counterLine)
        .font(GleamTypeToken.caption.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .contentTransition(.numericText())
        .animation(
          GleamSpring.gentle.animation(reduceMotion: reduceMotion),
          value: progress.counters.filesSeen
        )
    }
  }

  private var counterLine: String {
    let files = progress.counters.filesSeen
    let findings = progress.counters.findingCount
    let filesPart = files == 1 ? "1 file seen" : "\(files) files seen"
    guard findings > 0 else { return filesPart }
    let findingsPart = findings == 1 ? "1 finding" : "\(findings) findings"
    return "\(filesPart), \(findingsPart)"
  }

  private func determinateFraction(estimatedTotalFiles: UInt64) -> Double {
    guard estimatedTotalFiles > 0 else { return 0 }
    return min(Double(progress.counters.filesSeen) / Double(estimatedTotalFiles), 1)
  }
}

/// The indeterminate sweep: an accent highlight orbiting a quiet track.
struct CleanupSweepBar: View {
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    TimelineView(.animation) { context in
      let phase =
        context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
      GeometryReader { geometry in
        let width = geometry.size.width
        let sweepWidth = width * 0.3
        Capsule()
          .fill(GleamColorToken.accent.color(for: colorScheme).opacity(0.15))
        Capsule()
          .fill(GleamColorToken.accent.color(for: colorScheme))
          .frame(width: sweepWidth)
          .offset(x: (width + sweepWidth) * phase - sweepWidth)
          .clipShape(Capsule())
      }
    }
    .frame(height: 4)
    .clipShape(Capsule())
  }
}
