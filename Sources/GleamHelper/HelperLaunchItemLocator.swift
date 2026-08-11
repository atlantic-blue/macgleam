import Foundation
import GleamCore
import GleamHelperCore

/// Turns a launch item identifier into the property list launchd loads it
/// from. The helper resolves this itself, before the denylist is consulted,
/// because it cannot check least privilege for a file it has not found.
///
/// The two directories below are the system scope ones, which is the whole
/// scope the helper serves: a user scope item is the user process's own work
/// and never reaches here.
struct HelperLaunchItemLocator: HelperLaunchItemLocating {
  static let systemDirectories = [
    AbsolutePath(normalising: "/Library/LaunchDaemons"),
    AbsolutePath(normalising: "/Library/LaunchAgents"),
  ]

  let directories: [AbsolutePath]
  let fileExists: @Sendable (String) -> Bool

  init(
    directories: [AbsolutePath] = HelperLaunchItemLocator.systemDirectories,
    fileExists: @escaping @Sendable (String) -> Bool = {
      FileManager.default.fileExists(atPath: $0)
    }
  ) {
    self.directories = directories
    self.fileExists = fileExists
  }

  func location(of item: LaunchItemID) -> AbsolutePath? {
    guard isPlausibleLabel(item.value) else { return nil }
    for directory in directories {
      let candidate = AbsolutePath(normalising: "\(directory.value)/\(item.value).plist")
      if fileExists(candidate.value) { return candidate }
    }
    return nil
  }

  /// A label is one path component. Anything carrying a separator, or empty,
  /// is refused here rather than being pasted into a path, so no identifier
  /// can name a file outside the directories above.
  private func isPlausibleLabel(_ value: String) -> Bool {
    !value.isEmpty && !value.contains("/") && value != "." && value != ".."
  }
}
