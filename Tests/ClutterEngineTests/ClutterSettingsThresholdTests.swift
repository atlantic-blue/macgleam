import ClutterEngine
import Foundation
import GleamCore
import Testing

@Suite("Clutter scan: thresholds honour Settings")
struct ClutterSettingsThresholdTests {

  @Test("lowering the large file threshold turns yesterday's non finding into a finding")
  func loweringTheLargeThresholdChangesWhatIsFound() async throws {
    let fileSystem = await ClutterTree.seeded()
    let atThreshold = ClutterFixture.path(ClutterTree.largeExactlyAtThreshold)
    let oneByteUnder = ClutterFixture.path(ClutterTree.largeOneByteUnder)

    let strict = try await runClutterScan(
      rules: ClutterTree.catalog(),
      over: fileSystem,
      settings: makeClutterSettings(largeFileThresholdBytes: ClutterTree.largeThresholdBytes)
    )
    #expect(strict.pathSets(in: .largeFile) == [[atThreshold]])

    let relaxed = try await runClutterScan(
      rules: ClutterTree.catalog(),
      over: fileSystem,
      settings: makeClutterSettings(
        largeFileThresholdBytes: ClutterTree.largeThresholdBytes - 1)
    )
    #expect(relaxed.pathSets(in: .largeFile) == [[atThreshold], [oneByteUnder]])
  }

  @Test("lowering the old file threshold turns yesterday's non finding into a finding")
  func loweringTheOldThresholdChangesWhatIsFound() async throws {
    let fileSystem = await ClutterTree.seeded()
    let oneDayNewer = ClutterFixture.path(ClutterTree.oldOneDayNewer)

    let strict = try await runClutterScan(
      rules: ClutterTree.catalog(),
      over: fileSystem,
      settings: makeClutterSettings(oldFileThresholdDays: ClutterTree.oldThresholdDays)
    )
    #expect(
      strict.findings(in: .oldFile).allSatisfy { !$0.paths.contains(oneDayNewer) })

    let relaxed = try await runClutterScan(
      rules: ClutterTree.catalog(),
      over: fileSystem,
      settings: makeClutterSettings(oldFileThresholdDays: ClutterTree.oldThresholdDays - 1)
    )
    #expect(
      relaxed.findings(in: .oldFile).contains { $0.paths.contains(oneDayNewer) })
  }
}
