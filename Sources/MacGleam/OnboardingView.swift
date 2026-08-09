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
        .font(GleamTypeToken.title.font)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text(
        """
        Finding caches, mail attachments and the trash bins of other apps \
        needs Full Disk Access, which macOS grants only from System Settings \
        under Privacy and Security. MacGleam scans on your say so, never \
        sends a file name off this Mac, and moves nothing without showing \
        you first.
        """
      )
      .font(GleamTypeToken.body.font)
      .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      VStack(spacing: GleamSpacing.points(2)) {
        Button(action: { model.openSystemSettings() }) {
          Text("Open System Settings")
            .font(GleamTypeToken.body.font.weight(.semibold))
            .foregroundStyle(GleamColorToken.baseBackground.color(for: colorScheme))
            .padding(.vertical, GleamSpacing.points(1))
            .padding(.horizontal, GleamSpacing.points(3))
            .background(
              RoundedRectangle(cornerRadius: GleamRadius.control.value)
                .fill(GleamColorToken.accent.color(for: colorScheme))
            )
        }
        .buttonStyle(.plain)
        Button(action: { model.continueWithoutAccess() }) {
          Text("Continue without access")
            .font(GleamTypeToken.caption.font)
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
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
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
        .font(GleamTypeToken.caption.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .fixedSize(horizontal: false, vertical: true)
      Button(action: onOpenSettings) {
        Text("Grant access")
          .font(GleamTypeToken.caption.font.weight(.semibold))
          .foregroundStyle(GleamColorToken.accent.color(for: colorScheme))
      }
      .buttonStyle(.plain)
    }
    .padding(.vertical, GleamSpacing.points(2))
    .padding(.horizontal, GleamSpacing.points(3))
    .background(
      RoundedRectangle(cornerRadius: GleamRadius.card.value)
        .fill(GleamColorToken.surface.color(for: colorScheme))
    )
    .overlay(
      RoundedRectangle(cornerRadius: GleamRadius.card.value)
        .strokeBorder(
          GleamColorToken.review.color(for: colorScheme).opacity(0.4),
          lineWidth: 1
        )
    )
  }
}
