import Observation

/// The Full Disk Access onboarding view model, on the same Observation
/// pattern as HubModel. The SwiftUI onboarding scene renders this and adds
/// no state of its own.
///
/// The flow starts on the explanation step. A grant advances to `granted`
/// from any step. An ungranted emission only moves `granted` to `degraded`,
/// which is a revocation; it never moves `explanation` anywhere, because the
/// user has not decided yet. Declining is explicit, through
/// `continueWithoutAccess`.
///
/// No timers, no clock, no scheduled prompting: the only way System
/// Settings opens is `openSystemSettings`, on a user action.
@MainActor @Observable
public final class DiskAccessOnboardingModel {
  /// The sentence the degraded banner shows: plain, non empty, naming what
  /// stays out of reach without the grant.
  public static let degradedBanner =
    "Without Full Disk Access, mail attachments and the trash bins of other apps stay unavailable, so scans cover your user files only."

  public private(set) var step: DiskAccessOnboardingStep = .explanation

  private let monitor: any FullDiskAccessMonitoring

  public init(monitor: any FullDiskAccessMonitoring) {
    self.monitor = monitor
  }

  /// Probes the current grant once, then consumes grant changes until the
  /// stream ends. Meant to run for the life of the onboarding scene.
  public func monitorUpdates() async {
    if await monitor.isGranted {
      step = .granted
    }
    for await isGranted in monitor.updates() {
      apply(grant: isGranted)
    }
  }

  /// The explicit decline on the explanation screen. A granted flow stays
  /// granted; declining after the grant landed is a no op.
  public func continueWithoutAccess() {
    guard step == .explanation else { return }
    step = .degraded(unavailable: Self.degradedBanner)
  }

  /// Deep links to the Privacy and Security pane. Changes no state: the
  /// flow advances only when the monitor reports the grant.
  public func openSystemSettings() {
    monitor.openPrivacySettings()
  }

  private func apply(grant isGranted: Bool) {
    if isGranted {
      step = .granted
      return
    }
    guard step == .granted else { return }
    step = .degraded(unavailable: Self.degradedBanner)
  }
}
