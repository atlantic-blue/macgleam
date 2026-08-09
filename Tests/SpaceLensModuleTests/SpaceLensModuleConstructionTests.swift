import Foundation
import GleamCore
import SpaceLensModule
import Testing

@Suite("Space lens module construction")
struct SpaceLensModuleConstructionTests {

  @Test("construction traps unless the engine is the space lens engine")
  func constructionTrapsOnAForeignEngine() async {
    await #expect(processExitsWith: .failure) {
      await MainActor.run {
        _ = SpaceLensModuleModel(
          engine: FakeSpaceLensMapProvider(module: .cleanup),
          executor: FakePlanExecutor(),
          settings: FakeSettingsStore(initial: LensModuleFixture.settings()),
          sessions: FakeSpaceLensSessionProvider(sessionIDs: [LensModuleFixture.sessionA]),
          access: FakeFullDiskAccessMonitor()
        )
      }
    }
  }

  @Test("a space lens engine constructs a model at idle with no failure notice")
  @MainActor
  func aSpaceLensEngineConstructsAModelAtIdle() {
    let harness = makeSpaceLensHarness()
    #expect(harness.model.state == .idle)
    #expect(harness.model.failureNotice == nil)
  }

  @Test("the model exposes no hub figure: space lens contributes nothing to the hub")
  @MainActor
  func modelExposesNoHubFigure() {
    let harness = makeSpaceLensHarness()
    let labels = Mirror(reflecting: harness.model).children.compactMap(\.label)
    #expect(!labels.contains { $0.lowercased().contains("hub") })
    #expect(!labels.contains { $0.lowercased().contains("estimate") })
  }
}
