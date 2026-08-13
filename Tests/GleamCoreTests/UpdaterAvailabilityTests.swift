import Foundation
import GleamCore
import Testing

/// Whether a build is allowed to start its updater at all.
///
/// The decision is made here, before the framework is asked to start, because
/// an updater that fails to start puts a failure in front of somebody who can
/// do nothing about it. A build without a usable key has no updater, says so,
/// and offers nothing.
@Suite("Updater availability")
struct UpdaterAvailabilityTests {

  @Test("a build given no key has no updater")
  func noKeyMeansNoUpdater() {
    #expect(UpdaterAvailability.canUpdate(publicKey: nil) == false)
  }

  @Test(
    "a key that is blank has no updater",
    arguments: ["", " ", "\n", "\t "])
  func blankKeyMeansNoUpdater(key: String) {
    #expect(UpdaterAvailability.canUpdate(publicKey: key) == false)
  }

  @Test("the placeholder a build ships with is not a key")
  func thePlaceholderIsNotAKey() {
    #expect(
      UpdaterAvailability.canUpdate(publicKey: UpdaterAvailability.placeholder) == false,
      """
      the placeholder is what an unreleased build carries, and it is the exact \
      case this decision exists for
      """)
  }

  @Test(
    "text that is not base 64 is not a key",
    arguments: ["not a key at all", "????", "abc def"])
  func textThatIsNotBase64IsNotAKey(key: String) {
    #expect(UpdaterAvailability.canUpdate(publicKey: key) == false)
  }

  @Test(
    "a key of the wrong length is refused",
    arguments: [1, 16, 31, 33, 64])
  func aKeyOfTheWrongLengthIsRefused(count: Int) {
    let key = Data(repeating: 7, count: count).base64EncodedString()

    #expect(
      UpdaterAvailability.canUpdate(publicKey: key) == false,
      "a signing key is 32 bytes, and anything else would fail at the framework")
  }

  @Test("a real key of 32 bytes gives the build an updater")
  func aRealKeyGivesAnUpdater() {
    let key = Data(repeating: 7, count: 32).base64EncodedString()

    #expect(UpdaterAvailability.canUpdate(publicKey: key))
  }

  @Test("surrounding space does not spoil a real key")
  func surroundingSpaceDoesNotSpoilAKey() {
    let key = " \(Data(repeating: 7, count: 32).base64EncodedString())\n"

    #expect(UpdaterAvailability.canUpdate(publicKey: key))
  }

  @Test("a build with no updater says why rather than showing a failure")
  func aBuildWithNoUpdaterSaysWhy() {
    #expect(UpdaterAvailability.unavailableExplanation.isEmpty == false)
    #expect(
      UpdaterAvailability.unavailableExplanation.contains("update"),
      "the sentence is read by somebody in Settings, so it names what is missing")
  }

  @Test("a build that cannot update says so instead of a time")
  func aBuildThatCannotUpdateSaysSo() {
    let line = UpdatesSummary.line(isAvailable: false, lastCheck: "13 August 2026 at 10:41")

    #expect(
      line == UpdaterAvailability.unavailableExplanation,
      """
      a time here would read as a check that happened, and no check happened \
      or ever will in this build
      """)
  }

  @Test("a build that has never looked says that, rather than nothing")
  func aBuildThatNeverLookedSaysThat() {
    #expect(UpdatesSummary.line(isAvailable: true, lastCheck: nil) == "Not checked yet.")
  }

  @Test("a build that looked says when")
  func aBuildThatLookedSaysWhen() {
    let line = UpdatesSummary.line(isAvailable: true, lastCheck: "13 August 2026 at 10:41")

    #expect(line == "Last checked 13 August 2026 at 10:41.")
  }

  @Test("a build with no updater refuses to check")
  func aBuildWithNoUpdaterRefusesToCheck() async {
    let updater = UnavailableUpdater()

    #expect(
      updater.isAvailable == false,
      """
      the button that checks is drawn from this, so a build that cannot check \
      must not offer to
      """)
  }
}
