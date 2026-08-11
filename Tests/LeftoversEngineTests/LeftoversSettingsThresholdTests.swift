import Foundation
import GleamCore
import LeftoversEngine
import Testing

@Suite("Leftovers scan: thresholds honour Settings")
struct LeftoversSettingsThresholdTests {

  @Test("lowering the large file threshold turns yesterday's non finding into a finding")
  func loweringTheLargeThresholdChangesWhatIsFound() async throws {
    let fileSystem = await LeftoversTree.seeded()
    let atThreshold = LeftoversFixture.path(LeftoversTree.largeExactlyAtThreshold)
    let oneByteUnder = LeftoversFixture.path(LeftoversTree.largeOneByteUnder)

    let strict = try await runLeftoversScan(
      rules: LeftoversTree.catalog(),
      over: fileSystem,
      settings: makeLeftoversSettings(largeFileThresholdBytes: LeftoversTree.largeThresholdBytes)
    )
    #expect(strict.pathSets(in: .largeFile) == [[atThreshold]])

    let relaxed = try await runLeftoversScan(
      rules: LeftoversTree.catalog(),
      over: fileSystem,
      settings: makeLeftoversSettings(
        largeFileThresholdBytes: LeftoversTree.largeThresholdBytes - 1)
    )
    #expect(relaxed.pathSets(in: .largeFile) == [[atThreshold], [oneByteUnder]])
  }

  @Test("lowering the old file threshold turns yesterday's non finding into a finding")
  func loweringTheOldThresholdChangesWhatIsFound() async throws {
    let fileSystem = await LeftoversTree.seeded()
    let oneDayNewer = LeftoversFixture.path(LeftoversTree.oldOneDayNewer)

    let strict = try await runLeftoversScan(
      rules: LeftoversTree.catalog(),
      over: fileSystem,
      settings: makeLeftoversSettings(oldFileThresholdDays: LeftoversTree.oldThresholdDays)
    )
    #expect(
      strict.findings(in: .oldFile).allSatisfy { !$0.paths.contains(oneDayNewer) })

    let relaxed = try await runLeftoversScan(
      rules: LeftoversTree.catalog(),
      over: fileSystem,
      settings: makeLeftoversSettings(oldFileThresholdDays: LeftoversTree.oldThresholdDays - 1)
    )
    #expect(
      relaxed.findings(in: .oldFile).contains { $0.paths.contains(oneDayNewer) })
  }
}
