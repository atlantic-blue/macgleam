import Foundation
import GleamHub
import Testing

@Suite("Hub status line")
struct HubStatusLineTests {

  static let representativeStates: [HubMachineState] = [
    makeEmptyFirstRunState(),
    makeHealthyScannedState(),
    makeAttentionState(),
    makeFullyPopulatedState(),
    makeHubMachineState(lastScanFinishedAt: fixedNow.addingTimeInterval(-86_400)),
    makeHubMachineState(reclaimableEstimateBytes: 500_000_000),
    makeHubMachineState(attentionReason: "One folder needs a look."),
  ]

  @Test(
    "the status line is never empty",
    arguments: representativeStates
  )
  func theStatusLineIsNeverEmpty(state: HubMachineState) {
    #expect(!HubModel.statusLine(for: state).isEmpty)
  }

  @Test("the empty first run state gets a non empty first scan invitation")
  func theEmptyFirstRunStateGetsANonEmptyFirstScanInvitation() {
    let line = HubModel.statusLine(for: makeEmptyFirstRunState())
    #expect(!line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  @Test("an attention state surfaces exactly the attention reason sentence")
  func anAttentionStateSurfacesExactlyTheAttentionReasonSentence() {
    let reason = "Your Trash has not been emptied in 60 days."
    let state = makeAttentionState(reason: reason)
    #expect(HubModel.statusLine(for: state) == reason)
  }

  @Test("a healthy status line reflects the reclaimable estimate")
  func aHealthyStatusLineReflectsTheReclaimableEstimate() {
    let smallEstimate = makeHealthyScannedState(reclaimableEstimateBytes: 5_000_000_000)
    let largeEstimate = makeHealthyScannedState(reclaimableEstimateBytes: 80_000_000_000)
    #expect(
      HubModel.statusLine(for: smallEstimate) != HubModel.statusLine(for: largeEstimate)
    )
  }

  @Test("a healthy status line reflects the last scan recency")
  func aHealthyStatusLineReflectsTheLastScanRecency() {
    let recentScan = makeHealthyScannedState(scanAge: 120)
    let staleScan = makeHealthyScannedState(scanAge: 45 * 86_400)
    #expect(
      HubModel.statusLine(for: recentScan) != HubModel.statusLine(for: staleScan)
    )
  }

  @Test("recency is reckoned against the state's now, not the wall clock")
  func recencyIsReckonedAgainstTheStatesNowNotTheWallClock() {
    // Two states with the same scan age and estimate, twenty years apart in
    // absolute time. If derivation only reads the state, the sentences match.
    let scanAge: TimeInterval = 3 * 3_600
    let estimate: UInt64 = 12_800_000_000
    let earlyEpoch = makeHealthyScannedState(
      scanAge: scanAge,
      reclaimableEstimateBytes: estimate,
      now: fixedNow
    )
    let lateEpoch = makeHealthyScannedState(
      scanAge: scanAge,
      reclaimableEstimateBytes: estimate,
      now: fixedNow.addingTimeInterval(20 * 365 * 86_400)
    )
    #expect(
      HubModel.statusLine(for: earlyEpoch) == HubModel.statusLine(for: lateEpoch)
    )
  }

  @Test("the same state value derived at different wall clock moments gives the same status line")
  func theSameStateValueDerivedAtDifferentWallClockMomentsGivesTheSameStatusLine() async throws {
    let state = makeHealthyScannedState()
    let earlierLine = HubModel.statusLine(for: state)
    try await Task.sleep(for: .milliseconds(50))
    #expect(HubModel.statusLine(for: state) == earlierLine)
  }

  @Test("status line derivation is deterministic across repeated calls on the same input")
  func statusLineDerivationIsDeterministicAcrossRepeatedCalls() {
    let state = makeFullyPopulatedState()
    let firstLine = HubModel.statusLine(for: state)
    for _ in 1...5 {
      #expect(HubModel.statusLine(for: state) == firstLine)
    }
  }
}
