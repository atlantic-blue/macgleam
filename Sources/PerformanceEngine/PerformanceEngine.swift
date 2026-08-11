import Foundation
import GleamCore

/// Maintenance tasks: the upkeep a Mac needs that no file removal can deliver.
///
/// Scanning names one task per catalogue entry and reads nothing from disk, so
/// it needs no Full Disk Access and never reports a degraded category. A
/// maintenance finding carries no path entries: it names work the machine
/// performs, not files it removes, so its `paths` is empty and its `byteSize`
/// is exactly zero. Planning turns each selected finding into one
/// `runMaintenance` operation at root privilege, which is what sends it to the
/// helper rather than running it in process.
///
/// No plan this engine produces can contain a file removal. That is a property
/// of the shape rather than a check: `plan` reads a finding's category and
/// nothing else, so a path is never in scope to become a target, and a finding
/// tampered with to carry entries plans exactly as one that carries none.
public struct PerformanceEngine: GleamEngine {
  public var module: GleamModule { .performance }

  public init() {}

  public func scan(_ context: ScanContext) -> AsyncThrowingStream<ScanEvent, Error> {
    AsyncThrowingStream { continuation in
      continuation.yield(.phase(.indeterminate))
      var counters = ScanCounters.zero
      for task in MaintenanceCatalogue.tasks {
        let finding = Self.makeFinding(for: task, sessionID: context.sessionID)
        counters.itemCount += finding.itemCount
        counters.bytesReclaimable += finding.byteSize
        continuation.yield(.finding(finding))
        continuation.yield(.progress(counters))
      }
      continuation.yield(.phase(.settling))
      continuation.finish()
    }
  }

  public func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan {
    guard !selection.isEmpty else { throw PlanningError.emptySelection }
    for finding in selection where finding.sessionID != context.sessionID {
      throw PlanningError.findingFromDifferentSession(finding.id)
    }
    let operations = selection.compactMap { finding in
      Self.maintenanceOperation(for: finding)
    }
    return OperationPlan(
      id: UUID(),
      sessionID: context.sessionID,
      operations: operations,
      totalBytes: 0,
      permanentDeletionConfirmation: nil)
  }
}

// MARK: - Findings

extension PerformanceEngine {
  /// One maintenance row. Risk is safe because the task does nothing to the
  /// machine that cannot be undone by running it again, and a task that clears
  /// user visible data still arrives deselected: preselection is consent
  /// inferred from somebody having read the row, and a row nobody opens is a
  /// warning nobody reads.
  fileprivate static func makeFinding(for task: MaintenanceTask, sessionID: UUID) -> Finding {
    Finding(
      id: UUID(),
      sessionID: sessionID,
      category: .maintenanceTask(task: task),
      entries: [],
      risk: .safe,
      explanation: explanation(for: task),
      isPreselected: !task.clearsUserVisibleData)
  }

  /// The catalogue sentence, followed by the warning where the task carries
  /// one, so the row says what will be cleared before anybody runs it.
  private static func explanation(for task: MaintenanceTask) -> String {
    let description = MaintenanceCatalogue.explanation(for: task)
    guard let warning = MaintenanceCatalogue.warning(for: task) else { return description }
    return description + " " + warning
  }
}

// MARK: - Planning

extension PerformanceEngine {
  /// The one operation a maintenance finding plans. The task comes from the
  /// category, the only place this engine reads, so there is no path in scope
  /// to expand and nothing to decide about deletion mode or denylisting.
  /// Privilege is root because running maintenance is the helper's job.
  fileprivate static func maintenanceOperation(for finding: Finding) -> GleamCore.Operation? {
    guard case .maintenanceTask(let task) = finding.category else { return nil }
    return GleamCore.Operation(
      id: UUID(),
      findingID: finding.id,
      kind: .runMaintenance(task: task),
      privilege: .root)
  }
}
