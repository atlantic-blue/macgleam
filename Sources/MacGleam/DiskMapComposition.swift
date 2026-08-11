import CleanupModule
import DiskMapEngine
import DiskMapModule
import Foundation
import GleamCore

/// Builds the Disk Map surface's live dependency graph: the streaming map
/// engine over the real disk, the user domain executor, the shared settings
/// store and the real Full Disk Access monitor.
@MainActor
enum DiskMapComposition {
  static func make() -> DiskMapDependencies {
    let rules = CleanupComposition.loadRules()
    let ownershipPolicy = HomeDirectoryOwnershipPolicy()
    let executor = CancellableCleanupExecutor(
      fileSystem: DiskFileSystem(),
      denylist: rules.denylist,
      ownershipPolicy: ownershipPolicy,
      helpers: HelperSupply()
    )
    let model = DiskMapModuleModel(
      engine: DiskMapEngine(),
      executor: executor,
      settings: SettingsStore(directory: CleanupComposition.settingsDirectory()),
      sessions: LiveDiskMapSessionProvider(
        fileSystem: DiskFileSystem(),
        rules: rules,
        ownership: ownershipPolicy
      ),
      access: RealFullDiskAccessMonitor()
    )
    return DiskMapDependencies(model: model, executor: executor)
  }
}

@MainActor
struct DiskMapDependencies {
  let model: DiskMapModuleModel
  let executor: CancellableCleanupExecutor
}

/// Mints one fresh session identifier per map context, and plan contexts
/// bound to exactly the session they are asked for.
struct LiveDiskMapSessionProvider: DiskMapSessionProviding {
  let fileSystem: DiskFileSystem
  let rules: RuleCatalog
  let ownership: any PathOwnershipPolicy

  func makeScanContext(settings: Settings, hasFullDiskAccess: Bool) async -> ScanContext {
    ScanContext(
      sessionID: UUID(),
      fileSystem: fileSystem,
      rules: rules,
      settings: settings,
      hasFullDiskAccess: hasFullDiskAccess
    )
  }

  func makePlanContext(sessionID: UUID, settings: Settings) async -> PlanContext {
    PlanContext(sessionID: sessionID, rules: rules, settings: settings, ownership: ownership)
  }
}
