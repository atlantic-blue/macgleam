import Foundation

/// Executes an operation plan in the user process. Before every item, in
/// order: cancellation probe, denylist check, ownership routing. The denylist
/// runs before routing, so a blocked target is skipped in this process and
/// never crosses to the helper.
///
/// Operations whose target the ownership policy places in the system domain
/// route to the privileged helper. With a helper wired, each one is that
/// helper's to answer and a refusal costs one operation; the plan carries on
/// either way. With no helper, such an operation stops the run with
/// `helperUnavailable` and everything from that item onward reports
/// `notStarted`.
public struct PlanExecutor: PlanExecuting {
  private let fileSystem: any FileSystem
  private let denylist: Denylist
  private let helper: (any PrivilegedOperationPerforming)?
  private let ownershipPolicy: any PathOwnershipPolicy
  private let environment: OwnershipEnvironment
  private let safetyNet: (any SafetyNetStoring)?
  private let now: @Sendable () -> Date
  private let isCancelled: @Sendable () -> Bool
  private let launchItems: (any LaunchItemManaging)?

  public init(
    fileSystem: any FileSystem,
    denylist: Denylist,
    helper: (any PrivilegedOperationPerforming)? = nil,
    ownershipPolicy: any PathOwnershipPolicy,
    environment: OwnershipEnvironment,
    safetyNet: (any SafetyNetStoring)? = nil,
    now: @escaping @Sendable () -> Date,
    isCancelled: @escaping @Sendable () -> Bool,
    launchItems: (any LaunchItemManaging)? = nil
  ) {
    self.fileSystem = fileSystem
    self.denylist = denylist
    self.helper = helper
    self.ownershipPolicy = ownershipPolicy
    self.environment = environment
    self.safetyNet = safetyNet
    self.now = now
    self.isCancelled = isCancelled
    self.launchItems = launchItems
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
      let result = await executeItem(operation, planID: plan.id, halted: &halted, yield: yield)
      results.append((operationID: operation.id, result: result))
    }
    yield(.planCompleted(report(for: plan, results: results, startedAt: startedAt)))
  }

  private func executeItem(
    _ operation: Operation,
    planID: UUID,
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
    if case .setLaunchItemEnabled(let item, let enabled) = operation.kind, let launchItems {
      yield(.operationStarted(operationID: operation.id))
      let result = await changeLaunchItem(
        item, to: enabled, launchItems: launchItems, planID: planID, operationID: operation.id)
      yield(.operationFinished(operationID: operation.id, result: result))
      return result
    }
    if isSafetyNetWork(operation) {
      yield(.operationStarted(operationID: operation.id))
      let result = await perform(operation)
      yield(.operationFinished(operationID: operation.id, result: result))
      return result
    }
    let needsPrivilege = routedPrivilege(of: operation) == .root
    if needsPrivilege, helper == nil {
      halted = true
      let reason =
        "The privileged helper is not installed, so this system item was left untouched."
      yield(.refused(.helperUnavailable(reason: reason)))
      return .notStarted
    }
    yield(.operationStarted(operationID: operation.id))
    let result = await outcome(of: operation, planID: planID, needsPrivilege: needsPrivilege)
    yield(.operationFinished(operationID: operation.id, result: result))
    return result
  }

  /// One operation's outcome, from whichever process owns it. A privileged
  /// operation is the helper's to answer, and the helper answers every one:
  /// its refusals and failures are this operation's result, never the run's.
  private func outcome(
    of operation: Operation,
    planID: UUID,
    needsPrivilege: Bool
  ) async -> OperationResult {
    guard needsPrivilege, let helper else { return await perform(operation) }
    return await helper.perform(operation, planID: planID)
  }

  // MARK: - Launch items

  /// A launch item names no path, so ownership routing has nothing to decide
  /// from and this operation is the exception to it: the manager routes by the
  /// scope it reads from the current inventory, and the executor supplies the
  /// attribution because it is the only thing that knows both identifiers.
  /// Turning a registration off frees nothing, so a completed change promises
  /// no bytes.
  private func changeLaunchItem(
    _ item: LaunchItemID,
    to enabled: Bool,
    launchItems: any LaunchItemManaging,
    planID: UUID,
    operationID: UUID
  ) async -> OperationResult {
    do {
      _ = try await launchItems.setEnabled(
        enabled,
        item: item,
        attribution: .operation(planID: planID, operationID: operationID))
      return .completed(bytesReclaimed: 0)
    } catch let error as LaunchItemError {
      return .failed(reason: Self.sentence(for: error, item: item))
    } catch {
      return .failed(reason: failureSentence(for: error))
    }
  }

  /// A launch item failure in the report's words. The item is named where it
  /// has gone, because a row saying only that something failed is no use for
  /// finding out what; every other failure already arrives as a sentence.
  private static func sentence(for error: LaunchItemError, item: LaunchItemID) -> String {
    switch error {
    case .itemNotFound:
      return "The login item \(item.value) is not on this Mac any more, so nothing was changed."
    case .changeFailed(let reason):
      return reason
    }
  }

  // MARK: - Routing

  /// A quarantine and an archive go to the SafetyNet store whatever the path's
  /// ownership says, and the store does its own routing inside.
  ///
  /// Ownership routing decides between this process and the helper for a trash
  /// move and a permanent deletion, and it decides nothing here: the store
  /// holds the manifest, so the store is the thing that must know an archive
  /// happened. An executor sending a system domain archive to the helper
  /// directly moves a file into the store without the store knowing, which is
  /// exactly the defect this closes.
  private func isSafetyNetWork(_ operation: Operation) -> Bool {
    switch operation.kind {
    case .quarantine, .archive:
      return true
    case .moveToTrash, .deletePermanently, .setLaunchItemEnabled, .runMaintenance:
      return false
    }
  }

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
    case .quarantine(let target):
      return await moveIntoSafetyNet(target, source: .malwareQuarantine, groupID: nil)
    case .archive(let target, let groupID):
      return await moveIntoSafetyNet(target, source: .uninstallArchive, groupID: groupID)
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

  /// The store owns where a quarantined or archived payload goes, so the
  /// executor hands it the path and invents no storage location of its own.
  ///
  /// The bytes reported are the size the store recorded for the item it
  /// returned, never a figure measured here. The executor cannot measure a
  /// system domain payload reliably, the store already holds an exact
  /// measurement taken at the origin before the move, and two measurements of
  /// one file that could disagree are one measurement too many.
  private func moveIntoSafetyNet(
    _ target: AbsolutePath,
    source: SafetyNetItem.Source,
    groupID: UUID?
  ) async -> OperationResult {
    guard let safetyNet else {
      let reason =
        "The SafetyNet store is not available in this build, "
        + "so \(target.value) was left untouched."
      return .failed(reason: reason)
    }
    do {
      let item = try await safetyNet.store(target, source: source, groupID: groupID)
      return .completed(bytesReclaimed: item.allocatedBytes)
    } catch {
      return .failed(reason: failureSentence(for: error))
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
