import Foundation
import GleamHub
import Testing

@Suite("Hub cards")
struct HubCardsTests {

  static let representativeStates: [HubMachineState] = [
    makeEmptyFirstRunState(),
    makeHealthyScannedState(),
    makeAttentionState(),
    makeFullyPopulatedState(),
  ]

  @Test("HubModule.allCases is the fixed hexagonal order")
  func hubModuleAllCasesIsTheFixedHexagonalOrder() {
    #expect(
      HubModule.allCases == [
        .smartCare, .cleanup, .protection, .performance, .applications, .myClutter,
      ]
    )
  }

  @Test(
    "cards holds exactly six entries whatever the state says",
    arguments: representativeStates
  )
  func cardsHoldsExactlySixEntriesWhateverTheStateSays(state: HubMachineState) {
    #expect(HubModel.cards(for: state).count == 6)
  }

  @Test(
    "cards follow HubModule.allCases order whatever the state says",
    arguments: representativeStates
  )
  func cardsFollowHubModuleAllCasesOrderWhateverTheStateSays(state: HubMachineState) {
    let modules = HubModel.cards(for: state).map(\.module)
    #expect(modules == HubModule.allCases)
  }

  @Test("a module missing from cardFigures gets an empty figure")
  func aModuleMissingFromCardFiguresGetsAnEmptyFigure() {
    let cards = HubModel.cards(for: makeEmptyFirstRunState())
    for card in cards {
      #expect(card.figure.isEmpty)
    }
  }

  @Test("figures flow through from cardFigures to their cards")
  func figuresFlowThroughFromCardFiguresToTheirCards() {
    let figures = makeFullCardFigures()
    let state = makeHubMachineState(cardFigures: figures)
    let cards = HubModel.cards(for: state)
    for card in cards {
      #expect(card.figure == figures[card.module])
    }
  }

  @Test("a partial cardFigures maps supplied figures and leaves the rest empty")
  func aPartialCardFiguresMapsSuppliedFiguresAndLeavesTheRestEmpty() {
    let state = makeHubMachineState(cardFigures: [.cleanup: "12.4 gigabytes reclaimable"])
    let cards = HubModel.cards(for: state)
    for card in cards {
      if card.module == .cleanup {
        #expect(card.figure == "12.4 gigabytes reclaimable")
      } else {
        #expect(card.figure.isEmpty)
      }
    }
  }

  @Test("enabled flags flow from enabledModules")
  func enabledFlagsFlowFromEnabledModules() {
    let enabled: Set<HubModule> = [.smartCare, .cleanup]
    let state = makeHubMachineState(enabledModules: enabled)
    let cards = HubModel.cards(for: state)
    for card in cards {
      #expect(card.isEnabled == enabled.contains(card.module))
    }
  }

  @Test("no enabled modules leaves every card disabled")
  func noEnabledModulesLeavesEveryCardDisabled() {
    let cards = HubModel.cards(for: makeEmptyFirstRunState())
    for card in cards {
      #expect(!card.isEnabled)
    }
  }

  @Test("every module enabled leaves every card enabled")
  func everyModuleEnabledLeavesEveryCardEnabled() {
    let cards = HubModel.cards(for: makeFullyPopulatedState())
    for card in cards {
      #expect(card.isEnabled)
    }
  }

  @Test(
    "card identity equals its module",
    arguments: representativeStates
  )
  func cardIdentityEqualsItsModule(state: HubMachineState) {
    for card in HubModel.cards(for: state) {
      #expect(card.id == card.module)
    }
  }

  @Test("card derivation is deterministic across repeated calls on the same input")
  func cardDerivationIsDeterministicAcrossRepeatedCalls() {
    let state = makeFullyPopulatedState()
    let firstCards = HubModel.cards(for: state)
    for _ in 1...5 {
      #expect(HubModel.cards(for: state) == firstCards)
    }
  }
}
