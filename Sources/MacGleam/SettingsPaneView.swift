import GleamCore
import GleamDesign
import GleamHub
import SwiftUI

/// The Settings destination: what MacGleam does with what it finds, and where
/// this copy stands.
///
/// The licence section says the same thing in every state and gates nothing.
/// The trial ending changes this sentence and nothing else in the app, which
/// is a product decision rather than an oversight: an app somebody cannot
/// evaluate is an app nobody buys.
struct SettingsPaneView: View {
  let licence: LicenceModel
  @Environment(\.colorScheme) private var colorScheme
  @State private var licenceKey = ""

  var body: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(2)) {
      Text("Settings")
        .gleamType(.heading)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      licenceSection
      Spacer()
    }
    .padding(.horizontal, GleamSpacing.points(6))
    .padding(.vertical, GleamSpacing.points(5))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task { await licence.refresh() }
  }

  private var licenceSection: some View {
    VStack(alignment: .leading, spacing: GleamSpacing.points(1)) {
      Text("Licence")
        .gleamType(.body)
        .fontWeight(.semibold)
        .foregroundStyle(GleamColorToken.textPrimary.color(for: colorScheme))
      Text(licence.state.invitation)
        .gleamType(.caption)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      if !isLicensed {
        HStack(spacing: GleamSpacing.points(1)) {
          TextField("Licence key", text: $licenceKey)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 260)
          PrimaryButton(
            title: "Activate",
            action: { Task { await licence.activate(licenceKey: licenceKey) } },
            isEnabled: !licence.isActivating && !licenceKey.isEmpty)
        }
      }
      if let notice = licence.activationNotice {
        CleanupNoticeCard(
          sentences: [notice], tint: GleamColorToken.review.color(for: colorScheme))
      }
    }
  }

  private var isLicensed: Bool {
    if case .licensed = licence.state { return true }
    return false
  }
}
