import Foundation
import GleamCore
import Observation

/// What the Settings screen knows about updates: the policy in force and when
/// this Mac last looked.
///
/// Choosing a channel takes effect immediately rather than at the next launch,
/// because somebody who just switched to beta is asking for the beta now.
@MainActor @Observable
final class UpdatesModel {
  private(set) var policy: UpdatePolicy
  private(set) var lastCheck: Date?

  @ObservationIgnored private let updater: any AppUpdating

  init(updater: any AppUpdating, policy: UpdatePolicy = UpdatePolicy()) {
    self.updater = updater
    self.policy = policy
  }

  func select(channel: UpdateChannel) async {
    policy = UpdatePolicy(
      channel: channel,
      checksAutomatically: policy.checksAutomatically,
      checkInterval: policy.checkInterval)
    await updater.apply(policy)
  }

  /// Whether this build can update itself at all. A build without a key
  /// offers no check, rather than offering one that fails.
  var isAvailable: Bool { updater.isAvailable }

  func check() async {
    await updater.check()
    lastCheck = await updater.lastCheck
  }

  /// What the row says. A Mac that has never looked says so rather than
  /// showing a blank, because "never checked" and "checked and found nothing"
  /// are different facts.
  var lastCheckLine: String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return UpdatesSummary.line(
      isAvailable: updater.isAvailable,
      lastCheck: lastCheck.map { formatter.string(from: $0) })
  }
}
