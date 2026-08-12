import Foundation

/// The one thing the SafetyNet store cannot do itself: hold a payload only
/// root can move.
///
/// Implemented by the helper client over the message set, and absent in a
/// store that has no helper. Every method names the item, because an archive
/// outlives the plan that caused it and the item identifier is the only name
/// still true afterwards.
///
/// Guarantees, all of which are the helper's to keep:
/// - `archive` measures and snapshots at the origin before anything moves,
///   moves the payload to exactly `storedPath` and nowhere else, strips its
///   execute bits, stamps it with what it measured, snapshotted and took it
///   from, and reports that. It creates no directory. It fails whole: a
///   payload it could not measure exactly, or could not move without copying,
///   stays where it was and nothing is stamped.
/// - `describeArchived` returns the stamp of a payload already archived, which
///   is what lets the store recover an entry whose reply was lost. It reads
///   and changes nothing, and it answers with the same value the archive
///   reported.
/// - `restoreArchived` moves the payload back to the origin its stamp names,
///   reinstates the stamped mode, extended attributes and dates, removes the
///   stamp, and returns where it went. It never restores to a path the request
///   named, because the request is the part an attacker would choose.
/// - `discardArchived` deletes the payload permanently. It is the purge of a
///   root owned payload, which the user process cannot perform: removing the
///   children of a root owned directory needs write permission on that
///   directory.
public protocol SafetyNetPrivilegedArchiving: Sendable {
  func archive(
    _ path: AbsolutePath,
    to storedPath: AbsolutePath,
    itemID: UUID
  ) async throws -> PrivilegedArchiveReport

  func describeArchived(
    at storedPath: AbsolutePath,
    itemID: UUID
  ) async throws -> PrivilegedArchiveReport

  func restoreArchived(at storedPath: AbsolutePath, itemID: UUID) async throws -> AbsolutePath
  func discardArchived(at storedPath: AbsolutePath, itemID: UUID) async throws
}

/// What the privileged half observed at the origin, and the whole of what the
/// store records for a privileged item.
///
/// These are the values the helper stamped onto the payload, so the report of
/// making an archive and a later description of the same payload are equal.
public struct PrivilegedArchiveReport: Codable, Sendable, Equatable {
  public let originPath: AbsolutePath
  public let metadata: FileMetadataSnapshot
  public let allocatedBytes: UInt64

  public init(
    originPath: AbsolutePath,
    metadata: FileMetadataSnapshot,
    allocatedBytes: UInt64
  ) {
    self.originPath = originPath
    self.metadata = metadata
    self.allocatedBytes = allocatedBytes
  }
}
