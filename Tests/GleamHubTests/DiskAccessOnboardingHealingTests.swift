import Foundation
import GleamHub
import Testing

@MainActor
@Suite("Disk access onboarding healing and revocation")
struct DiskAccessOnboardingHealingTests {

  @Test("a grant arriving in degraded mode moves the flow to granted")
  func aGrantArrivingInDegradedModeMovesTheFlowToGranted() async {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    model.continueWithoutAccess()
    monitor.emitGrantChange(true)
    monitor.finishUpdates()
    await model.monitorUpdates()
    #expect(model.step == .granted)
  }

  @Test("healing clears the degraded banner")
  func healingClearsTheDegradedBanner() async {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    model.continueWithoutAccess()
    monitor.emitGrantChange(true)
    monitor.finishUpdates()
    await model.monitorUpdates()
    #expect(degradedBanner(of: model.step) == nil)
  }

  @Test("the grant being revoked after granted returns the flow to degraded with the banner")
  func theGrantBeingRevokedAfterGrantedReturnsTheFlowToDegradedWithTheBanner() async {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    monitor.emitGrantChange(true)
    monitor.emitGrantChange(false)
    monitor.finishUpdates()
    await model.monitorUpdates()
    let banner = degradedBanner(of: model.step) ?? ""
    #expect(banner.lowercased().contains("mail attachment"))
    #expect(banner.lowercased().contains("trash bin"))
  }

  @Test("revocation never opens System Settings by itself")
  func revocationNeverOpensSystemSettingsByItself() async {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    monitor.emitGrantChange(true)
    monitor.emitGrantChange(false)
    monitor.finishUpdates()
    await model.monitorUpdates()
    #expect(monitor.privacySettingsOpenCount == 0)
  }
}
