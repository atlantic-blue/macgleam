import GleamCore

/// What the Performance module says about a login or background item: who it
/// belongs to, and the sentence the row reads.
///
/// The owner is what makes an item legible, so it is stated plainly or its
/// absence is stated plainly. An item nothing can be attributed to is the one
/// most worth reading, so it is never dropped from the list and never labelled
/// with somebody else's app name.
public enum LaunchItemPresentation {
  /// The label for an item whose owning app cannot be resolved at all. A
  /// sentence fragment a person can act on, never an empty string and never a
  /// rendered optional.
  public static let unknownOwnerLabel = "an app this Mac cannot identify"

  /// Who the item belongs to: the app's name where macOS knows it, the bundle
  /// identifier where that is all there is, and an honest admission where
  /// there is neither. Three answers, in descending order of how much the
  /// person can do with them.
  public static func ownerLabel(for item: LaunchItem) -> String {
    if let name = item.owningAppName, !name.isEmpty { return name }
    if let bundleID = item.owningAppBundleID, !bundleID.isEmpty {
      return "an app registered as \(bundleID)"
    }
    return unknownOwnerLabel
  }

  /// The row's sentence: what this registration is, who put it there and what
  /// turning it off costs. It names the registration and the owner, so the two
  /// things a person needs in order to decide are both in the line they read.
  public static func explanation(for item: LaunchItem) -> String {
    "\(kindSentence(for: item)) named \(item.label), belonging to \(ownerLabel(for: item)). "
      + "\(scopeSentence(for: item)) Turning it off stops it starting itself and removes nothing, "
      + "so it can be turned back on at any time."
  }

  private static func kindSentence(for item: LaunchItem) -> String {
    switch item.kind {
    case .appService:
      return "A login item"
    case .legacyLaunchAgent:
      return "A background agent"
    case .legacyLaunchDaemon:
      return "A background service"
    }
  }

  private static func scopeSentence(for item: LaunchItem) -> String {
    switch item.scope {
    case .user:
      return "It runs when you log in."
    case .system:
      return "It runs for everybody on this Mac, so turning it off needs your permission."
    }
  }
}
