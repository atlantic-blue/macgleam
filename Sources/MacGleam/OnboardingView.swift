import GleamDesign
import GleamHub
import SwiftUI

/// The first run Full Disk Access explanation, shown over the blurred hub
/// until the user grants access or chooses to continue without it.
struct OnboardingView: View {
  let model: DiskAccessOnboardingModel
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: GleamSpacing.points(3)) {
      Image(systemName: "internaldrive")
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(GleamColorToken.accent.color(for: colorScheme))
      Text("Let MacGleam see the whole disk")
        .gleamType(.title)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text(
        """
        Finding caches, mail attachments and the trash bins of other apps \
        needs Full Disk Access. macOS never asks for it, so you grant it \
        yourself: open System Settings, then add MacGleam to the list with \
        the plus button and switch it on. MacGleam scans on your say so, \
        never sends a file name off this Mac, and moves nothing without \
        showing you first.
        """
      )
      .gleamType(.body)
      .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      VStack(spacing: GleamSpacing.points(2)) {
        PrimaryButton(
          title: "Open System Settings", action: { model.openSystemSettings() })
        Button(action: { model.continueWithoutAccess() }) {
          Text("Continue without access")
            .gleamType(.caption)
            .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
            .underline()
        }
        .buttonStyle(.plain)
      }
      .padding(.top, GleamSpacing.points(1))
    }
    .padding(GleamSpacing.points(5))
    .frame(maxWidth: 440)
    .background(
      RoundedRectangle(cornerRadius: GleamRadius.card.value)
        .fill(GleamColorToken.surface.color(for: colorScheme))
        .shadow(
          color: .black.opacity(GleamElevation.high.shadowOpacity),
          radius: GleamElevation.high.shadowRadius,
          y: GleamElevation.high.shadowOffsetY
        )
    )
    .overlay(
      RoundedRectangle(cornerRadius: GleamRadius.card.value)
        .strokeBorder(
          Color.white.opacity(GleamElevation.high.borderOpacity), lineWidth: 1)
    )
  }
}

/// The degraded mode banner: an inline card pinned to the hub's bottom
/// edge, never a modal. It states what stays unavailable and offers the
/// System Settings deep link, and it leaves on its own when the grant
/// lands.
struct DiskAccessDegradedBanner: View {
  let sentence: String
  let onOpenSettings: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: GleamSpacing.points(2)) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(GleamColorToken.review.color(for: colorScheme))
      Text(sentence)
        .gleamType(.caption)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .fixedSize(horizontal: false, vertical: true)
      Button(action: onOpenSettings) {
        Text("Grant access")
          .gleamType(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(GleamColorToken.accent.color(for: colorScheme))
      }
      .buttonStyle(.plain)
    }
    .padding(.vertical, GleamSpacing.points(2))
    .padding(.horizontal, GleamSpacing.points(3))
    .background(
      RoundedRectangle(cornerRadius: GleamRadius.item.value)
        .fill(GleamColorToken.surface.color(for: colorScheme))
    )
    .overlay(
      RoundedRectangle(cornerRadius: GleamRadius.item.value)
        .strokeBorder(
          GleamColorToken.review.color(for: colorScheme).opacity(0.4),
          lineWidth: 1
        )
    )
  }
}
