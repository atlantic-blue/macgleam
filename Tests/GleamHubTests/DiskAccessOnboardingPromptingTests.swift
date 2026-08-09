import Foundation
import GleamHub
import Testing

@MainActor
@Suite("Disk access onboarding never prompts on a schedule")
struct DiskAccessOnboardingPromptingTests {

  @Test("repeated monitor emissions never open System Settings without a user action")
  func repeatedMonitorEmissionsNeverOpenSystemSettingsWithoutAUserAction() async {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    for _ in 0..<50 {
      monitor.emitGrantChange(true)
      monitor.emitGrantChange(false)
    }
    monitor.finishUpdates()
    await model.monitorUpdates()
    #expect(monitor.privacySettingsOpenCount == 0)
  }

  @Test("declining and waiting in degraded mode never opens System Settings")
  func decliningAndWaitingInDegradedModeNeverOpensSystemSettings() async {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    model.continueWithoutAccess()
    for _ in 0..<50 {
      monitor.emitGrantChange(false)
    }
    monitor.finishUpdates()
    await model.monitorUpdates()
    #expect(monitor.privacySettingsOpenCount == 0)
  }

  @Test("the flow opens System Settings exactly once per explicit user request")
  func theFlowOpensSystemSettingsExactlyOncePerExplicitUserRequest() {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    model.openSystemSettings()
    #expect(monitor.privacySettingsOpenCount == 1)
    model.openSystemSettings()
    #expect(monitor.privacySettingsOpenCount == 2)
  }

  @Test("asking to open System Settings does not change the flow step")
  func askingToOpenSystemSettingsDoesNotChangeTheFlowStep() {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    model.openSystemSettings()
    #expect(model.step == .explanation)
  }

  @Test("opening System Settings from degraded mode keeps the degraded banner")
  func openingSystemSettingsFromDegradedModeKeepsTheDegradedBanner() {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    model.continueWithoutAccess()
    let bannerBefore = degradedBanner(of: model.step)
    model.openSystemSettings()
    #expect(degradedBanner(of: model.step) == bannerBefore)
    #expect(degradedBanner(of: model.step) != nil)
  }
}
