import GleamDesign
import GleamHub
import SwiftUI

@main
struct MacGleamApp: App {
  @State private var model = HubModel(state: .firstRun(now: Date()))

  var body: some Scene {
    WindowGroup {
      HubView(model: model)
        .frame(minWidth: 980, minHeight: 700)
    }
    .windowResizability(.contentMinSize)
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
