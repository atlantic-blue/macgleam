import Foundation
import GleamCore
import Testing

@Suite("Settings")
struct SettingsTests {

  @Test("the default deletion mode is trash")
  func defaultDeletionModeIsTrash() {
    #expect(Settings.defaults.deletionMode == .trash)
  }

  @Test("deletion modes use their contract raw values")
  func deletionModesUseContractRawValues() {
    #expect(Settings.DeletionMode.trash.rawValue == "trash")
    #expect(Settings.DeletionMode.permanent.rawValue == "permanent")
  }

  @Test("the defaults round trip losslessly")
  func defaultsRoundTripLosslessly() throws {
    try expectLosslessRoundTrip(Settings.defaults)
  }

  @Test("customised settings round trip losslessly")
  func customisedSettingsRoundTripLosslessly() throws {
    let settings = makeSettings(
      deletionMode: .permanent,
      largeFileThresholdBytes: UInt64.max,
      oldFileThresholdDays: UInt32.max,
      reduceMotionOverride: true
    )
    try expectLosslessRoundTrip(settings)
  }

  @Test("zero thresholds round trip losslessly")
  func zeroThresholdsRoundTripLosslessly() throws {
    let settings = makeSettings(largeFileThresholdBytes: 0, oldFileThresholdDays: 0)
    try expectLosslessRoundTrip(settings)
  }

  @Test("the permanent deletion mode survives coding")
  func permanentDeletionModeSurvivesCoding() throws {
    let settings = makeSettings(deletionMode: .permanent)
    let encoded = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(Settings.self, from: encoded)
    #expect(decoded.deletionMode == .permanent)
  }
}

@Suite("MenuBarPreferences")
struct MenuBarPreferencesTests {

  @Test(
    "every toggle combination round trips losslessly",
    arguments: [false, true], [false, true]
  )
  func everyToggleCombinationRoundTrips(showsStorage: Bool, showsMemory: Bool) throws {
    let preferences = MenuBarPreferences(
      showsStorage: showsStorage,
      showsMemory: showsMemory,
      showsProcessorLoad: showsStorage != showsMemory
    )
    try expectLosslessRoundTrip(preferences)
  }
}

@Suite("MotionPreferences")
struct MotionPreferencesTests {

  @Test("an absent override round trips losslessly")
  func absentOverrideRoundTrips() throws {
    try expectLosslessRoundTrip(MotionPreferences(reduceMotionOverride: nil))
  }

  @Test("a forced reduced motion override round trips losslessly")
  func forcedOverrideRoundTrips() throws {
    try expectLosslessRoundTrip(MotionPreferences(reduceMotionOverride: true))
    try expectLosslessRoundTrip(MotionPreferences(reduceMotionOverride: false))
  }
}
