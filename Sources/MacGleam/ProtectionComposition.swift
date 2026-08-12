import CleanupModule
import Foundation
import GleamCore
import ProtectionEngine
import ProtectionModule

/// Builds the Protection module's live dependency graph: the detection engine
/// over the real disk, the executor that routes through the SafetyNet, and the
/// store the SafetyNet screen reads.
///
/// One store for both, so what the module quarantines is what the screen
/// lists. The signature matcher is absent in this build, which the engine
/// reports as a degraded notice rather than implying it checked signatures.
@MainActor
enum ProtectionComposition {
  static func make(supply: RuleSupply, helpers: HelperSupply) -> ProtectionDependencies {
    let ownershipPolicy = HomeDirectoryOwnershipPolicy()
    let run = helpers.makeRun()
    let store = SafetyNetStore(
      directory: helpers.storeDirectory,
      fileSystem: DiskFileSystem(),
      denylist: supply.rules.denylist,
      ownership: ownershipPolicy,
      environment: .current,
      privileged: run.archiving,
      now: { Date() })
    let executor = CancellableCleanupExecutor(
      fileSystem: DiskFileSystem(),
      denylist: supply.rules.denylist,
      ownershipPolicy: ownershipPolicy,
      helpers: helpers)
    let model = ProtectionModuleModel(
      engine: ProtectionEngine(),
      executor: executor,
      settings: SettingsStore(directory: CleanupComposition.settingsDirectory()),
      sessions: LiveProtectionSessionProvider(
        fileSystem: DiskFileSystem(),
        supply: supply,
        ownership: ownershipPolicy))
    return ProtectionDependencies(
      model: model, executor: executor, safetyNet: SafetyNetModel(store: store))
  }
}

@MainActor
struct ProtectionDependencies {
  let model: ProtectionModuleModel
  let executor: CancellableCleanupExecutor
  let safetyNet: SafetyNetModel
}

/// Mints one fresh session identifier per scan, and plan contexts bound to
/// exactly the session they are asked for. The rules are read per session, so
/// a catalogue the channel published while the app was open is in force for
/// the next scan.
struct LiveProtectionSessionProvider: ProtectionSessionProviding {
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
