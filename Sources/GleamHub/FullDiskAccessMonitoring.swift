/// Full Disk Access state for the onboarding flow and the degraded mode
/// banner. This is the C32 protocol; the contract files it under app
/// services, and it lives in GleamHub until such a target exists.
///
/// Guarantees:
/// - `isGranted` reflects the real, current grant, probed in a way that
///   does not itself trigger a permission prompt.
/// - `updates` emits when the grant changes while the app runs, so the
///   onboarding flow advances by itself when the user flips the toggle in
///   System Settings. Emission within two seconds of the change.
/// - `openPrivacySettings` deep links to the Privacy and Security pane.
/// - The app never nags on a schedule: this service reports state, it never
///   prompts.
public protocol FullDiskAccessMonitoring: Sendable {
  var isGranted: Bool { get async }
  func updates() -> AsyncStream<Bool>
  @MainActor func openPrivacySettings()
}
