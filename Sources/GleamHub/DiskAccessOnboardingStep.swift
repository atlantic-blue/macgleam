/// Where the Full Disk Access onboarding flow stands.
///
/// `explanation` is the first run screen that says why access is wanted.
/// `degraded` is the honest fallback after declining or revoking, carrying
/// the banner sentence that names what is unavailable. `granted` means the
/// toggle is on and the flow is over.
public enum DiskAccessOnboardingStep: Sendable, Equatable {
  case explanation
  case degraded(unavailable: String)
  case granted
}
