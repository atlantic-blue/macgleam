import Foundation
import GleamHub
import Testing

/// What the orb does while a sweep runs, and what the status line says.
///
/// The three active moods existed from the first slice and nothing could reach
/// them: the hub only knew about a machine at rest. This is the input that
/// reaches them, and these pin that a sweep in progress is the one thing the
/// orb reports while it is happening.
@Suite("Hub sweep activity")
struct HubSweepActivityTests {

  private func state(
    sweep: HubSweepActivity?,
    attention: String? = nil
  ) -> HubMachineState {
    HubMachineState(
      lastScanFinishedAt: nil,
      reclaimableEstimateBytes: nil,
      attentionReason: attention,
      moduleFigures: [:],
      enabledModules: [],
      sweepActivity: sweep,
      now: Date(timeIntervalSince1970: 1_726_000_000))
  }

  @Test("a sweep in progress makes the orb scan")
  func aSweepInProgressMakesTheOrbScan() {
    #expect(HubModel.mood(for: state(sweep: .scanning(bytesReclaimable: 0))) == .scanning)
  }

  @Test("a sweep with something to show makes the orb pulse")
  func aSweepWithSomethingToShowMakesTheOrbPulse() {
    #expect(
      HubModel.mood(for: state(sweep: .result(bytesReclaimable: 1_000, issueCount: 3)))
        == .result)
  }

  @Test("a sweep that found nothing makes the orb bloom")
  func aSweepThatFoundNothingMakesTheOrbBloom() {
    #expect(HubModel.mood(for: state(sweep: .cleanSweep)) == .cleanSweep)
  }

  @Test("a sweep in progress outranks an attention reason, because it is what is happening")
  func aSweepInProgressOutranksAnAttentionReason() {
    let scanning = state(sweep: .scanning(bytesReclaimable: 0), attention: "Something is wrong.")
    #expect(HubModel.mood(for: scanning) == .scanning)
  }

  @Test("with no sweep the moods are exactly what they were")
  func withNoSweepTheMoodsAreWhatTheyWere() {
    #expect(HubModel.mood(for: state(sweep: nil)) == .idleHealthy)
    #expect(HubModel.mood(for: state(sweep: nil, attention: "Something.")) == .idleAttention)
  }

  // MARK: - What it says

  @Test("a running sweep says what it has found so far")
  func aRunningSweepSaysWhatItHasFound() {
    let line = HubModel.statusLine(for: state(sweep: .scanning(bytesReclaimable: 2_000_000)))
    #expect(line.contains("Checking"))
    #expect(line.contains("2 MB"))
  }

  @Test("a running sweep with nothing yet does not put a zero on screen")
  func aRunningSweepWithNothingYetShowsNoZero() {
    let line = HubModel.statusLine(for: state(sweep: .scanning(bytesReclaimable: 0)))
    #expect(!line.contains("0"))
  }

  @Test("a finished sweep says how many things and how much")
  func aFinishedSweepSaysHowManyAndHowMuch() {
    let line = HubModel.statusLine(
      for: state(sweep: .result(bytesReclaimable: 3_000_000, issueCount: 4)))
    #expect(line.contains("4 things"))
    #expect(line.contains("3 MB"))
  }

  @Test("one thing is one thing rather than 1 things")
  func oneThingIsOneThing() {
    let line = HubModel.statusLine(
      for: state(sweep: .result(bytesReclaimable: 1_000, issueCount: 1)))
    #expect(line.contains("1 thing to deal with"))
    #expect(!line.contains("1 things"))
  }

  @Test("a clean sweep says so rather than showing a zero")
  func aCleanSweepSaysSo() {
    let line = HubModel.statusLine(for: state(sweep: .cleanSweep))
    #expect(!line.contains("0"))
    #expect(line.contains("good shape"))
  }

  @Test("every status line is a full sentence, whatever the sweep is doing")
  func everyStatusLineIsAFullSentence() {
    for activity in [
      HubSweepActivity.scanning(bytesReclaimable: 0),
      .scanning(bytesReclaimable: 1_500),
      .result(bytesReclaimable: 0, issueCount: 0),
      .result(bytesReclaimable: 9_000, issueCount: 12),
      .cleanSweep,
    ] {
      let line = HubModel.statusLine(for: state(sweep: activity))
      #expect(!line.isEmpty)
      #expect(line.hasSuffix("."))
    }
  }

  // MARK: - The appearance the mood resolves to

  @Test("Reduce Motion never leaves a spring in a sweep's appearance")
  func reduceMotionNeverLeavesASpring() {
    for mood in [OrbMood.scanning, .result, .cleanSweep] {
      let appearance = OrbAppearanceResolver.appearance(for: mood, reduceMotion: true)
      switch appearance {
      case .breathing, .resultPulse:
        Issue.record("\(mood) resolves to a spring with Reduce Motion on")
      case .determinateRing, .staticGradient, .shimmerBand, .lustreBloom:
        continue
      }
    }
  }

  @Test("a scanning sweep under Reduce Motion is a determinate ring rather than a shimmer")
  func scanningUnderReduceMotionIsADeterminateRing() {
    #expect(
      OrbAppearanceResolver.appearance(for: .scanning, reduceMotion: true) == .determinateRing)
  }
}
