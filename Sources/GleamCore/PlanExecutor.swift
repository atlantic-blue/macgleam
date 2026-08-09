import Foundation

/// Executes an operation plan in the user process. Before every item, in
/// order: cancellation probe, denylist check, ownership routing. Operations
/// whose target the ownership policy places in the system domain would route
/// to the privileged helper; no helper exists in this build, so such an
/// operation stops the run with `helperUnavailable` and everything from that
/// item onward reports `notStarted`.
public struct PlanExecutor: PlanExecuting {
  private let fileSystem: any FileSystem
  private let denylist: Denylist
  private let ownershipPolicy: any PathOwnershipPolicy
  private let environment: OwnershipEnvironment
  private let now: @Sendable () -> Date
  private let isCancelled: @Sendable () -> Bool

  public init(
    fileSystem: any FileSystem,
    denylist: Denylist,
    ownershipPolicy: any PathOwnershipPolicy,
    environment: OwnershipEnvironment,
    now: @escaping @Sendable () -> Date,
    isCancelled: @escaping @Sendable () -> Bool
  ) {
    self.fileSystem = fileSystem
    self.denylist = denylist
    self.ownershipPolicy = ownershipPolicy
    self.environment = environment
    self.now = now
    self.isCancelled = isCancelled
  }

  public func execute(_ plan: OperationPlan) -> AsyncStream<ExecutionEvent> {
    AsyncStream { continuation in
      Task {
        await run(plan) { continuation.yield($0) }
        continuation.finish()
      }
    }
  }

  // MARK: - Run

  private func run(_ plan: OperationPlan, yield: @Sendable (ExecutionEvent) -> Void) async {
    let startedAt = now()
    guard await permanentDeletionIsConfirmed(plan) else {
      yield(.refused(.permanentDeletionUnconfirmed))
      let untouched = plan.operations.map {
        (operationID: $0.id, result: OperationResult.notStarted)
      }
      yield(.planCompleted(report(for: plan, results: untouched, startedAt: startedAt)))
      return
    }
    var results: [(operationID: UUID, result: OperationResult)] = []
    var halted = false
    for operation in plan.operations {
      let result = await executeItem(operation, halted: &halted, yield: yield)
      results.append((operationID: operation.id, result: result))
    }
    yield(.planCompleted(report(for: plan, results: results, startedAt: startedAt)))
  }

  private func executeItem(
    _ operation: Operation,
    halted: inout Bool,
    yield: (ExecutionEvent) -> Void
  ) async -> OperationResult {
    if halted { return .notStarted }
    if isCancelled() {
      halted = true
      return .notStarted
    }
    if let target = pathedTarget(of: operation), denylist.blocks(target) {
      yield(.operationFinished(operationID: operation.id, result: .skippedDenylisted))
      return .skippedDenylisted
    }
    guard routedPrivilege(of: operation) == .user else {
      halted = true
      let reason =
        "The privileged helper is not installed, so this system item was left untouched."
      yield(.refused(.helperUnavailable(reason: reason)))
      return .notStarted
    }
    yield(.operationStarted(operationID: operation.id))
    let result = await perform(operation)
    yield(.operationFinished(operationID: operation.id, result: result))
    return result
  }

  // MARK: - Routing

  private func routedPrivilege(of operation: Operation) -> Operation.Privilege {
    guard let target = pathedTarget(of: operation) else { return operation.privilege }
    switch ownershipPolicy.ownership(of: target, environment: environment) {
    case .userDomain: return .user
    case .systemDomain: return .root
    }
  }

  private func pathedTarget(of operation: Operation) -> AbsolutePath? {
    switch operation.kind {
    case .moveToTrash(let target), .deletePermanently(let target),
      .quarantine(let target), .archive(let target, _):
      return target
    case .setLaunchItemEnabled, .runMaintenance:
      return nil
    }
  }

  // MARK: - Performing

  private func perform(_ operation: Operation) async -> OperationResult {
    switch operation.kind {
    case .moveToTrash(let target):
      return await reclaim(target) { _ = try await fileSystem.moveToTrash(target) }
    case .deletePermanently(let target):
      return await reclaim(target) { try await fileSystem.delete(target) }
    case .quarantine(let target), .archive(let target, _):
      let reason =
        "The SafetyNet store is not available in this build, "
        + "so \(target.value) was left untouched."
      return .failed(reason: reason)
    case .setLaunchItemEnabled(let item, _):
      let reason =
        "Launch item management is not available in this build, "
        + "so \(item.value) was left unchanged."
      return .failed(reason: reason)
    case .runMaintenance(let task):
      let reason =
        "Maintenance tasks are not available in this build, "
        + "so \(task.rawValue) was not run."
      return .failed(reason: reason)
    }
  }

  private func reclaim(
    _ target: AbsolutePath,
    using action: () async throws -> Void
  ) async -> OperationResult {
    do {
      let bytes = try await measureBytes(at: target)
      try await action()
      return .completed(bytesReclaimed: bytes)
    } catch {
      return .failed(reason: failureSentence(for: error))
    }
  }

  private func failureSentence(for error: any Error) -> String {
    let description = error.localizedDescription
    guard description.isEmpty else { return description }
    return "The operation failed for an unknown reason."
  }

  // MARK: - Permanent deletion gate

  private func permanentDeletionIsConfirmed(_ plan: OperationPlan) async -> Bool {
    let targets = permanentTargets(of: plan)
    guard !targets.isEmpty else { return true }
    guard plan.hasValidPermanentDeletionConfirmation,
      let confirmation = plan.permanentDeletionConfirmation
    else { return false }
    var measured: UInt64 = 0
    for target in targets {
      measured += (try? await measureBytes(at: target)) ?? 0
    }
    return confirmation.byteTotal == measured
  }

  private func permanentTargets(of plan: OperationPlan) -> [AbsolutePath] {
    plan.operations.compactMap { operation in
      if case .deletePermanently(let target) = operation.kind { return target }
      return nil
    }
  }

  // MARK: - Byte accounting

  private func measureBytes(at path: AbsolutePath) async throws -> UInt64 {
    let record = try await fileSystem.metadata(at: path)
    guard record.isDirectory else { return record.allocatedBytes }
    var total = record.allocatedBytes
    let options = EnumerationOptions(includesHiddenFiles: true, descendsIntoPackages: true)
    for try await event in fileSystem.enumerate(root: path, options: options) {
      if case .record(let child) = event { total += child.allocatedBytes }
    }
    return total
  }

  private func report(
    for plan: OperationPlan,
    results: [(operationID: UUID, result: OperationResult)],
    startedAt: Date
  ) -> ExecutionReport {
    let bytes = results.reduce(UInt64(0)) { total, entry in
      if case .completed(let reclaimed) = entry.result { return total + reclaimed }
      return total
    }
    return ExecutionReport(
      planID: plan.id,
      results: results,
      bytesReclaimed: bytes,
      startedAt: startedAt,
      finishedAt: now())
  }
}
