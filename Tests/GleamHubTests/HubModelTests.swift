import Foundation
import GleamHub
import Testing

@MainActor
@Suite("Hub model observation")
struct HubModelTests {

  @Test("init projects mood, status line and cards from the initial state")
  func initProjectsMoodStatusLineAndCardsFromTheInitialState() {
    let state = makeHealthyScannedState()
    let model = HubModel(state: state)
    #expect(model.orbMood == HubModel.mood(for: state))
    #expect(model.statusLine == HubModel.statusLine(for: state))
    #expect(model.cards == HubModel.cards(for: state))
  }

  @Test("init projects the attention pair for an attention state")
  func initProjectsTheAttentionPairForAnAttentionState() {
    let state = makeAttentionState()
    let model = HubModel(state: state)
    #expect(model.orbMood == .idleAttention)
    #expect(model.statusLine == HubModel.statusLine(for: state))
    #expect(model.cards == HubModel.cards(for: state))
  }

  @Test("apply updates all three observed properties to projections of the new state")
  func applyUpdatesAllThreeObservedPropertiesToProjectionsOfTheNewState() {
    let model = HubModel(state: makeEmptyFirstRunState())
    let newState = makeFullyPopulatedState()
    model.apply(newState)
    #expect(model.orbMood == HubModel.mood(for: newState))
    #expect(model.statusLine == HubModel.statusLine(for: newState))
    #expect(model.cards == HubModel.cards(for: newState))
  }

  @Test("apply moves the mood from attention back to healthy when the reason clears")
  func applyMovesTheMoodFromAttentionBackToHealthyWhenTheReasonClears() {
    let model = HubModel(state: makeAttentionState())
    #expect(model.orbMood == .idleAttention)
    let clearedState = makeHealthyScannedState()
    model.apply(clearedState)
    #expect(model.orbMood == .idleHealthy)
    #expect(model.statusLine == HubModel.statusLine(for: clearedState))
    #expect(model.cards == HubModel.cards(for: clearedState))
  }
}
