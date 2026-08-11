import DiskMapModule
import Foundation
import GleamCore
import Testing

@Suite("Space lens module construction")
struct DiskMapModuleConstructionTests {

  @Test("construction traps unless the engine is the disk map engine")
  func constructionTrapsOnAForeignEngine() async {
    await #expect(processExitsWith: .failure) {
      await MainActor.run {
        _ = DiskMapModuleModel(
          engine: FakeDiskMapMapProvider(module: .cleanup),
          executor: FakePlanExecutor(),
          settings: FakeSettingsStore(initial: LensModuleFixture.settings()),
          sessions: FakeDiskMapSessionProvider(sessionIDs: [LensModuleFixture.sessionA]),
          access: FakeFullDiskAccessMonitor()
        )
      }
    }
  }

  @Test("a disk map engine constructs a model at idle with no failure notice")
  @MainActor
  func aDiskMapEngineConstructsAModelAtIdle() {
    let harness = makeDiskMapHarness()
    #expect(harness.model.state == .idle)
    #expect(harness.model.failureNotice == nil)
  }

  @Test("the model exposes no hub figure: disk map contributes nothing to the hub")
  @MainActor
  func modelExposesNoHubFigure() {
    let harness = makeDiskMapHarness()
    let labels = Mirror(reflecting: harness.model).children.compactMap(\.label)
    #expect(!labels.contains { $0.lowercased().contains("hub") })
    #expect(!labels.contains { $0.lowercased().contains("estimate") })
  }
}
