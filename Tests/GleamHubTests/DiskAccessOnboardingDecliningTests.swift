import Foundation
import GleamHub
import Testing

@MainActor
@Suite("Disk access onboarding declining")
struct DiskAccessOnboardingDecliningTests {

  @Test("continuing without access lands the flow in degraded mode")
  func continuingWithoutAccessLandsTheFlowInDegradedMode() {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    model.continueWithoutAccess()
    #expect(degradedBanner(of: model.step) != nil)
  }

  @Test("the degraded banner names mail attachments as unavailable")
  func theDegradedBannerNamesMailAttachmentsAsUnavailable() {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    model.continueWithoutAccess()
    let banner = degradedBanner(of: model.step) ?? ""
    #expect(banner.lowercased().contains("mail attachment"))
  }

  @Test("the degraded banner names trash bins as unavailable")
  func theDegradedBannerNamesTrashBinsAsUnavailable() {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    model.continueWithoutAccess()
    let banner = degradedBanner(of: model.step) ?? ""
    #expect(banner.lowercased().contains("trash bin"))
  }

  @Test("the degraded banner is a plain sentence, never empty")
  func theDegradedBannerIsAPlainSentenceNeverEmpty() {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    model.continueWithoutAccess()
    let banner = degradedBanner(of: model.step) ?? ""
    let trimmed = banner.trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(!trimmed.isEmpty)
    #expect(trimmed == banner)
    #expect(banner.hasSuffix("."))
  }

  @Test("continuing without access after the grant landed leaves the flow granted")
  func continuingWithoutAccessAfterTheGrantLandedLeavesTheFlowGranted() async {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    monitor.emitGrantChange(true)
    monitor.finishUpdates()
    await model.monitorUpdates()
    model.continueWithoutAccess()
    #expect(model.step == .granted)
  }
}
