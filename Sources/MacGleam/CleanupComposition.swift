import CleanupEngine
import CleanupModule
import Foundation
import GleamCore
import GleamHub
import os

/// Builds the cleanup module's live dependency graph: the real engine over
/// the real disk, the user domain executor, the settings store in Application
/// Support, and the onboarding model as the degraded provider.
@MainActor
enum CleanupComposition {
  static func make(onboarding: DiskAccessOnboardingModel) -> CleanupDependencies {
    let rules = loadRules()
    let ownershipPolicy = HomeDirectoryOwnershipPolicy()
    let executor = CancellableCleanupExecutor(
      fileSystem: DiskFileSystem(),
      denylist: rules.denylist,
      ownershipPolicy: ownershipPolicy,
      helpers: HelperSupply()
    )
    let model = CleanupModuleModel(
      engine: CleanupEngine(),
      executor: executor,
      settings: SettingsStore(directory: settingsDirectory()),
      sessions: LiveCleanupSessionProvider(
        fileSystem: DiskFileSystem(),
        rules: rules,
        ownership: ownershipPolicy
      ),
      degraded: OnboardingDegradedStateProvider(onboarding: onboarding)
    )
    return CleanupDependencies(
      model: model, executor: executor, presentation: CleanupPresentation())
  }

  /// A baseline that fails to load leaves an empty catalogue: scans find
  /// nothing rather than crash, and the failure is logged for diagnosis.
  static func loadRules() -> RuleCatalog {
    do {
      return try RuleCatalogBaseline.load()
    } catch {
      Logger(subsystem: "com.atlanticblue.macgleam", category: "cleanup")
        .error("The baseline rule catalogue failed to load: \(error)")
      return RuleCatalog(
        version: RuleCatalogVersion(value: 0),
        signature: Data(),
        cleanupRules: [],
        adwareRules: [],
        denylist: Denylist(patterns: [])
      )
    }
  }

  static func settingsDirectory() -> URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("MacGleam", isDirectory: true)
  }
}

@MainActor
struct CleanupDependencies {
  let model: CleanupModuleModel
  let executor: CancellableCleanupExecutor
  /// What the pane shows rather than what the module knows, so it outlives
  /// the pane the rail rebuilds (C37's module state slot).
  let presentation: CleanupPresentation
}

/// Mints one fresh session identifier per scan context, and plan contexts
/// bound to exactly the session they are asked for.
struct LiveCleanupSessionProvider: CleanupSessionProviding {
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

/// Adapts the onboarding model's step into the cleanup module's degraded
/// state. Undecided and declined both read as no access, with the honest
/// banner sentence naming what stays out of reach.
struct OnboardingDegradedStateProvider: CleanupDegradedStateProviding {
  let onboarding: DiskAccessOnboardingModel

  func current() async -> CleanupDegradedState {
    await MainActor.run {
      switch onboarding.step {
      case .granted:
        return CleanupDegradedState(hasFullDiskAccess: true, unavailable: [])
      case .degraded(let unavailable):
        return CleanupDegradedState(hasFullDiskAccess: false, unavailable: [unavailable])
      case .explanation:
        return CleanupDegradedState(
          hasFullDiskAccess: false,
          unavailable: [DiskAccessOnboardingModel.degradedBanner]
        )
      }
    }
  }
}

/// Wraps the PlanExecutor with the cancellation flag it polls
/// between operations. The view's cancel control raises the flag alongside
/// the model's `cancelExecution`, so cancellation lands between items and
/// the terminal report still arrives.
///
/// The executor is built per plan rather than once, because the helper it
/// routes privileged work to is one connection with one agreed contract
/// version, and a connection belongs to a run. Nothing is connected or
/// registered by building this: the helper supply hands over a client, and the
/// client reaches the system only when an operation genuinely needs privilege.
final class CancellableCleanupExecutor: PlanExecuting, Sendable {
  private let isCancellationRequested: OSAllocatedUnfairLock<Bool>
  private let fileSystem: DiskFileSystem
  private let denylist: Denylist
  private let ownershipPolicy: any PathOwnershipPolicy
  private let helpers: HelperSupply

  init(
    fileSystem: DiskFileSystem,
    denylist: Denylist,
    ownershipPolicy: any PathOwnershipPolicy,
    helpers: HelperSupply
  ) {
    self.isCancellationRequested = OSAllocatedUnfairLock(initialState: false)
    self.fileSystem = fileSystem
    self.denylist = denylist
    self.ownershipPolicy = ownershipPolicy
    self.helpers = helpers
  }

  func execute(_ plan: OperationPlan) -> AsyncStream<ExecutionEvent> {
    isCancellationRequested.withLock { $0 = false }
    return executorForOneRun().execute(plan)
  }

  func requestCancellation() {
    isCancellationRequested.withLock { $0 = true }
  }

  private func executorForOneRun() -> PlanExecutor {
    let flag = isCancellationRequested
    return PlanExecutor(
      fileSystem: fileSystem,
      denylist: denylist,
      helper: helpers.makeHelper(),
      ownershipPolicy: ownershipPolicy,
      environment: .current,
      now: { Date() },
      isCancelled: { flag.withLock { $0 } }
    )
  }
}
