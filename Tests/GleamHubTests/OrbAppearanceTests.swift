import Foundation
import GleamDesign
import GleamHub
import Testing

private func isBreathing(_ appearance: OrbAppearance) -> Bool {
  if case .breathing = appearance { return true }
  return false
}

private func isResultPulse(_ appearance: OrbAppearance) -> Bool {
  if case .resultPulse = appearance { return true }
  return false
}

private func sheen(of appearance: OrbAppearance) -> OrbSheen? {
  switch appearance {
  case .breathing(_, _, let sheen): return sheen
  case .staticGradient(let sheen, _): return sheen
  case .shimmerBand, .determinateRing, .resultPulse, .lustreBloom: return nil
  }
}

@Suite("Orb appearance resolver")
struct OrbAppearanceResolverTests {

  @Test(
    "the resolver is total and deterministic over every mood and reduce motion pair",
    arguments: OrbMood.allCases, [false, true]
  )
  func theResolverIsTotalAndDeterministicOverEveryMoodAndReduceMotionPair(
    mood: OrbMood,
    reduceMotion: Bool
  ) {
    let first = OrbAppearanceResolver.appearance(for: mood, reduceMotion: reduceMotion)
    let second = OrbAppearanceResolver.appearance(for: mood, reduceMotion: reduceMotion)
    #expect(first == second)
  }

  @Test(
    "idleHealthy full motion breathes with a period of exactly six seconds and the iridescent sheen"
  )
  func idleHealthyFullMotionBreathesAtExactlySixSecondsWithTheIridescentSheen() {
    let appearance = OrbAppearanceResolver.appearance(for: .idleHealthy, reduceMotion: false)
    guard case .breathing(_, let period, let sheen) = appearance else {
      Issue.record("expected breathing, got \(appearance)")
      return
    }
    #expect(period == .seconds(6))
    #expect(sheen == .iridescent)
  }

  @Test(
    "idleAttention full motion breathes strictly faster than six seconds with the warmedToReview sheen"
  )
  func idleAttentionFullMotionBreathesStrictlyFasterThanSixSecondsWithTheWarmedToReviewSheen() {
    let appearance = OrbAppearanceResolver.appearance(for: .idleAttention, reduceMotion: false)
    guard case .breathing(_, let period, let sheen) = appearance else {
      Issue.record("expected breathing, got \(appearance)")
      return
    }
    #expect(period < .seconds(6))
    #expect(sheen == .warmedToReview)
  }

  @Test("scanning full motion is the shimmer band")
  func scanningFullMotionIsTheShimmerBand() {
    #expect(
      OrbAppearanceResolver.appearance(for: .scanning, reduceMotion: false) == .shimmerBand
    )
  }

  @Test("result full motion is one pulse with the lively spring")
  func resultFullMotionIsOnePulseWithTheLivelySpring() {
    #expect(
      OrbAppearanceResolver.appearance(for: .result, reduceMotion: false)
        == .resultPulse(spring: .lively)
    )
  }

  @Test("cleanSweep full motion is the lustre bloom")
  func cleanSweepFullMotionIsTheLustreBloom() {
    #expect(
      OrbAppearanceResolver.appearance(for: .cleanSweep, reduceMotion: false) == .lustreBloom
    )
  }
}

@Suite("Orb appearance under Reduce Motion")
struct OrbAppearanceReduceMotionTests {

  @Test(
    "reduce motion never yields breathing for any mood",
    arguments: OrbMood.allCases
  )
  func reduceMotionNeverYieldsBreathingForAnyMood(mood: OrbMood) {
    let appearance = OrbAppearanceResolver.appearance(for: mood, reduceMotion: true)
    #expect(!isBreathing(appearance))
  }

  @Test(
    "reduce motion never yields a result pulse for any mood",
    arguments: OrbMood.allCases
  )
  func reduceMotionNeverYieldsAResultPulseForAnyMood(mood: OrbMood) {
    let appearance = OrbAppearanceResolver.appearance(for: mood, reduceMotion: true)
    #expect(!isResultPulse(appearance))
  }

  @Test("scanning under reduce motion is the determinate ring")
  func scanningUnderReduceMotionIsTheDeterminateRing() {
    #expect(
      OrbAppearanceResolver.appearance(for: .scanning, reduceMotion: true) == .determinateRing
    )
  }

  @Test(
    "every non scanning mood under reduce motion is a static gradient carrying the standard fade",
    arguments: OrbMood.allCases.filter { $0 != .scanning }
  )
  func everyNonScanningMoodUnderReduceMotionIsAStaticGradientCarryingTheStandardFade(
    mood: OrbMood
  ) {
    let appearance = OrbAppearanceResolver.appearance(for: mood, reduceMotion: true)
    guard case .staticGradient(_, let moodChangeFade) = appearance else {
      Issue.record("expected staticGradient for \(mood), got \(appearance)")
      return
    }
    #expect(moodChangeFade == GleamFade.standard)
  }

  @Test("idleHealthy under reduce motion keeps the iridescent sheen")
  func idleHealthyUnderReduceMotionKeepsTheIridescentSheen() {
    let appearance = OrbAppearanceResolver.appearance(for: .idleHealthy, reduceMotion: true)
    #expect(sheen(of: appearance) == .iridescent)
  }

  @Test("idleAttention under reduce motion keeps the warmedToReview sheen")
  func idleAttentionUnderReduceMotionKeepsTheWarmedToReviewSheen() {
    let appearance = OrbAppearanceResolver.appearance(for: .idleAttention, reduceMotion: true)
    #expect(sheen(of: appearance) == .warmedToReview)
  }
}

@Suite("Orb sheen never turns dangerous")
struct OrbSheenNeverTurnsDangerousTests {

  @Test("the sheen cases are exactly iridescent and warmedToReview")
  func theSheenCasesAreExactlyIridescentAndWarmedToReview() {
    #expect(OrbSheen(rawValue: "iridescent") == OrbSheen.iridescent)
    #expect(OrbSheen(rawValue: "warmedToReview") == OrbSheen.warmedToReview)
    for forbiddenName in ["dangerous", "alarmed", "red", "critical", "alert"] {
      #expect(OrbSheen(rawValue: forbiddenName) == nil)
    }
  }

  @Test(
    "every sheen the resolver returns is one of the two calm sheens",
    arguments: OrbMood.allCases, [false, true]
  )
  func everySheenTheResolverReturnsIsOneOfTheTwoCalmSheens(
    mood: OrbMood,
    reduceMotion: Bool
  ) {
    let appearance = OrbAppearanceResolver.appearance(for: mood, reduceMotion: reduceMotion)
    if let sheen = sheen(of: appearance) {
      #expect(sheen == .iridescent || sheen == .warmedToReview)
    }
  }
}
