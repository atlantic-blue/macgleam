import CleanupModule
import Foundation
import GleamCore
import SpaceLensEngine
import SpaceLensModule

/// Builds the Space Lens surface's live dependency graph: the streaming map
/// engine over the real disk, the user domain executor, the shared settings
/// store and the real Full Disk Access monitor.
@MainActor
enum SpaceLensComposition {
  static func make() -> SpaceLensDependencies {
    let rules = CleanupComposition.loadRules()
    let ownershipPolicy = HomeDirectoryOwnershipPolicy()
    let executor = CancellableCleanupExecutor(
      fileSystem: DiskFileSystem(),
      denylist: rules.denylist,
      ownershipPolicy: ownershipPolicy
    )
    let model = SpaceLensModuleModel(
      engine: SpaceLensEngine(),
      executor: executor,
      settings: SettingsStore(directory: CleanupComposition.settingsDirectory()),
      sessions: LiveSpaceLensSessionProvider(
        fileSystem: DiskFileSystem(),
        rules: rules,
        ownership: ownershipPolicy
      ),
      access: RealFullDiskAccessMonitor()
    )
    return SpaceLensDependencies(model: model, executor: executor)
  }
}

@MainActor
struct SpaceLensDependencies {
  let model: SpaceLensModuleModel
  let executor: CancellableCleanupExecutor
}

/// Mints one fresh session identifier per map context, and plan contexts
/// bound to exactly the session they are asked for.
struct LiveSpaceLensSessionProvider: SpaceLensSessionProviding {
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
