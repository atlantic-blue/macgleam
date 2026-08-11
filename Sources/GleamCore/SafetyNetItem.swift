import Foundation

/// Exactly what a restore reinstates and nothing more. The owning account is
/// deliberately absent: nothing can read it and nothing can write it without
/// root, so a field for it could only ever be nil inside a struct that claims
/// to carry what restore needs.
public struct FileMetadataSnapshot: Codable, Sendable, Equatable {
  /// The mode read before the file moved into the store, exact, because a
  /// restore reinstates this value bit for bit.
  public let posixPermissions: UInt16
  public let extendedAttributes: [String: Data]
  public let created: Date?
  public let modified: Date?

  public init(
    posixPermissions: UInt16,
    extendedAttributes: [String: Data],
    created: Date?,
    modified: Date?
  ) {
    self.posixPermissions = posixPermissions
    self.extendedAttributes = extendedAttributes
    self.created = created
    self.modified = modified
  }
}

/// One quarantined or archived file in the SafetyNet store. Expiry marks
/// purge eligibility only; nothing is ever purged without explicit
/// confirmation.
///
/// `allocatedBytes` is a fact recorded once and never a value to recompute.
/// The store strips execute from what it holds, and a directory without
/// execute cannot be traversed, so a later reading of a directory payload
/// returns an absence rather than the truth. The size is therefore measured at
/// the origin path before the payload moves, and an item exists only if that
/// measurement was exact.
public struct SafetyNetItem: Identifiable, Codable, Sendable, Equatable {
  public enum Source: String, Codable, Sendable, Equatable {
    case malwareQuarantine
    case uninstallArchive
  }

  /// Expiry is exactly 30 days after storage.
  public static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

  public let id: UUID
  public let originPath: AbsolutePath
  public let storedPath: AbsolutePath
  public let source: Source
  public let groupID: UUID?
  public let metadata: FileMetadataSnapshot
  /// The allocated bytes the payload occupied when it was stored: a file's own
  /// allocation, a directory's whole subtree total. Allocated and never
  /// logical, so one number means one thing across the app.
  public let allocatedBytes: UInt64
  public let storedAt: Date
  public let expiresAt: Date
  public var isRestored: Bool

  public init(
    id: UUID,
    originPath: AbsolutePath,
    storedPath: AbsolutePath,
    source: Source,
    groupID: UUID?,
    metadata: FileMetadataSnapshot,
    allocatedBytes: UInt64,
    storedAt: Date,
    expiresAt: Date,
    isRestored: Bool
  ) {
    self.id = id
    self.originPath = originPath
    self.storedPath = storedPath
    self.source = source
    self.groupID = groupID
    self.metadata = metadata
    self.allocatedBytes = allocatedBytes
    self.storedAt = storedAt
    self.expiresAt = expiresAt
    self.isRestored = isRestored
  }
}
