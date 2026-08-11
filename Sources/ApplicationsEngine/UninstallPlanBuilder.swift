import Foundation
import GleamCore

/// Turns a reviewed uninstall selection into archive operations, one per path,
/// grouped per application.
///
/// Archive is the only operation this builder can construct. There is no
/// deletion mode here and no branch to reach a removal from: a forged finding,
/// a category added later or a settings change cannot put a `moveToTrash` or a
/// `deletePermanently` inside an uninstall, because nothing in here builds one.
/// That matters because an uninstall is sold as reversible for 30 days as a
/// unit, and a removal sitting among the archives would make it partly
/// irreversible without saying so. Somebody who turned permanent deletion on
/// for junk did not ask for an uninstall they cannot undo.
///
/// The group is per application per plan. The bundle and its leftovers share
/// one identifier, so a restore puts the whole application back at once; two
/// applications get two identifiers, so restoring one leaves the other
/// uninstalled; and a second plan of the same application gets a fresh one, so
/// a restore cannot reach into an older uninstall's items.
struct UninstallPlanBuilder {
  private let context: PlanContext
  private let excludedBundleID: String
  private let environment = OwnershipEnvironment.current
  private var operations: [GleamCore.Operation] = []
  private var totalBytes: UInt64 = 0
  private var groupsByBundleID: [String: UUID] = [:]

  init(context: PlanContext, excluding excludedBundleID: String) {
    self.context = context
    self.excludedBundleID = excludedBundleID
  }

  /// Adds one finding's paths. A finding naming no application, one naming
  /// MacGleam itself, and an entry the denylist blocks all contribute nothing,
  /// so a selection of only those plans an empty plan rather than a partial
  /// one.
  mutating func add(_ finding: Finding) {
    guard let bundleID = Self.uninstalledBundleID(of: finding.category),
      bundleID != excludedBundleID
    else { return }
    let targeted = finding.entries.filter { !context.rules.denylist.blocks($0.path) }
    guard !targeted.isEmpty else { return }
    let groupID = group(for: bundleID)
    for entry in targeted {
      totalBytes += entry.allocatedBytes
      operations.append(archive(entry.path, findingID: finding.id, groupID: groupID))
    }
  }

  /// The plan's total is the sum of the allocated bytes of the entries its
  /// operations target, C6's basis: an archive move moves exactly the bytes a
  /// trash move would, and a denylisted entry takes its bytes out with it.
  func build(sessionID: UUID) -> OperationPlan {
    OperationPlan(
      id: UUID(),
      sessionID: sessionID,
      operations: operations,
      totalBytes: totalBytes,
      permanentDeletionConfirmation: nil)
  }

  private mutating func group(for bundleID: String) -> UUID {
    if let existing = groupsByBundleID[bundleID] { return existing }
    let identifier = UUID()
    groupsByBundleID[bundleID] = identifier
    return identifier
  }

  private func archive(
    _ path: AbsolutePath,
    findingID: UUID,
    groupID: UUID
  ) -> GleamCore.Operation {
    let ownership = context.ownership.ownership(of: path, environment: environment)
    return GleamCore.Operation(
      id: UUID(),
      findingID: findingID,
      kind: .archive(target: path, groupID: groupID),
      privilege: ownership == .userDomain ? .user : .root)
  }

  /// The application a finding belongs to, for the two categories an uninstall
  /// is made of. Everything else names no application to group by and is not
  /// this module's to remove.
  private static func uninstalledBundleID(of category: FindingCategory) -> String? {
    switch category {
    case .applicationBundle(let bundleID), .applicationLeftover(let bundleID):
      return bundleID
    default:
      return nil
    }
  }
}
