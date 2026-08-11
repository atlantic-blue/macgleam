import Foundation
import GleamHub

/// A fixed instant every test pins its clock to. Derivation must reckon
/// recency against `HubMachineState.now`, never against the wall clock, so
/// the tests choose their own instants.
let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

func makeHubMachineState(
  lastScanFinishedAt: Date? = nil,
  reclaimableEstimateBytes: UInt64? = nil,
  attentionReason: String? = nil,
  moduleFigures: [HubModule: String] = [:],
  enabledModules: Set<HubModule> = [],
  now: Date = fixedNow
) -> HubMachineState {
  HubMachineState(
    lastScanFinishedAt: lastScanFinishedAt,
    reclaimableEstimateBytes: reclaimableEstimateBytes,
    attentionReason: attentionReason,
    moduleFigures: moduleFigures,
    enabledModules: enabledModules,
    now: now
  )
}

/// The state of a machine that has never run a scan: no last scan, no
/// estimate, no attention, nothing enabled beyond the defaults.
func makeEmptyFirstRunState(now: Date = fixedNow) -> HubMachineState {
  makeHubMachineState(now: now)
}

/// A healthy machine with a recent scan and a reclaimable estimate.
func makeHealthyScannedState(
  scanAge: TimeInterval = 3_600,
  reclaimableEstimateBytes: UInt64 = 12_800_000_000,
  now: Date = fixedNow
) -> HubMachineState {
  makeHubMachineState(
    lastScanFinishedAt: now.addingTimeInterval(-scanAge),
    reclaimableEstimateBytes: reclaimableEstimateBytes,
    now: now
  )
}

/// A machine that needs attention, with the reason sentence supplied.
func makeAttentionState(
  reason: String = "Your Downloads folder has grown past 40 gigabytes.",
  now: Date = fixedNow
) -> HubMachineState {
  makeHubMachineState(
    lastScanFinishedAt: now.addingTimeInterval(-7_200),
    reclaimableEstimateBytes: 9_500_000_000,
    attentionReason: reason,
    now: now
  )
}

/// One figure per module so flow through checks can see every module.
func makeFullModuleFigures() -> [HubModule: String] {
  Dictionary(
    uniqueKeysWithValues: HubModule.allCases.map { module in
      (module, "figure for \(module.rawValue)")
    }
  )
}

/// Every field populated: scan history, estimate, attention, all figures,
/// all modules enabled.
func makeFullyPopulatedState(now: Date = fixedNow) -> HubMachineState {
  makeHubMachineState(
    lastScanFinishedAt: now.addingTimeInterval(-600),
    reclaimableEstimateBytes: 42_000_000_000,
    attentionReason: "Two applications are holding leftover support files.",
    moduleFigures: makeFullModuleFigures(),
    enabledModules: Set(HubModule.allCases),
    now: now
  )
}

/// Module summaries with the named modules enabled and the given figures.
func makeSummaries(
  enabled: Set<HubModule> = [],
  figures: [HubModule: String] = [:]
) -> [HubModuleSummary] {
  HubModule.allCases.map { module in
    HubModuleSummary(
      module: module,
      figure: figures[module] ?? "",
      isEnabled: enabled.contains(module)
    )
  }
}
