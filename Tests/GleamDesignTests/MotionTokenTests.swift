import GleamDesign
import SwiftUI
import Testing

@Suite("Motion token values")
struct MotionTokenValueTests {

  @Test("snappy spring locks response 0.30 and damping 0.85")
  func snappySpringLocksItsContractValues() {
    #expect(GleamSpring.snappy.response == 0.30)
    #expect(GleamSpring.snappy.dampingFraction == 0.85)
  }

  @Test("gentle spring locks response 0.55 and damping 0.90")
  func gentleSpringLocksItsContractValues() {
    #expect(GleamSpring.gentle.response == 0.55)
    #expect(GleamSpring.gentle.dampingFraction == 0.90)
  }

  @Test("lively spring locks response 0.40 and damping 0.70")
  func livelySpringLocksItsContractValues() {
    #expect(GleamSpring.lively.response == 0.40)
    #expect(GleamSpring.lively.dampingFraction == 0.70)
  }

  @Test("micro fade lasts exactly 150 milliseconds")
  func microFadeLastsExactlyOneHundredAndFiftyMilliseconds() {
    #expect(GleamFade.micro.duration == .milliseconds(150))
  }

  @Test("standard fade lasts exactly 250 milliseconds")
  func standardFadeLastsExactlyTwoHundredAndFiftyMilliseconds() {
    #expect(GleamFade.standard.duration == .milliseconds(250))
  }
}

@Suite("Reduce Motion mapping")
struct ReduceMotionMappingTests {

  @Test(
    "reduce motion resolves every spring to the standard crossfade",
    arguments: GleamSpring.allCases
  )
  func reduceMotionResolvesEverySpringToTheStandardCrossfade(spring: GleamSpring) {
    #expect(spring.animation(reduceMotion: true) == .easeInOut(duration: 0.25))
  }

  @Test(
    "reduce motion never returns a spring animation",
    arguments: GleamSpring.allCases
  )
  func reduceMotionNeverReturnsASpringAnimation(spring: GleamSpring) {
    let springAnimation = Animation.spring(
      response: spring.response,
      dampingFraction: spring.dampingFraction
    )
    #expect(spring.animation(reduceMotion: true) != springAnimation)
  }

  @Test(
    "with reduce motion off every token returns its own spring animation",
    arguments: GleamSpring.allCases
  )
  func withReduceMotionOffEveryTokenReturnsItsOwnSpringAnimation(spring: GleamSpring) {
    let springAnimation = Animation.spring(
      response: spring.response,
      dampingFraction: spring.dampingFraction
    )
    #expect(spring.animation(reduceMotion: false) == springAnimation)
  }
}
