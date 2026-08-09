import Foundation
import GleamHub
import Testing

@MainActor
@Suite("Disk access onboarding flow advancement")
struct DiskAccessOnboardingFlowAdvancementTests {

  @Test("a fresh flow with no grant shows the explanation step")
  func aFreshFlowWithNoGrantShowsTheExplanationStep() {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    #expect(model.step == .explanation)
  }

  @Test("the flow advances to granted by itself when the monitor emits the grant")
  func theFlowAdvancesToGrantedByItselfWhenTheMonitorEmitsTheGrant() async {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    monitor.emitGrantChange(true)
    monitor.finishUpdates()
    await model.monitorUpdates()
    #expect(model.step == .granted)
  }

  @Test("a grant already present when monitoring starts advances the flow without any emission")
  func aGrantAlreadyPresentWhenMonitoringStartsAdvancesTheFlowWithoutAnyEmission() async {
    let monitor = FakeFullDiskAccessMonitor(isGranted: true)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    monitor.finishUpdates()
    await model.monitorUpdates()
    #expect(model.step == .granted)
  }

  @Test("an ungranted monitor whose stream ends leaves the flow on the explanation step")
  func anUngrantedMonitorWhoseStreamEndsLeavesTheFlowOnTheExplanationStep() async {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    monitor.finishUpdates()
    await model.monitorUpdates()
    #expect(model.step == .explanation)
  }

  @Test("a redundant ungranted emission leaves the explanation step unchanged")
  func aRedundantUngrantedEmissionLeavesTheExplanationStepUnchanged() async {
    let monitor = FakeFullDiskAccessMonitor(isGranted: false)
    let model = DiskAccessOnboardingModel(monitor: monitor)
    monitor.emitGrantChange(false)
    monitor.emitGrantChange(false)
    monitor.finishUpdates()
    await model.monitorUpdates()
    #expect(model.step == .explanation)
  }
}
