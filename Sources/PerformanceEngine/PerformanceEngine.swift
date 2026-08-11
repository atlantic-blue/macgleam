import Foundation
import GleamCore

/// Maintenance tasks and login items: the upkeep a Mac needs that no file
/// removal can deliver, and the registrations that start themselves.
///
/// Scanning names one task per catalogue entry and one row per login item.
/// Neither reads a file, so the scan needs no Full Disk Access, and neither
/// carries a path entry: a maintenance finding names work the machine
/// performs, a launch item finding names a registration to turn off. Their
/// `paths` is empty and their `byteSize` is exactly zero.
///
/// The inventory this engine holds can only enumerate. Listing login items
/// cannot change one, and that is a property of the type rather than of the
/// code below: the changing side is a different protocol, and nothing here can
/// reach it.
///
/// No plan this engine produces can contain a file removal. That is a property
/// of the shape rather than a check: `plan` reads a finding's category and
/// nothing else, so a path is never in scope to become a target, and a finding
/// tampered with to carry entries plans exactly as one that carries none.
public struct PerformanceEngine: GleamEngine {
  private let launchItems: (any LaunchItemEnumerating)?

  public var module: GleamModule { .performance }

  public init(launchItems: (any LaunchItemEnumerating)? = nil) {
    self.launchItems = launchItems
  }

  public func scan(_ context: ScanContext) -> AsyncThrowingStream<ScanEvent, Error> {
    AsyncThrowingStream { continuation in
      Task {
        continuation.yield(.phase(.indeterminate))
        var counters = ScanCounters.zero
        for task in MaintenanceCatalogue.tasks {
          let finding = Self.makeFinding(for: task, sessionID: context.sessionID)
          counters.itemCount += finding.itemCount
          continuation.yield(.finding(finding))
          continuation.yield(.progress(counters))
        }
        await scanLaunchItems(context, counters: &counters) { continuation.yield($0) }
        continuation.yield(.phase(.settling))
        continuation.finish()
      }
    }
  }

  public func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan {
    guard !selection.isEmpty else { throw PlanningError.emptySelection }
    for finding in selection where finding.sessionID != context.sessionID {
      throw PlanningError.findingFromDifferentSession(finding.id)
    }
    let operations = selection.compactMap(Self.operation(for:))
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

  /// One login item row. Risk is review rather than safe: turning something
  /// off that somebody installed deliberately is a decision only they can
  /// take, so no launch item is ever preselected and none is swept into a job
  /// nobody opened. The category carries the scope, which is what tells a plan
  /// which side of the privileged boundary this change will land on without
  /// anything taking the identifier apart.
  fileprivate static func makeFinding(for item: LaunchItem, sessionID: UUID) -> Finding {
    Finding(
      id: UUID(),
      sessionID: sessionID,
      category: .launchItem(item: item.identifier, scope: item.scope),
      entries: [],
      risk: .review,
      explanation: LaunchItemPresentation.explanation(for: item),
      isPreselected: false)
  }
}

// MARK: - Scanning login items

extension PerformanceEngine {
  /// The login item half of the scan. An inventory that cannot be read
  /// degrades the scan and never fails it: the maintenance rows are still
  /// worth showing, and the banner says what is missing rather than the
  /// session ending on an error.
  fileprivate func scanLaunchItems(
    _ context: ScanContext,
    counters: inout ScanCounters,
    yield: (ScanEvent) -> Void
  ) async {
    guard let launchItems else { return }
    let items: [LaunchItem]
    do {
      items = try await launchItems.items()
    } catch {
      yield(.degraded(unavailable: Self.inventoryUnreadableSentence))
      return
    }
    for item in items {
      let finding = Self.makeFinding(for: item, sessionID: context.sessionID)
      counters.itemCount += finding.itemCount
      yield(.finding(finding))
      yield(.progress(counters))
    }
  }

  private static let inventoryUnreadableSentence =
    "Login and background items could not be listed, so none of them are shown."
}

// MARK: - Planning

extension PerformanceEngine {
  /// The one operation a Performance finding plans, read from its category and
  /// from nothing else. There is no path in scope to expand, so there is
  /// nothing to decide about deletion mode or denylisting, and no arm of this
  /// switch can name a removal.
  fileprivate static func operation(for finding: Finding) -> GleamCore.Operation? {
    switch finding.category {
    case .maintenanceTask(let task):
      return GleamCore.Operation(
        id: UUID(),
        findingID: finding.id,
        kind: .runMaintenance(task: task),
        privilege: .root)
    case .launchItem(let item, let scope):
      return GleamCore.Operation(
        id: UUID(),
        findingID: finding.id,
        kind: .setLaunchItemEnabled(item: item, enabled: false),
        privilege: scope == .system ? .root : .user)
    default:
      return nil
    }
  }
}
