import GleamDesign
import GleamHub
import SwiftUI

/// The pane beside the rail: the heading, what this module is for, the jobs
/// it runs with their live figures, and the one control that runs them.
///
/// The reading column sits vertically centred and the action sits alone at
/// the bottom, so a module with three jobs and one with none read as the same
/// screen rather than as two different layouts.
struct ModulePaneView: View {
  let pane: ModulePane
  let onActivate: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  private static let readingColumnWidth: CGFloat = GleamSpacing.points(58)

  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: GleamSpacing.points(4))
      readingColumn
      Spacer(minLength: GleamSpacing.points(4))
      footer
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, GleamSpacing.points(6))
    .padding(.vertical, GleamSpacing.points(5))
  }

  private var readingColumn: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(pane.title)
        .gleamType(.heading)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text(pane.sentence)
        .gleamType(.body)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .padding(.top, GleamSpacing.points(1))
      if !pane.jobs.isEmpty {
        VStack(alignment: .leading, spacing: GleamSpacing.half(3)) {
          ForEach(pane.jobs) { job in
            JobRow(job: job, isLive: pane.action != nil)
          }
        }
        .padding(.top, GleamSpacing.points(4))
      }
    }
    .frame(width: Self.readingColumnWidth, alignment: .leading)
  }

  @ViewBuilder
  private var footer: some View {
    if let action = pane.action {
      PrimaryButton(title: action.title, action: onActivate)
    } else if let note = pane.notReadyNote {
      Text(note)
        .gleamType(.body)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .padding(.horizontal, GleamSpacing.half(5))
        .padding(.vertical, GleamSpacing.half(3))
        .background(
          Capsule().fill(GleamColorToken.surface.color(for: colorScheme))
        )
        .overlay(
          Capsule()
            .strokeBorder(Color.white.opacity(GleamElevation.low.borderOpacity), lineWidth: 1)
        )
    }
  }
}

/// One job the module runs. The well behind the glyph brightens when the
/// module can actually run it.
private struct JobRow: View {
  let job: ModulePaneJob
  let isLive: Bool
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: GleamSpacing.points(2)) {
      RoundedRectangle(cornerRadius: GleamRadius.item.value)
        .fill(wellFill)
        .frame(width: GleamSpacing.points(4), height: GleamSpacing.points(4))
        .overlay(
          Image(systemName: job.symbolName)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(glyphColor)
        )
      Text(job.name)
        .gleamType(.label)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Spacer(minLength: GleamSpacing.points(2))
      if !job.detail.isEmpty {
        Text(job.detail)
          .gleamType(.body)
          .foregroundStyle(GleamColorToken.accent.color(for: colorScheme))
      }
    }
  }

  private var wellFill: Color {
    isLive
      ? GleamColorToken.primary.color(for: colorScheme).opacity(0.10)
      : GleamColorToken.surfaceHigh.color(for: colorScheme)
  }

  private var glyphColor: Color {
    isLive
      ? GleamColorToken.primary.color(for: colorScheme)
      : GleamColorToken.textSecondary.color(for: colorScheme)
  }
}

/// The pane's one primary control: a filled accent button with the specified
/// inner top highlight.
struct PrimaryButton: View {
  let title: String
  let action: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .gleamType(.label)
        .foregroundStyle(GleamColorToken.onPrimary.color(for: colorScheme))
        .padding(.horizontal, GleamSpacing.points(4))
        .padding(.vertical, GleamSpacing.half(3))
        .background(
          RoundedRectangle(cornerRadius: GleamRadius.control.value)
            .fill(GleamColorToken.primary.color(for: colorScheme))
            .brightness(isHovering ? 0.06 : 0)
        )
        .overlay(
          RoundedRectangle(cornerRadius: GleamRadius.control.value)
            .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
            .mask(
              LinearGradient(
                colors: [.white, .clear], startPoint: .top, endPoint: .center)
            )
        )
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .animation(GleamSpring.snappy.animation(reduceMotion: reduceMotion), value: isHovering)
  }
}
