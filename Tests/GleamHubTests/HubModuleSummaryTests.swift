import Foundation
import GleamHub
import Testing

@Suite("Module summaries")
struct HubModuleSummaryTests {

  static let representativeStates: [HubMachineState] = [
    makeEmptyFirstRunState(),
    makeHealthyScannedState(),
    makeAttentionState(),
    makeFullyPopulatedState(),
  ]

  @Test("HubModule.allCases is the fixed module order")
  func hubModuleAllCasesIsTheFixedHexagonalOrder() {
    #expect(
      HubModule.allCases == [
        .fullSweep, .cleanup, .protection, .performance, .applications, .leftovers,
      ]
    )
  }

  @Test(
    "summaries holds exactly six entries whatever the state says",
    arguments: representativeStates
  )
  func summariesHoldExactlySixEntriesWhateverTheStateSays(state: HubMachineState) {
    #expect(HubModel.summaries(for: state).count == 6)
  }

  @Test(
    "summaries follow HubModule.allCases order whatever the state says",
    arguments: representativeStates
  )
  func summariesFollowHubModuleAllCasesOrderWhateverTheStateSays(state: HubMachineState) {
    let modules = HubModel.summaries(for: state).map(\.module)
    #expect(modules == HubModule.allCases)
  }

  @Test("a module missing from moduleFigures gets an empty figure")
  func aModuleMissingFromModuleFiguresGetsAnEmptyFigure() {
    let summaries = HubModel.summaries(for: makeEmptyFirstRunState())
    for summary in summaries {
      #expect(summary.figure.isEmpty)
    }
  }

  @Test("figures flow through to their summaries")
  func figuresFlowThroughToTheirSummaries() {
    let figures = makeFullModuleFigures()
    let state = makeHubMachineState(moduleFigures: figures)
    let summaries = HubModel.summaries(for: state)
    for summary in summaries {
      #expect(summary.figure == figures[summary.module])
    }
  }

  @Test("a partial figure map leaves the rest empty")
  func aPartialFigureMapLeavesTheRestEmpty() {
    let state = makeHubMachineState(moduleFigures: [.cleanup: "12.4 gigabytes reclaimable"])
    let summaries = HubModel.summaries(for: state)
    for summary in summaries {
      if summary.module == .cleanup {
        #expect(summary.figure == "12.4 gigabytes reclaimable")
      } else {
        #expect(summary.figure.isEmpty)
      }
    }
  }

  @Test("enabled flags flow from enabledModules")
  func enabledFlagsFlowFromEnabledModules() {
    let enabled: Set<HubModule> = [.fullSweep, .cleanup]
    let state = makeHubMachineState(enabledModules: enabled)
    let summaries = HubModel.summaries(for: state)
    for summary in summaries {
      #expect(summary.isEnabled == enabled.contains(summary.module))
    }
  }

  @Test("no enabled modules leaves every summary disabled")
  func noEnabledModulesLeavesEveryCardDisabled() {
    let summaries = HubModel.summaries(for: makeEmptyFirstRunState())
    for summary in summaries {
      #expect(!summary.isEnabled)
    }
  }

  @Test("every module enabled leaves every summary enabled")
  func everyModuleEnabledLeavesEveryCardEnabled() {
    let summaries = HubModel.summaries(for: makeFullyPopulatedState())
    for summary in summaries {
      #expect(summary.isEnabled)
    }
  }

  @Test(
    "summary identity equals its module",
    arguments: representativeStates
  )
  func summaryIdentityEqualsItsModule(state: HubMachineState) {
    for summary in HubModel.summaries(for: state) {
      #expect(summary.id == summary.module)
    }
  }

  @Test("summary derivation is deterministic across repeated calls on the same input")
  func summaryDerivationIsDeterministicAcrossRepeatedCalls() {
    let state = makeFullyPopulatedState()
    let firstSummaries = HubModel.summaries(for: state)
    for _ in 1...5 {
      #expect(HubModel.summaries(for: state) == firstSummaries)
    }
  }
}
