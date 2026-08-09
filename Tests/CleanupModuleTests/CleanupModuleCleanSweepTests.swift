import CleanupModule
import Foundation
import GleamCore
import Testing

@MainActor
@Suite("Cleanup module clean sweep")
struct CleanupModuleCleanSweepTests {

  @Test("a scan that finds nothing lands the clean sweep naming the files checked")
  func aScanFindingNothingLandsTheCleanSweep() async {
    let harness = makeCleanupHarness()
    await reachCleanSweep(harness, filesChecked: 4_321)
    #expect(harness.model.state == .cleanSweep(filesChecked: 4_321))
    #expect(harness.model.hubEstimateBytes == 0)
  }

  @Test("acknowledging the clean sweep returns to idle")
  func acknowledgingTheCleanSweepReturnsToIdle() async {
    let harness = makeCleanupHarness()
    await reachCleanSweep(harness)
    harness.model.acknowledgeResult()
    #expect(harness.model.state == .idle)
  }

  @Test("a clean sweep after a real result zeroes the hub estimate")
  func aCleanSweepAfterAResultZeroesTheHubEstimate() async {
    let harness = makeCleanupHarness()
    _ = await reachResult(harness, bytesReclaimed: 1_000)
    harness.model.acknowledgeResult()
    #expect(harness.model.hubEstimateBytes == 1_000)

    await reachCleanSweep(harness, filesChecked: 77)
    #expect(harness.model.state == .cleanSweep(filesChecked: 77))
    #expect(harness.model.hubEstimateBytes == 0)
  }
}
