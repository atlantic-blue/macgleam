import AppKit
import GleamDesign
import GleamHub
import SwiftUI

/// An executable launched straight from the build directory carries no
/// bundle identity, so macOS starts it as an accessory: the window is
/// created but never takes focus and no Dock icon appears, which reads as
/// the app doing nothing at all. Claiming the regular activation policy at
/// launch makes a plain `swift run MacGleam` behave like a shipped app.
final class MacGleamAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
    true
  }
}

@main
struct MacGleamApp: App {
  @NSApplicationDelegateAdaptor(MacGleamAppDelegate.self) private var appDelegate
  @State private var hubModel = HubModel(state: .firstRun(now: Date()))
  @State private var onboardingModel: DiskAccessOnboardingModel
  @State private var cleanup: CleanupDependencies
  @State private var spaceLens: SpaceLensDependencies

  init() {
    let onboarding = DiskAccessOnboardingModel(monitor: RealFullDiskAccessMonitor())
    _onboardingModel = State(initialValue: onboarding)
    _cleanup = State(initialValue: CleanupComposition.make(onboarding: onboarding))
    _spaceLens = State(initialValue: SpaceLensComposition.make())
  }

  var body: some Scene {
    WindowGroup {
      RootView(
        hubModel: hubModel,
        onboardingModel: onboardingModel,
        cleanup: cleanup,
        spaceLens: spaceLens
      )
      .frame(minWidth: 980, minHeight: 700)
    }
    .windowResizability(.contentMinSize)
  }
}

/// Composes the hub with the Full Disk Access flow: the explanation card
/// over a blurred hub while ungranted and undecided, the degraded banner
/// inline at the hub's bottom edge after declining or revocation, and
/// nothing at all once granted. The onboarding model's monitoring runs for
/// the life of this scene, and the cleanup model's live estimate feeds the
/// hub card figure.
struct RootView: View {
  let hubModel: HubModel
  let onboardingModel: DiskAccessOnboardingModel
  let cleanup: CleanupDependencies
  let spaceLens: SpaceLensDependencies
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let hubBlurWhileOnboarding: CGFloat = 8

  var body: some View {
    ZStack {
      HubView(model: hubModel, cleanup: cleanup, spaceLens: spaceLens)
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
    .onChange(of: cleanup.model.hubEstimateBytes) { refreshHubFigures() }
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

  /// Applies the cleanup card's live figure: the model's hub estimate,
  /// formatted, and empty before it says anything.
  private func refreshHubFigures() {
    let bytes = cleanup.model.hubEstimateBytes
    hubModel.apply(
      HubMachineState(
        lastScanFinishedAt: nil,
        reclaimableEstimateBytes: nil,
        attentionReason: nil,
        cardFigures: bytes > 0 ? [.cleanup: "\(ByteFigure.string(bytes)) reclaimable"] : [:],
        enabledModules: Set(HubModule.allCases),
        now: Date()
      )
    )
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
