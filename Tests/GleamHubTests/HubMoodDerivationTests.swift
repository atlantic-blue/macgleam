import Foundation
import GleamHub
import Testing

@Suite("Hub mood derivation")
struct HubMoodDerivationTests {

  @Test("an attention reason derives idleAttention")
  func anAttentionReasonDerivesIdleAttention() {
    let state = makeAttentionState()
    #expect(HubModel.mood(for: state) == .idleAttention)
  }

  @Test("an attention reason derives idleAttention even on an otherwise healthy machine")
  func anAttentionReasonDerivesIdleAttentionEvenOnAnOtherwiseHealthyMachine() {
    let state = makeHubMachineState(
      lastScanFinishedAt: fixedNow.addingTimeInterval(-60),
      reclaimableEstimateBytes: 1_000_000,
      attentionReason: "One thing needs a look.",
      moduleFigures: makeFullModuleFigures(),
      enabledModules: Set(HubModule.allCases)
    )
    #expect(HubModel.mood(for: state) == .idleAttention)
  }

  @Test("no attention reason derives idleHealthy on the empty first run state")
  func noAttentionReasonDerivesIdleHealthyOnTheEmptyFirstRunState() {
    #expect(HubModel.mood(for: makeEmptyFirstRunState()) == .idleHealthy)
  }

  @Test("no attention reason derives idleHealthy with scan history and an estimate")
  func noAttentionReasonDerivesIdleHealthyWithScanHistoryAndAnEstimate() {
    #expect(HubModel.mood(for: makeHealthyScannedState()) == .idleHealthy)
  }

  @Test("mood derivation is deterministic across repeated calls on the same input")
  func moodDerivationIsDeterministicAcrossRepeatedCalls() {
    let attention = makeAttentionState()
    let healthy = makeHealthyScannedState()
    let firstAttentionMood = HubModel.mood(for: attention)
    let firstHealthyMood = HubModel.mood(for: healthy)
    for _ in 1...5 {
      #expect(HubModel.mood(for: attention) == firstAttentionMood)
      #expect(HubModel.mood(for: healthy) == firstHealthyMood)
    }
  }

  @Test("the same state value derived at different wall clock moments gives the same mood")
  func theSameStateValueDerivedAtDifferentWallClockMomentsGivesTheSameMood() async throws {
    let state = makeHealthyScannedState()
    let earlierMood = HubModel.mood(for: state)
    try await Task.sleep(for: .milliseconds(50))
    #expect(HubModel.mood(for: state) == earlierMood)
  }
}
