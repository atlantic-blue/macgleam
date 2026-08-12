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
    if let request = HelperDiagnostics.request(from: CommandLine.arguments) {
      reportHelperAndExit(request)
      return
    }
    if let request = RenderToFile.request(from: CommandLine.arguments) {
      renderAndExit(request)
      return
    }
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  /// A helper run never shows a window either. It reports where the privileged
  /// helper stands and exits.
  private func reportHelperAndExit(_ request: HelperDiagnostics.Request) {
    Task {
      let report = await HelperDiagnostics.run(request)
      FileHandle.standardOutput.write(Data("\(report)\n".utf8))
      exit(0)
    }
  }

  /// A render run never shows a window. It reads the file system only when
  /// asked to map a folder, and writes only the image.
  @MainActor
  private func renderAndExit(_ request: RenderToFile.Request) {
    let onboarding = DiskAccessOnboardingModel(monitor: RealFullDiskAccessMonitor())
    // A render never asks the channel for anything: it draws what a build
    // holds, so a picture does not depend on a network.
    let supply = RuleSupply()
    let diskMap = DiskMapComposition.make(supply: supply)
    Task { @MainActor in
      if let folder = request.mapFolder {
        await RenderToFile.mapAndSettle(diskMap.model, folder: folder)
      }
      do {
        try RenderToFile.render(
          request,
          hub: HubModel(state: .firstRun(now: Date())),
          cleanup: CleanupComposition.make(onboarding: onboarding, supply: supply),
          diskMap: diskMap,
          protection: ProtectionComposition.make(supply: supply, helpers: HelperSupply()),
          fullSweep: FullSweepComposition.make(supply: supply, helpers: HelperSupply())
        )
        FileHandle.standardOutput.write(Data("rendered \(request.destination.path)\n".utf8))
        exit(0)
      } catch {
        FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
        exit(1)
      }
    }
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
  @State private var diskMap: DiskMapDependencies
  @State private var protection: ProtectionDependencies
  @State private var fullSweep: FullSweepDependencies
  @State private var rules: RuleSupply

  init() {
    let onboarding = DiskAccessOnboardingModel(monitor: RealFullDiskAccessMonitor())
    let supply = RuleSupply()
    _onboardingModel = State(initialValue: onboarding)
    _rules = State(initialValue: supply)
    _cleanup = State(initialValue: CleanupComposition.make(onboarding: onboarding, supply: supply))
    _diskMap = State(initialValue: DiskMapComposition.make(supply: supply))
    _protection = State(
      initialValue: ProtectionComposition.make(supply: supply, helpers: HelperSupply()))
    _fullSweep = State(
      initialValue: FullSweepComposition.make(supply: supply, helpers: HelperSupply()))
  }

  var body: some Scene {
    WindowGroup {
      RootView(
        hubModel: hubModel,
        onboardingModel: onboardingModel,
        cleanup: cleanup,
        diskMap: diskMap,
        protection: protection,
        fullSweep: fullSweep
      )
      .frame(minWidth: 1120, minHeight: 760)
      // Best effort, once per launch. A catalogue that does not arrive
      // changes nothing: the app runs on the one it already has.
      .task { await rules.refresh() }
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentMinSize)
  }
}

/// Composes the shell with the Full Disk Access flow: the explanation card
/// over a blurred window while ungranted and undecided, the degraded banner
/// inline at the bottom edge after declining or revocation, and nothing at
/// all once granted. The onboarding model's monitoring runs for the life of
/// this scene, and the cleanup model's live estimate feeds its pane.
struct RootView: View {
  let hubModel: HubModel
  let onboardingModel: DiskAccessOnboardingModel
  let cleanup: CleanupDependencies
  let diskMap: DiskMapDependencies
  let protection: ProtectionDependencies
  let fullSweep: FullSweepDependencies
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let hubBlurWhileOnboarding: CGFloat = 8

  /// The modules whose engine and module model have shipped. Everything else
  /// still gets a pane; the pane says the module is not built rather than
  /// offering an action that would do nothing.
  static let builtModules: Set<HubModule> = [.fullSweep, .cleanup, .protection]

  var body: some View {
    ZStack {
      AppShellView(
        model: hubModel,
        cleanup: cleanup,
        diskMap: diskMap,
        protection: protection,
        fullSweep: fullSweep
      )
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
        moduleFigures: bytes > 0 ? [.cleanup: "\(ByteFigure.string(bytes)) reclaimable"] : [:],
        enabledModules: Self.builtModules,
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
      moduleFigures: [:],
      enabledModules: RootView.builtModules,
      now: now
    )
  }
}
