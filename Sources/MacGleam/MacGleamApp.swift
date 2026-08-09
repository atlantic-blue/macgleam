import GleamDesign
import GleamHub
import SwiftUI

@main
struct MacGleamApp: App {
  @State private var hubModel = HubModel(state: .firstRun(now: Date()))
  @State private var onboardingModel = DiskAccessOnboardingModel(
    monitor: RealFullDiskAccessMonitor()
  )

  var body: some Scene {
    WindowGroup {
      RootView(hubModel: hubModel, onboardingModel: onboardingModel)
        .frame(minWidth: 980, minHeight: 700)
    }
    .windowResizability(.contentMinSize)
  }
}

/// Composes the hub with the Full Disk Access flow: the explanation card
/// over a blurred hub while ungranted and undecided, the degraded banner
/// inline at the hub's bottom edge after declining or revocation, and
/// nothing at all once granted. The onboarding model's monitoring runs for
/// the life of this scene.
struct RootView: View {
  let hubModel: HubModel
  let onboardingModel: DiskAccessOnboardingModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let hubBlurWhileOnboarding: CGFloat = 8

  var body: some View {
    ZStack {
      HubView(model: hubModel)
        .blur(radius: showsExplanation ? Self.hubBlurWhileOnboarding : 0)
        .allowsHitTesting(!showsExplanation)
      if let sentence = degradedSentence {
        VStack {
          Spacer()
          DiskAccessDegradedBanner(
            sentence: sentence,
            onOpenSettings: { onboardingModel.openSystemSettings() }
          )
          .padding(.bottom, GleamSpacing.points(3))
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      if showsExplanation {
        OnboardingView(model: onboardingModel)
          .transition(.opacity)
      }
    }
    .animation(
      GleamSpring.gentle.animation(reduceMotion: reduceMotion),
      value: onboardingModel.step
    )
    .task { await onboardingModel.monitorUpdates() }
  }

  private var showsExplanation: Bool {
    onboardingModel.step == .explanation
  }

  private var degradedSentence: String? {
    if case .degraded(let unavailable) = onboardingModel.step {
      return unavailable
    }
    return nil
  }
}

extension HubMachineState {
  /// The seed before any scan exists: no history, all modules enabled, empty
  /// figures, so the first run invitation shows.
  static func firstRun(now: Date) -> HubMachineState {
    HubMachineState(
      lastScanFinishedAt: nil,
      reclaimableEstimateBytes: nil,
      attentionReason: nil,
      cardFigures: [:],
      enabledModules: Set(HubModule.allCases),
      now: now
    )
  }
}
