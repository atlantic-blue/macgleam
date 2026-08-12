import GleamCore
import GleamDesign
import GleamHub
import ProtectionModule
import SwiftUI

/// The Protection surface: one thin view over the module model, adding no
/// state of its own beyond the confirmation dialog.
///
/// The review is two lists rather than one. Threats are things nobody chose to
/// have and they arrive ticked, because containment is reversible and leaving
/// malware running while somebody reads a list is the worse default. Traces
/// are things a person made, they arrive untouched, and clearing them is the
/// one permanent thing here, so it asks first with the exact numbers.
struct ProtectionModuleView: View {
  let model: ProtectionModuleModel
  let safetyNet: SafetyNetModel
  let idlePane: ModulePane
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var clearingScope: PermanentDeletionScope?

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
    .task { await safetyNet.reload() }
    .confirmationDialog(
      "Clear permanently?",
      isPresented: isConfirmingClear,
      presenting: clearingScope
    ) { scope in
      Button("Clear \(itemCountLine(scope.fileCount))", role: .destructive) {
        model.executeSelection(
          clearingConfirmation: PermanentDeletionConfirmation(
            fileCount: scope.fileCount,
            byteTotal: scope.byteTotal,
            confirmedAt: Date()))
      }
      Button("Cancel", role: .cancel) {}
    } message: { scope in
      Text(
        "This clears \(itemCountLine(scope.fileCount)) totalling \(ByteFigure.string(scope.byteTotal)). Traces are cleared rather than held, so they cannot be put back."
      )
    }
  }

  private var isIdle: Bool {
    if case .idle = model.state { return true }
    return false
  }

  private var working: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(2)) {
      Text("Protection")
        .gleamType(.heading)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      notices
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(.horizontal, GleamSpacing.points(6))
    .padding(.vertical, GleamSpacing.points(5))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private var notices: some View {
    if !model.degradedNotices.isEmpty {
      CleanupNoticeCard(
        sentences: model.degradedNotices,
        tint: GleamColorToken.review.color(for: colorScheme))
    }
    if let failure = model.failureNotice {
      CleanupNoticeCard(
        sentences: [failure], tint: GleamColorToken.review.color(for: colorScheme))
    }
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .idle:
      SafetyNetSection(model: safetyNet)
    case .scanning(let progress):
      ProtectionScanningView(progress: progress, onCancel: { model.cancelScan() })
    case .reviewing(let review):
      ProtectionReviewView(
        review: review,
        onToggle: { model.toggleFinding($0) },
        onRun: beginRun)
    case .executing(let progress):
      ProtectionExecutingView(progress: progress)
    case .result(let summary):
      ProtectionResultView(summary: summary, onDone: { model.acknowledgeResult() })
    case .allClear(let filesChecked):
      ProtectionAllClearView(
        filesChecked: filesChecked, onDone: { model.acknowledgeResult() })
    }
  }

  /// Threats alone run without a question, because containment is reversible.
  /// A selection holding a trace asks first, with the counts.
  private func beginRun() {
    if let scope = model.clearedScope() {
      clearingScope = scope
      return
    }
    model.executeSelection(clearingConfirmation: nil)
  }

  private var isConfirmingClear: Binding<Bool> {
    Binding(
      get: { clearingScope != nil },
      set: { isPresented in
        if !isPresented { clearingScope = nil }
      })
  }

  private func itemCountLine(_ count: UInt32) -> String {
    count == 1 ? "1 item" : "\(count) items"
  }

  private var stateShape: ProtectionStateShape {
    switch model.state {
    case .idle: return .idle
    case .scanning: return .scanning
    case .reviewing: return .reviewing
    case .executing: return .executing
    case .result: return .result
    case .allClear: return .allClear
    }
  }
}

enum ProtectionStateShape {
  case idle, scanning, reviewing, executing, result, allClear
}
