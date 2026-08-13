import Foundation
import GleamCore

/// Picks the updater this build is entitled to.
///
/// The key comes from the bundle, which is the only place it can come from:
/// the app checks a signature against the key it was built with, so a key from
/// anywhere else would defeat the check it exists for. A build without one
/// gets an updater that does nothing and says so, and the framework is never
/// started, so it never puts its own failure in front of anybody.
@MainActor
enum UpdaterComposition {
  static let publicKeyName = "SUPublicEDKey"

  static func make(publicKey: String? = bundleKey()) -> any AppUpdating {
    guard UpdaterAvailability.canUpdate(publicKey: publicKey) else {
      return UnavailableUpdater()
    }
    return SparkleUpdater()
  }

  private static func bundleKey() -> String? {
    Bundle.main.object(forInfoDictionaryKey: publicKeyName) as? String
  }
}
