import CleanupEngine
import CleanupModule
import Foundation
import FullSweepModule
import GleamCore
import LeftoversEngine
import PerformanceEngine

/// Builds the Full Sweep's live dependency graph: the three engines the sweep
/// composes, the executor they run through, and the model the hub reads its
/// orb from.
///
/// The engines are the same ones the modules use. A sweep is not a fourth
/// implementation of cleaning up; it is the three of them started at once.
@MainActor
enum FullSweepComposition {
  static func make(supply: RuleSupply, helpers: HelperSupply) -> FullSweepDependencies {
    let ownershipPolicy = HomeDirectoryOwnershipPolicy()
    let executor = CancellableCleanupExecutor(
      fileSystem: DiskFileSystem(),
      denylist: supply.rules.denylist,
      ownershipPolicy: ownershipPolicy,
      helpers: helpers)
    let orchestrator = FullSweepOrchestrator(engines: [
      .deepClean: CleanupEngine(),
      .storageDeclutter: LeftoversEngine(
        userHome: AbsolutePath(normalising: NSHomeDirectory()), referenceDate: Date()),
      .performanceBoost: PerformanceEngine(),
    ])
    let model = FullSweepModuleModel(
      orchestrator: orchestrator,
      executor: executor,
      settings: SettingsStore(directory: CleanupComposition.settingsDirectory()),
      sessions: LiveFullSweepSessionProvider(
        fileSystem: DiskFileSystem(), supply: supply, ownership: ownershipPolicy))
    return FullSweepDependencies(model: model, executor: executor)
  }
}

@MainActor
struct FullSweepDependencies {
  let model: FullSweepModuleModel
  let executor: CancellableCleanupExecutor
}

struct LiveFullSweepSessionProvider: FullSweepSessionProviding {
  let fileSystem: DiskFileSystem
  let supply: RuleSupply
  let ownership: any PathOwnershipPolicy

  func makeScanContext(settings: Settings, hasFullDiskAccess: Bool) async -> ScanContext {
    ScanContext(
      sessionID: UUID(),
      fileSystem: fileSystem,
      rules: supply.rules,
      settings: settings,
      hasFullDiskAccess: hasFullDiskAccess)
  }

  func makePlanContext(sessionID: UUID, settings: Settings) async -> PlanContext {
    PlanContext(
      sessionID: sessionID, rules: supply.rules, settings: settings, ownership: ownership)
  }
}
