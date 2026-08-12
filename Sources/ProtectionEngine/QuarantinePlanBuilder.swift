import Foundation
import GleamCore

/// Turns a reviewed detection into quarantine operations, one per path.
///
/// Quarantine is the only operation this builder can construct. There is no
/// deletion mode here and no branch to reach a removal from, so a forged
/// finding, a settings change or a category added later cannot put a
/// `moveToTrash` or a `deletePermanently` into a Protection plan. That is the
/// whole promise of this module: what it finds is contained, never deleted,
/// and containment is reversible for thirty days.
///
/// A category this module does not detect contributes nothing. A privacy row,
/// which is cleared rather than quarantined, is a different builder's work.
struct QuarantinePlanBuilder {
  private let context: PlanContext
  private let environment = OwnershipEnvironment.current
  private var operations: [GleamCore.Operation] = []
  private var totalBytes: UInt64 = 0

  init(context: PlanContext) {
    self.context = context
  }

  mutating func add(_ finding: Finding) {
    guard Self.isDetection(finding.category) else { return }
    for entry in finding.entries where !context.rules.denylist.blocks(entry.path) {
      totalBytes += entry.allocatedBytes
      operations.append(quarantine(entry.path, findingID: finding.id))
    }
  }

  func build(sessionID: UUID) -> OperationPlan {
    OperationPlan(
      id: UUID(),
      sessionID: sessionID,
      operations: operations,
      totalBytes: totalBytes,
      permanentDeletionConfirmation: nil)
  }

  private func quarantine(_ path: AbsolutePath, findingID: UUID) -> GleamCore.Operation {
    let ownership = context.ownership.ownership(of: path, environment: environment)
    return GleamCore.Operation(
      id: UUID(),
      findingID: findingID,
      kind: .quarantine(target: path),
      privilege: ownership == .userDomain ? .user : .root)
  }

  static func isDetection(_ category: FindingCategory) -> Bool {
    switch category {
    case .malware, .adwareLaunchItem, .suspiciousBrowserExtension, .unwantedAppPath:
      return true
    default:
      return false
    }
  }
}
