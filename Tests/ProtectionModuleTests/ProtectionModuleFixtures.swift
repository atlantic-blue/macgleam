import Foundation
import GleamCore
import ProtectionModule
import Testing
import os

/// Fixtures for the Protection module. The engine and the executor are
/// doubles: the module's whole job is deciding what to do with what they say,
/// and both of them are proved in their own suites.
enum ProtectionModuleFixture {
  struct Failure: Error {}

  static let sessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
  static let instant = Date(timeIntervalSince1970: 1_726_000_000)
  static let filesSeen: UInt64 = 4_321

  static func path(_ value: String) -> AbsolutePath {
    AbsolutePath(normalising: value)
  }

  static func malware() -> Finding {
    Finding(
      id: UUID(),
      sessionID: sessionID,
      category: .malware(signatureIdentifier: "MACOS.GENIEO.A"),
      entries: [PathEntry(path: path("/Users/gleam/Downloads/bad"), allocatedBytes: 4_096)],
      risk: .dangerous,
      explanation: "A fixture detection.",
      isPreselected: true)
  }

  static func adware() -> Finding {
    Finding(
      id: UUID(),
      sessionID: sessionID,
      category: .adwareLaunchItem,
      entries: [
        PathEntry(
          path: path("/Users/gleam/Library/LaunchAgents/com.adware.plist"), allocatedBytes: 512)
      ],
      risk: .dangerous,
      explanation: "A fixture detection.",
      isPreselected: true)
  }

  static func history() -> Finding {
    Finding(
      id: UUID(),
      sessionID: sessionID,
      category: .browserHistory(browser: "Safari"),
      entries: [
        PathEntry(path: path("/Users/gleam/Library/Safari/History.db"), allocatedBytes: 900)
      ],
      risk: .review,
      explanation: "A fixture trace.",
      isPreselected: false)
  }
}

/// A scan that yields exactly what the test scripted, and a plan built from
/// whatever was selected: one quarantine per detection path, one permanent
/// clear per trace path, which is what the real engine produces.
final class ScriptedProtectionEngine: ProtectionScanning, @unchecked Sendable {
  private let findings: [Finding]
  private let degraded: [String]
  private let failure: (any Error)?
  private let holdsOpen: Bool
  private let state = OSAllocatedUnfairLock(initialState: 0)

  init(
    findings: [Finding],
    degraded: [String] = [],
    failure: (any Error)? = nil,
    holdsOpen: Bool = false
  ) {
    self.findings = findings
    self.degraded = degraded
    self.failure = failure
    self.holdsOpen = holdsOpen
  }

  var scanCount: Int { state.withLock { $0 } }

  func scan(_ context: ScanContext) -> AsyncThrowingStream<ScanEvent, Error> {
    state.withLock { $0 += 1 }
    let findings = self.findings
    let degraded = self.degraded
    let failure = self.failure
    let holdsOpen = self.holdsOpen
    return AsyncThrowingStream { continuation in
      continuation.yield(.phase(.indeterminate))
      for sentence in degraded {
        continuation.yield(.degraded(unavailable: sentence))
      }
      if let failure {
        continuation.finish(throwing: failure)
        return
      }
      for finding in findings {
        continuation.yield(
          .finding(
            Finding(
              id: finding.id,
              sessionID: context.sessionID,
              category: finding.category,
              entries: finding.entries,
              risk: finding.risk,
              explanation: finding.explanation,
              isPreselected: finding.isPreselected)))
      }
      continuation.yield(
        .progress(
          ScanCounters(
            filesSeen: ProtectionModuleFixture.filesSeen, bytesReclaimable: 0, itemCount: 0)))
      continuation.yield(.phase(.settling))
      guard !holdsOpen else { return }
      continuation.finish()
    }
  }

  func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan {
    var operations: [GleamCore.Operation] = []
    var total: UInt64 = 0
    for finding in selection {
      for entry in finding.entries {
        total += entry.allocatedBytes
        operations.append(
          GleamCore.Operation(
            id: UUID(),
            findingID: finding.id,
            kind: Self.isTrace(finding.category)
              ? .deletePermanently(target: entry.path) : .quarantine(target: entry.path),
            privilege: .user))
      }
    }
    return OperationPlan(
      id: UUID(),
      sessionID: context.sessionID,
      operations: operations,
      totalBytes: total,
      permanentDeletionConfirmation: nil)
  }

  private static func isTrace(_ category: FindingCategory) -> Bool {
    switch category {
    case .browserHistory, .browserCookies, .browserSiteData, .recentItemsList,
      .wifiNetworkHistory:
      return true
    default:
      return false
    }
  }
}

/// An executor that reports every operation completing, or every one skipped
/// by the denylist, and records the plans it was handed.
final class ScriptedProtectionExecutor: PlanExecuting, @unchecked Sendable {
  private let skipsEverything: Bool
  private let state = OSAllocatedUnfairLock(initialState: [OperationPlan]())

  init(skipsEverything: Bool = false) {
    self.skipsEverything = skipsEverything
  }

  var executed: [OperationPlan] { state.withLock { $0 } }

  func execute(_ plan: OperationPlan) -> AsyncStream<ExecutionEvent> {
    state.withLock { $0.append(plan) }
    let skips = skipsEverything
    return AsyncStream { continuation in
      var results: [(operationID: UUID, result: OperationResult)] = []
      for operation in plan.operations {
        continuation.yield(.operationStarted(operationID: operation.id))
        let result: OperationResult =
          skips ? .skippedDenylisted : .completed(bytesReclaimed: 100)
        continuation.yield(.operationFinished(operationID: operation.id, result: result))
        results.append((operationID: operation.id, result: result))
      }
      continuation.yield(
        .planCompleted(
          ExecutionReport(
            planID: plan.id,
            results: results,
            bytesReclaimed: results.reduce(UInt64(0)) { total, entry in
              guard case .completed(let bytes) = entry.result else { return total }
              return total + bytes
            },
            startedAt: ProtectionModuleFixture.instant,
            finishedAt: ProtectionModuleFixture.instant)))
      continuation.finish()
    }
  }
}

struct ScriptedProtectionSessions: ProtectionSessionProviding {
  let fileSystem = InMemoryFileSystem()

  func makeScanContext(settings: Settings, hasFullDiskAccess: Bool) async -> ScanContext {
    ScanContext(
      sessionID: UUID(),
      fileSystem: fileSystem,
      rules: RuleCatalog(
        version: RuleCatalogVersion(value: 1),
        signature: Data(),
        cleanupRules: [],
        adwareRules: [],
        denylist: Denylist(patterns: [])),
      settings: settings,
      hasFullDiskAccess: hasFullDiskAccess)
  }

  func makePlanContext(sessionID: UUID, settings: Settings) async -> PlanContext {
    PlanContext(
      sessionID: sessionID,
      rules: RuleCatalog(
        version: RuleCatalogVersion(value: 1),
        signature: Data(),
        cleanupRules: [],
        adwareRules: [],
        denylist: Denylist(patterns: [])),
      settings: settings,
      ownership: HomeDirectoryOwnershipPolicy())
  }
}

actor ScriptedSettingsStore: SettingsStoring {
  private var settings = Settings.defaults

  func load() async -> Settings { settings }

  func save(_ updated: Settings) async throws { settings = updated }

  nonisolated func updates() -> AsyncStream<Settings> {
    AsyncStream { $0.finish() }
  }
}

@MainActor
struct ProtectionHarness {
  let engine: ScriptedProtectionEngine
  let executor: ScriptedProtectionExecutor
  let model: ProtectionModuleModel
}

@MainActor
func makeProtectionHarness(
  findings: [Finding],
  degraded: [String] = [],
  failsWith failure: (any Error)? = nil,
  skipsEverything: Bool = false,
  holdsOpen: Bool = false
) -> ProtectionHarness {
  let engine = ScriptedProtectionEngine(
    findings: findings, degraded: degraded, failure: failure, holdsOpen: holdsOpen)
  let executor = ScriptedProtectionExecutor(skipsEverything: skipsEverything)
  return ProtectionHarness(
    engine: engine,
    executor: executor,
    model: ProtectionModuleModel(
      engine: engine,
      executor: executor,
      settings: ScriptedSettingsStore(),
      sessions: ScriptedProtectionSessions()))
}

@MainActor
func reviewing(_ model: ProtectionModuleModel) -> ProtectionReviewState? {
  guard case .reviewing(let review) = model.state else { return nil }
  return review
}

@MainActor
func scanning(_ model: ProtectionModuleModel) -> Bool {
  if case .scanning = model.state { return true }
  return false
}

/// Waits for the model's asynchronous work to land. Every transition here is
/// driven by a task the model started, so a test that read the state
/// immediately would be reading the state before the work.
@MainActor
func settle(_ harness: ProtectionHarness) async {
  for _ in 0..<200 {
    await Task.yield()
    try? await Task.sleep(nanoseconds: 1_000_000)
    switch harness.model.state {
    case .idle, .reviewing, .result, .allClear:
      return
    case .scanning, .executing:
      continue
    }
  }
}

@MainActor
func expectEventually(
  _ what: String,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ condition: @MainActor () -> Bool
) async {
  for _ in 0..<200 {
    if condition() { return }
    await Task.yield()
    try? await Task.sleep(nanoseconds: 1_000_000)
  }
  Issue.record("\(what) never happened", sourceLocation: sourceLocation)
}
