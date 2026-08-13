import Foundation

/// Whether a build can update itself, decided from the key it carries.
///
/// Sparkle refuses to start without a public key it can use, and a build that
/// has not been given one is every build before the first release. Left to the
/// framework, that ends as a failure dialog in front of somebody who can do
/// nothing about it. So the decision is made here, before anything is started:
/// a build with no usable key has no updater, and Settings says so.
public enum UpdaterAvailability {
  /// What the bundler writes into a build that has no key yet.
  public static let placeholder = "REPLACE_AT_LAUNCH_WITH_THE_APPCAST_PUBLIC_KEY"

  /// What Settings shows in place of a check somebody cannot run.
  public static let unavailableExplanation =
    "This build carries no update key, so it cannot check for updates."

  /// A signing key is 32 bytes. Anything else is a typo or a placeholder, and
  /// both fail at the framework rather than here, which is the point.
  private static let keyByteCount = 32

  public static func canUpdate(publicKey: String?) -> Bool {
    guard let publicKey else { return false }
    let trimmed = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != placeholder else { return false }
    guard let decoded = Data(base64Encoded: trimmed) else { return false }
    return decoded.count == keyByteCount
  }
}

/// What the updates row says, given what the build can do and when it last
/// looked.
///
/// It lives here rather than in the view so the sentence can be tested. Three
/// facts, and they are all different: this build cannot update itself, it can
/// and has never looked, it can and looked at a time.
public enum UpdatesSummary {
  public static func line(isAvailable: Bool, lastCheck: String?) -> String {
    guard isAvailable else { return UpdaterAvailability.unavailableExplanation }
    guard let lastCheck else { return "Not checked yet." }
    return "Last checked \(lastCheck)."
  }
}
