import GleamCore
import GleamDesign
import GleamHub
import SwiftUI

/// The menu bar: three figures read in a glance, and one way into the app.
///
/// It shows what the hub shows and nothing else, because two surfaces
/// disagreeing about how full the disk is would make both of them useless. The
/// quick action opens the app on Full Sweep rather than doing anything by
/// itself: nothing this app removes happens without a window somebody can see.
struct MenuBarPopover: View {
  let model: MenuBarModel
  let onOpenFullSweep: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(1)) {
      Text("MacGleam")
        .gleamType(.body)
        .fontWeight(.semibold)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      if model.lines.isEmpty {
        Text("Nothing is switched on to show here. Settings has the three figures.")
          .gleamType(.caption)
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      } else {
        ForEach(model.lines) { line in
          row(line)
        }
      }
      Divider()
      Button("Full Sweep", action: onOpenFullSweep)
        .buttonStyle(.plain)
        .gleamType(.body)
        .foregroundStyle(GleamColorToken.accent.color(for: colorScheme))
    }
    .padding(GleamSpacing.points(2))
    .frame(width: 260)
    .task { model.start() }
  }

  private func row(_ line: MenuBarLine) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(line.title)
          .gleamType(.caption)
          .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        Spacer()
        Text(line.value)
          .gleamType(.caption)
          .foregroundStyle(
            line.isAttention
              ? GleamColorToken.review.color(for: colorScheme)
              : GleamColorToken.textPrimary.color(for: colorScheme)
          )
          .contentTransition(.numericText())
      }
      if let fraction = line.fraction {
        GeometryReader { geometry in
          ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
              .fill(GleamColorToken.textSecondary.color(for: colorScheme).opacity(0.2))
            RoundedRectangle(cornerRadius: 2)
              .fill(
                line.isAttention
                  ? GleamColorToken.review.color(for: colorScheme)
                  : GleamColorToken.accent.color(for: colorScheme)
              )
              .frame(width: max(2, geometry.size.width * fraction))
          }
        }
        .frame(height: 4)
      }
    }
  }
}

/// What the menu bar item itself shows: the figure most worth a glance, which
/// is whichever one is asking for attention, and free space otherwise.
struct MenuBarLabel: View {
  let model: MenuBarModel

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "sparkles")
      if let line = headline {
        Text(line.value)
      }
    }
  }

  private var headline: MenuBarLine? {
    model.lines.first(where: \.isAttention) ?? model.lines.first
  }
}
