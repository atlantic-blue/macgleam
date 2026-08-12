import Foundation

/// The quarantine and archive store. Reversibility is the trust feature, so
/// every guarantee here is about giving a file back exactly as it was.
///
/// `store` moves a file in, snapshots the metadata a restore reinstates, and
/// strips the execute bits from the stored payload so quarantined malware
/// cannot run. `restore` moves the payload back to its origin path with its
/// mode, extended attributes and dates intact, and refuses an occupied origin
/// without changing anything. `restoreGroup` restores an uninstall as one unit
/// or not at all. Expiry marks purge eligibility only; nothing leaves the
/// store without a confirmation whose counts match.
public protocol SafetyNetStoring: Sendable {
  func store(
    _ path: AbsolutePath,
    source: SafetyNetItem.Source,
    groupID: UUID?
  ) async throws -> SafetyNetItem

  func items(includingRestored: Bool) async throws -> [SafetyNetItem]
  func restore(itemID: UUID) async throws
  func restoreGroup(groupID: UUID) async throws
  func purge(itemIDs: [UUID], confirmation: PurgeConfirmation) async throws
  func purgeEligibleItems(asOf now: Date) async throws -> [SafetyNetItem]
}

/// Evidence that the caller saw the exact scope of a purge.
public struct PurgeConfirmation: Codable, Sendable, Equatable {
  /// The number of identifiers in the purge.
  public let itemCount: UInt32
  /// The allocated bytes the purge reclaims: the allocated size of a stored
  /// file, the subtree allocated total of a stored directory. The same basis
  /// as every other reclaimable figure in MacGleam.
  public let byteTotal: UInt64
  public let confirmedAt: Date

  public init(itemCount: UInt32, byteTotal: UInt64, confirmedAt: Date) {
    self.itemCount = itemCount
    self.byteTotal = byteTotal
    self.confirmedAt = confirmedAt
  }
}

public enum SafetyNetError: Error, Sendable, Equatable {
  case originOccupied(AbsolutePath)
  case itemNotFound(UUID)
  /// No item carries this group identifier. Names a group.
  case groupNotFound(UUID)
  /// The item has already been restored, or, from `restoreGroup`, every item
  /// of the group has. Names an item in the first case and a group in the
  /// second.
  case alreadyRestored(UUID)
  case confirmationMismatch
  case denylistedPath(AbsolutePath)
  /// The payload needs the privileged half and this store has none, so
  /// nothing moved. Names the path that needed it.
  case privilegeUnavailable(AbsolutePath)
  /// The privileged half described an archive that is not the one asked
  /// about: another origin, or a report for another item. Names the item.
  case privilegedReportDisagreed(UUID)
}

extension SafetyNetError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .originOccupied(let path):
      return "Something already sits at \(path.value), so nothing was restored."
    case .itemNotFound(let identifier):
      return "The SafetyNet holds no item \(identifier.uuidString)."
    case .groupNotFound(let identifier):
      return "The SafetyNet holds no group \(identifier.uuidString)."
    case .alreadyRestored(let identifier):
      return "\(identifier.uuidString) has already been restored."
    case .confirmationMismatch:
      return "The confirmation does not match the items being purged."
    case .denylistedPath(let path):
      return "\(path.value) is protected and cannot be moved into the SafetyNet."
    case .privilegeUnavailable(let path):
      return
        "\(path.value) needs MacGleam's privileged helper, which is not available, so nothing "
        + "was moved."
    case .privilegedReportDisagreed(let identifier):
      return
        "The privileged helper described a different archive from \(identifier.uuidString), so "
        + "nothing was recorded."
    }
  }
}
