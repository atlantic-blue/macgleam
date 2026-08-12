import Foundation
import GleamCore
import Testing
import os

/// Fixtures for the Full Sweep. The engines are doubles: each of them is
/// proved in its own suite, and what this suite is about is what the
/// orchestrator does with three of them at once.
enum SweepFixture {
  struct Failure: Error, LocalizedError {
    var errorDescription: String? { "The disk could not be read." }
  }

  static let sessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!

  static func path(_ value: String) -> AbsolutePath {
    AbsolutePath(normalising: value)
  }

  static func scanContext() -> ScanContext {
    ScanContext(
      sessionID: sessionID,
      fileSystem: InMemoryFileSystem(),
      rules: catalog(),
      settings: Settings.defaults,
      hasFullDiskAccess: true)
  }

  static func planContext() -> PlanContext {
    PlanContext(
      sessionID: sessionID,
      rules: catalog(),
      settings: Settings.defaults,
      ownership: HomeDirectoryOwnershipPolicy())
  }

  static func catalog() -> RuleCatalog {
    RuleCatalog(
      version: RuleCatalogVersion(value: 1),
      signature: Data(),
      cleanupRules: [],
      adwareRules: [],
      denylist: Denylist(patterns: []))
  }

  static func finding(
    category: FindingCategory,
    path value: String = "/Users/gleam/Library/Caches/thing",
    bytes: UInt64 = 1_024,
    isPreselected: Bool = true,
    sessionID: UUID = SweepFixture.sessionID
  ) -> Finding {
    Finding(
      id: UUID(),
      sessionID: sessionID,
      category: category,
      entries: [PathEntry(path: path(value), allocatedBytes: bytes)],
      risk: .safe,
      explanation: "A fixture row.",
      isPreselected: isPreselected)
  }

  static func cache(sessionID: UUID = SweepFixture.sessionID) -> Finding {
    finding(category: .userCache, path: "/Users/gleam/Library/Caches/one", sessionID: sessionID)
  }

  static func log() -> Finding {
    finding(category: .log, path: "/Users/gleam/Library/Logs/two", bytes: 2_048)
  }

  static func largeFile() -> Finding {
    finding(
      category: .largeFile,
      path: "/Users/gleam/Movies/film.mov",
      bytes: 4_096,
      isPreselected: false)
  }

  static func maintenance(task: MaintenanceTask = .purgeMemoryPressure) -> Finding {
    Finding(
      id: UUID(),
      sessionID: sessionID,
      category: .maintenanceTask(task: task),
      entries: [],
      risk: .safe,
      explanation: "A fixture task.",
      isPreselected: false)
  }

  /// An engine that yields exactly what it was scripted, and plans one
  /// operation per selected row, which is what every real engine does at this
  /// boundary.
  static func engine(
    module: GleamModule,
    findings: [Finding],
    failsWith failure: (any Error)? = nil,
    gate: StartGate? = nil
  ) -> ScriptedSweepEngine {
    ScriptedSweepEngine(module: module, findings: findings, failure: failure, gate: gate)
  }
}

struct ScriptedSweepEngine: GleamEngine {
  let module: GleamModule
  let findings: [Finding]
  let failure: (any Error)?
  let gate: StartGate?

  func scan(_ context: ScanContext) -> AsyncThrowingStream<ScanEvent, Error> {
    let findings = self.findings
    let failure = self.failure
    let gate = self.gate
    return AsyncThrowingStream { continuation in
      let work = Task {
        // When a gate is present, no engine yields until all of them have
        // started, so a sequential orchestrator never finishes.
        if let gate {
          await gate.arriveAndWait()
        }
        continuation.yield(.phase(.indeterminate))
        if let failure {
          continuation.finish(throwing: failure)
          return
        }
        for finding in findings {
          continuation.yield(.finding(finding))
        }
        continuation.yield(.phase(.settling))
        continuation.finish()
      }
      continuation.onTermination = { _ in work.cancel() }
    }
  }

  func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan {
    OperationPlan(
      id: UUID(),
      sessionID: context.sessionID,
      operations: selection.map { finding in
        GleamCore.Operation(
          id: UUID(),
          findingID: finding.id,
          kind: finding.paths.first.map { GleamCore.Operation.Kind.moveToTrash(target: $0) }
            ?? .runMaintenance(task: .purgeMemoryPressure),
          privilege: .user)
      },
      totalBytes: selection.reduce(0) { $0 + $1.byteSize },
      permanentDeletionConfirmation: nil)
  }
}

/// A gate every job passes through before any of them may yield. It is how
/// concurrency is asserted without a clock: run the jobs one after another and
/// the first one waits forever.
actor StartGate {
  private let expected: Int
  private var arrived = 0
  private var waiting: [CheckedContinuation<Void, Never>] = []

  init(expected: Int) {
    self.expected = expected
  }

  func arriveAndWait() async {
    arrived += 1
    guard arrived < expected else {
      for continuation in waiting { continuation.resume() }
      waiting.removeAll()
      return
    }
    await withCheckedContinuation { continuation in
      waiting.append(continuation)
    }
  }
}
