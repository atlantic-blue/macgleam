import CleanupModule
import Foundation
import GleamCore
import Testing

@Suite("Cleanup module construction")
struct CleanupModuleConstructionTests {

  @Test("construction traps unless the engine is the cleanup engine")
  func constructionTrapsOnAForeignEngine() async {
    await #expect(processExitsWith: .failure) {
      await MainActor.run {
        _ = CleanupModuleModel(
          engine: FakeCleanupEngine(module: .leftovers),
          executor: FakePlanExecutor(),
          settings: FakeSettingsStore(initial: ModuleFixture.settings()),
          sessions: FakeCleanupSessionProvider(sessionIDs: [ModuleFixture.sessionA]),
          degraded: FakeDegradedStateProvider(state: ModuleFixture.fullAccess)
        )
      }
    }
  }

  @Test("a cleanup engine constructs a model at idle with a zero estimate")
  @MainActor
  func aCleanupEngineConstructsAModelAtIdle() {
    let harness = makeCleanupHarness()
    #expect(harness.model.state == .idle)
    #expect(harness.model.hubEstimateBytes == 0)
    #expect(harness.model.degradedNotices.isEmpty)
    #expect(harness.model.failureNotice == nil)
  }
}
