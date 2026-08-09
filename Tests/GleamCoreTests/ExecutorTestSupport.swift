import CryptoKit
import Foundation
import GleamCore
import os

typealias ExecutorOperation = GleamCore.Operation

/// Shared fixtures for the C17 executor tests. Everything is deterministic:
/// fixed instants, a fixed signing key seed, and an in memory file system.
enum ExecutorFixture {
  /// The instant the injected clock returns. The report's startedAt and
  /// finishedAt are pinned to it.
  static let executionInstant = Date(timeIntervalSince1970: 1_723_000_000)
  static let confirmationInstant = Date(timeIntervalSince1970: 1_722_999_000)

  static let userHome = AbsolutePath(normalising: "/Users/julian")
  static let environment = OwnershipEnvironment(currentUserHome: userHome, currentUserID: 501)

  /// Signing seed owned by the executor tests alone, distinct from any
  /// other fixture file's key material.
  static let signingKeySeed = Data((0..<32).map { UInt8(truncatingIfNeeded: 0x90 &+ $0 &* 3) })

  static func path(_ value: String) -> AbsolutePath {
    AbsolutePath(normalising: value)
  }

  /// Builds the effective denylist the way production obtains one: a
  /// catalogue signed with this file's own key, verified and adopted by a
  /// real RuleCatalogStore, independent of any engine.
  static func signedDenylist(blocking patterns: [String]) async throws -> Denylist {
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: signingKeySeed)
    let unsigned = RuleCatalog(
      version: RuleCatalogVersion(value: 1),
      signature: Data(),
      cleanupRules: [],
      adwareRules: [],
      denylist: Denylist(patterns: patterns.map { PathPattern(pattern: $0) })
    )
    let signature = try key.signature(for: unsigned.canonicalContentEncoding())
    let signed = RuleCatalog(
      version: unsigned.version,
      signature: signature,
      cleanupRules: [],
      adwareRules: [],
      denylist: unsigned.denylist
    )
    let verifier = try RuleCatalogVerifier(publicKey: key.publicKey.rawRepresentation)
    let store = try RuleCatalogStore(baseline: signed, verifier: verifier)
    return await store.effectiveDenylist
  }

  static func emptyDenylist() async throws -> Denylist {
    try await signedDenylist(blocking: [])
  }

  static func trashOperation(
    target: AbsolutePath,
    privilege: ExecutorOperation.Privilege = .user
  ) -> ExecutorOperation {
    ExecutorOperation(
      id: UUID(), findingID: UUID(), kind: .moveToTrash(target: target), privilege: privilege)
  }

  static func permanentOperation(
    target: AbsolutePath,
    privilege: ExecutorOperation.Privilege = .user
  ) -> ExecutorOperation {
    ExecutorOperation(
      id: UUID(), findingID: UUID(), kind: .deletePermanently(target: target), privilege: privilege)
  }

  static func launchItemOperation(
    label: String,
    enabled: Bool,
    privilege: ExecutorOperation.Privilege
  ) -> ExecutorOperation {
    ExecutorOperation(
      id: UUID(),
      findingID: UUID(),
      kind: .setLaunchItemEnabled(item: LaunchItemID(value: label), enabled: enabled),
      privilege: privilege
    )
  }

  static func maintenanceOperation(
    task: MaintenanceTask,
    privilege: ExecutorOperation.Privilege = .root
  ) -> ExecutorOperation {
    ExecutorOperation(
      id: UUID(), findingID: UUID(), kind: .runMaintenance(task: task), privilege: privilege)
  }

  static func plan(
    operations: [ExecutorOperation],
    totalBytes: UInt64,
    confirmation: PermanentDeletionConfirmation? = nil
  ) -> OperationPlan {
    OperationPlan(
      id: UUID(),
      sessionID: UUID(),
      operations: operations,
      totalBytes: totalBytes,
      permanentDeletionConfirmation: confirmation
    )
  }

  static func confirmation(fileCount: UInt32, byteTotal: UInt64) -> PermanentDeletionConfirmation {
    PermanentDeletionConfirmation(
      fileCount: fileCount, byteTotal: byteTotal, confirmedAt: confirmationInstant)
  }
}

/// Test ownership policy: everything at or under /Library is system domain,
/// everything else is user domain. Pure and deterministic, so routing
/// behaviour is pinned without depending on a concrete C16 implementation.
struct ExecutorLibraryOwnershipPolicy: PathOwnershipPolicy {
  private static let systemRoot = AbsolutePath(normalising: "/Library")

  func ownership(of path: AbsolutePath, environment: OwnershipEnvironment) -> PathOwnership {
    if path == Self.systemRoot || path.isDescendant(of: Self.systemRoot) {
      return .systemDomain
    }
    return .userDomain
  }
}

/// A thread safe flag the cancellation tests flip from inside the file
/// system boundary, so cancellation lands deterministically between two
/// named operations, never on a race with event delivery.
final class ExecutorCancellationTrigger: Sendable {
  private let state = OSAllocatedUnfairLock(initialState: false)

  func trip() {
    state.withLock { $0 = true }
  }

  var isTripped: Bool {
    state.withLock { $0 }
  }
}

/// Forwards every call to the in memory file system and trips the trigger
/// the moment the designated target has been fully mutated. The executor's
/// injected isCancelled probe reads the trigger, which models the user
/// pressing cancel while an item is mid flight.
struct ExecutorTrippingFileSystem: FileSystemReading, FileSystemMutating {
  let base: InMemoryFileSystem
  let tripAfterMutating: AbsolutePath
  let trigger: ExecutorCancellationTrigger

  func enumerate(root: AbsolutePath, options: EnumerationOptions) -> AsyncThrowingStream<
    EnumerationEvent, any Error
  > {
    base.enumerate(root: root, options: options)
  }

  func metadata(at path: AbsolutePath) async throws -> FileRecord {
    try await base.metadata(at: path)
  }

  func readData(at path: AbsolutePath, maxBytes: UInt64) async throws -> Data {
    try await base.readData(at: path, maxBytes: maxBytes)
  }

  func extendedAttributes(at path: AbsolutePath) async throws -> [String: Data] {
    try await base.extendedAttributes(at: path)
  }

  func exists(_ path: AbsolutePath) async -> Bool {
    await base.exists(path)
  }

  func volumeInfo(at path: AbsolutePath) async throws -> VolumeInfo {
    try await base.volumeInfo(at: path)
  }

  func moveToTrash(_ path: AbsolutePath) async throws -> AbsolutePath {
    let destination = try await base.moveToTrash(path)
    if path == tripAfterMutating {
      trigger.trip()
    }
    return destination
  }

  func move(_ source: AbsolutePath, to destination: AbsolutePath) async throws {
    try await base.move(source, to: destination)
    if source == tripAfterMutating {
      trigger.trip()
    }
  }

  func delete(_ path: AbsolutePath) async throws {
    try await base.delete(path)
    if path == tripAfterMutating {
      trigger.trip()
    }
  }

  func createDirectory(at path: AbsolutePath) async throws {
    try await base.createDirectory(at: path)
  }

  func setPosixPermissions(_ mode: UInt16, at path: AbsolutePath) async throws {
    try await base.setPosixPermissions(mode, at: path)
  }

  func setExtendedAttributes(_ attributes: [String: Data], at path: AbsolutePath) async throws {
    try await base.setExtendedAttributes(attributes, at: path)
  }
}

/// The construction surface the tests demand of the concrete C17 executor.
/// The clock and the cancellation probe are injected so no test reads a
/// wall clock or races a task.
func executorMake(
  fileSystem: any FileSystem,
  denylist: Denylist,
  isCancelled: @escaping @Sendable () -> Bool = { false }
) -> PlanExecutor {
  PlanExecutor(
    fileSystem: fileSystem,
    denylist: denylist,
    ownershipPolicy: ExecutorLibraryOwnershipPolicy(),
    environment: ExecutorFixture.environment,
    now: { ExecutorFixture.executionInstant },
    isCancelled: isCancelled
  )
}

func executorCollect(_ executor: PlanExecutor, executing plan: OperationPlan) async
  -> [ExecutionEvent]
{
  var events: [ExecutionEvent] = []
  for await event in executor.execute(plan) {
    events.append(event)
  }
  return events
}

/// The report is well formed only when exactly one planCompleted exists and
/// it is the final event. Returns nil otherwise so every call site fails
/// loudly on a malformed stream.
func executorFinalReport(in events: [ExecutionEvent]) -> ExecutionReport? {
  let reports = events.compactMap { event -> ExecutionReport? in
    if case .planCompleted(let report) = event {
      return report
    }
    return nil
  }
  guard reports.count == 1, let last = events.last, case .planCompleted = last else {
    return nil
  }
  return reports.first
}

func executorStartedOperationIDs(in events: [ExecutionEvent]) -> [UUID] {
  events.compactMap { event -> UUID? in
    if case .operationStarted(let operationID) = event {
      return operationID
    }
    return nil
  }
}

func executorFailureReason(_ result: OperationResult?) -> String? {
  if case .failed(let reason) = result {
    return reason
  }
  return nil
}

func executorHelperUnavailableReason(in events: [ExecutionEvent]) -> String? {
  for event in events {
    if case .refused(.helperUnavailable(let reason)) = event {
      return reason
    }
  }
  return nil
}
