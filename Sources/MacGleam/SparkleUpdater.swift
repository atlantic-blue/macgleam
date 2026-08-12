import Foundation
import GleamCore
import Sparkle
import os

/// The app's updater: Sparkle behind the one surface the rest of the app sees.
///
/// The rules live here rather than in the framework's configuration, because
/// they are decisions about how this app treats the person using it. The feed
/// is the channel's own, so nothing else can point a build somewhere. A check
/// looks and asks, so an app that can replace itself never does it while
/// nobody is watching. And the signature is checked by Sparkle against the key
/// in the bundle, so an entry that was tampered with is refused before it is
/// ever shown to anybody.
@MainActor
final class SparkleUpdater: AppUpdating {
  private let controller: SPUStandardUpdaterController
  private let log = Logger(subsystem: "com.atlanticblue.macgleam", category: "updates")

  init(policy: UpdatePolicy = UpdatePolicy()) {
    // Started here rather than lazily: the scheduled check is what makes a
    // daily check daily, and starting it at the moment somebody first opened
    // Settings would make the schedule depend on where they clicked.
    controller = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    applyNow(policy)
  }

  nonisolated func apply(_ policy: UpdatePolicy) async {
    await MainActor.run { applyNow(policy) }
  }

  nonisolated func check() async {
    await MainActor.run { controller.checkForUpdates(nil) }
  }

  nonisolated var lastCheck: Date? {
    get async { await MainActor.run { controller.updater.lastUpdateCheckDate } }
  }

  var canCheck: Bool {
    controller.updater.canCheckForUpdates
  }

  private func applyNow(_ policy: UpdatePolicy) {
    controller.updater.automaticallyChecksForUpdates = policy.checksAutomatically
    controller.updater.updateCheckInterval = policy.checkInterval
    // Sparkle would otherwise take the feed from the bundle. Setting it from
    // the policy is what makes the channel a choice somebody can change
    // rather than a constant baked in at build time.
    controller.updater.setFeedURL(policy.feedURL)
    log.info("Update channel set to \(policy.channel.rawValue, privacy: .public).")
  }
}
