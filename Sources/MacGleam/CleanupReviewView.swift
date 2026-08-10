import CleanupModule
import GleamCore
import GleamDesign
import SwiftUI

/// The review list: findings stream in grouped by category with a staggered
/// entrance, selection checkmarks land on the snappy spring, and collapsing
/// a category is a layout animation, never a jump cut. The footer carries
/// the exact selected figure and the one action; a permanent scope routes
/// through the confirmation naming its exact counts.
struct CleanupReviewView: View {
  let review: CleanupReviewState
  let model: CleanupModuleModel
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var collapsedCategories: Set<FindingCategory> = []
  @State private var confirmingScope: PermanentDeletionScope?

  var body: some View {
    VStack(spacing: GleamSpacing.points(2)) {
      ScrollView {
        VStack(spacing: GleamSpacing.points(2)) {
          ForEach(Array(review.categories.enumerated()), id: \.element.id) { index, group in
            CleanupStaggeredAppearance(index: index, reduceMotion: reduceMotion) {
              categorySection(group)
            }
          }
        }
        .padding(.vertical, GleamSpacing.points(1))
      }
      footer
    }
    .confirmationDialog(
      "Delete permanently?",
      isPresented: isConfirmingPermanent,
      presenting: confirmingScope
    ) { scope in
      Button("Delete \(fileCountLine(scope.fileCount)) Permanently", role: .destructive) {
        execute(confirming: scope)
      }
      Button("Cancel", role: .cancel) {}
    } message: { scope in
      Text(
        "This permanently deletes \(fileCountLine(scope.fileCount)) totalling \(ByteFigure.string(scope.byteTotal)). Permanent deletions cannot be undone."
      )
    }
  }

  // MARK: - Category sections

  private func categorySection(_ group: CleanupReviewCategory) -> some View {
    let isCollapsed = collapsedCategories.contains(group.category)
    return VStack(spacing: 0) {
      categoryHeader(group, isCollapsed: isCollapsed)
      if !isCollapsed {
        ForEach(Array(group.findings.enumerated()), id: \.element.id) { index, finding in
          CleanupStaggeredAppearance(index: index, reduceMotion: reduceMotion) {
            findingRow(finding)
          }
        }
      }
    }
    .background(
      RoundedRectangle(cornerRadius: GleamRadius.control.value)
        .fill(GleamColorToken.baseBackground.color(for: colorScheme).opacity(0.5))
    )
  }

  private func categoryHeader(_ group: CleanupReviewCategory, isCollapsed: Bool) -> some View {
    HStack(spacing: GleamSpacing.points(1)) {
      CleanupCheckmark(
        isSelected: isCategoryFullySelected(group),
        reduceMotion: reduceMotion,
        action: { model.toggleCategory(group.category) }
      )
      Text(group.category.cleanupTitle)
        .font(GleamTypeToken.body.font.weight(.semibold))
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Spacer()
      Text(ByteFigure.string(group.findings.reduce(0) { $0 + $1.byteSize }))
        .font(GleamTypeToken.caption.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      Button {
        withAnimation(GleamSpring.gentle.animation(reduceMotion: reduceMotion)) {
          toggleCollapse(group.category)
        }
      } label: {
        Image(systemName: "chevron.down")
          .rotationEffect(.degrees(isCollapsed ? -90 : 0))
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      }
      .buttonStyle(.plain)
    }
    .padding(GleamSpacing.points(1))
  }

  private func findingRow(_ finding: Finding) -> some View {
    let isSelected = review.selectedFindingIDs.contains(finding.id)
    return HStack(alignment: .top, spacing: GleamSpacing.points(1)) {
      CleanupCheckmark(
        isSelected: isSelected,
        reduceMotion: reduceMotion,
        action: { model.toggleFinding(finding.id) }
      )
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: GleamSpacing.points(1)) {
          CleanupRiskDot(risk: finding.risk)
          Text(rowTitle(finding))
            .font(GleamTypeToken.body.font)
            .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
          Spacer()
          Text(ByteFigure.string(finding.byteSize))
            .font(GleamTypeToken.caption.font)
            .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        }
        Text(finding.explanation)
          .font(GleamTypeToken.caption.font)
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        if let path = finding.paths.first {
          Text(path.value)
            .font(GleamTypeToken.mono.font)
            .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme).opacity(0.7))
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    }
    .padding(GleamSpacing.points(1))
  }

  // MARK: - Footer

  private var footer: some View {
    HStack {
      Text(selectionLine)
        .font(GleamTypeToken.body.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .contentTransition(.numericText())
        .animation(
          GleamSpring.snappy.animation(reduceMotion: reduceMotion),
          value: review.selectedByteTotal
        )
      Spacer()
      Button("Rescan") { model.startScan() }
        .buttonStyle(.plain)
        .font(GleamTypeToken.caption.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      PrimaryButton(
        title: "Clean",
        action: beginExecution,
        isEnabled: !review.selectedFindingIDs.isEmpty
      )
    }
  }

  private var selectionLine: String {
    let count = review.selectedFileCount
    guard count > 0 else { return "Nothing selected" }
    return "\(fileCountLine(count)) selected, \(ByteFigure.string(review.selectedByteTotal))"
  }

  // MARK: - Actions

  private func beginExecution() {
    if let scope = model.permanentDeletionScope() {
      confirmingScope = scope
      return
    }
    model.executeSelection(permanentConfirmation: nil)
  }

  private func execute(confirming scope: PermanentDeletionScope) {
    model.executeSelection(
      permanentConfirmation: PermanentDeletionConfirmation(
        fileCount: scope.fileCount,
        byteTotal: scope.byteTotal,
        confirmedAt: Date()
      )
    )
  }

  private var isConfirmingPermanent: Binding<Bool> {
    Binding(
      get: { confirmingScope != nil },
      set: { isPresented in
        if !isPresented { confirmingScope = nil }
      }
    )
  }

  private func isCategoryFullySelected(_ group: CleanupReviewCategory) -> Bool {
    group.findings.allSatisfy { review.selectedFindingIDs.contains($0.id) }
  }

  private func toggleCollapse(_ category: FindingCategory) {
    if collapsedCategories.contains(category) {
      collapsedCategories.remove(category)
    } else {
      collapsedCategories.insert(category)
    }
  }

  private func rowTitle(_ finding: Finding) -> String {
    guard finding.paths.count > 1 else {
      return finding.paths.first?.lastComponent ?? ""
    }
    return "\(finding.paths.count) files"
  }

  private func fileCountLine(_ count: UInt32) -> String {
    count == 1 ? "1 file" : "\(count) files"
  }
}

/// One selection checkmark on the snappy spring.
struct CleanupCheckmark: View {
  let isSelected: Bool
  let reduceMotion: Bool
  let action: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Button(action: action) {
      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 16))
        .foregroundStyle(
          isSelected
            ? GleamColorToken.accent.color(for: colorScheme)
            : GleamColorToken.textSecondary.color(for: colorScheme)
        )
        .scaleEffect(isSelected ? 1 : 0.92)
        .animation(GleamSpring.snappy.animation(reduceMotion: reduceMotion), value: isSelected)
    }
    .buttonStyle(.plain)
  }
}

/// The risk semantic colour as a quiet dot, inspectable via help text.
struct CleanupRiskDot: View {
  let risk: RiskLevel
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 8, height: 8)
      .help(sentence)
  }

  private var color: Color {
    switch risk {
    case .safe: return GleamColorToken.safe.color(for: colorScheme)
    case .review: return GleamColorToken.review.color(for: colorScheme)
    case .dangerous: return GleamColorToken.dangerous.color(for: colorScheme)
    }
  }

  private var sentence: String {
    switch risk {
    case .safe: return "Safe to remove."
    case .review: return "Review before removing."
    case .dangerous: return "Dangerous to remove."
    }
  }
}

/// Staggered row entrance: a 30 millisecond stagger, capped at 8 rows so
/// large results do not turn into a light show. Reduce Motion appears in
/// place with a crossfade.
struct CleanupStaggeredAppearance<Content: View>: View {
  let index: Int
  let reduceMotion: Bool
  @ViewBuilder let content: Content
  @State private var hasAppeared = false

  var body: some View {
    content
      .opacity(hasAppeared ? 1 : 0)
      .offset(y: hasAppeared || reduceMotion ? 0 : 8)
      .onAppear {
        let delay = Double(min(index, 8)) * 0.03
        withAnimation(GleamSpring.gentle.animation(reduceMotion: reduceMotion).delay(delay)) {
          hasAppeared = true
        }
      }
  }
}

extension FindingCategory {
  /// The review section title for every cleanup category, with a safe plain
  /// fallback for categories other modules own.
  var cleanupTitle: String {
    switch self {
    case .userCache: return "User caches"
    case .applicationCache: return "Application caches"
    case .log: return "Logs"
    case .brokenDownload: return "Broken downloads"
    case .xcodeDerivedData: return "Xcode derived data"
    case .simulatorCache: return "Simulator caches"
    case .browserCache: return "Browser caches"
    case .temporaryFile: return "Temporary files"
    case .mailAttachmentLocalCopy: return "Mail attachment local copies"
    case .trashBin(let volume):
      return volume.value == "/" ? "Trash bin" : "Trash bin on \(volume.lastComponent)"
    default: return "Other findings"
    }
  }
}
