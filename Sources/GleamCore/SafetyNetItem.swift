import Foundation

public struct FileMetadataSnapshot: Codable, Sendable, Equatable {
  public let posixPermissions: UInt16
  public let ownerAccountName: String?
  public let extendedAttributes: [String: Data]
  public let created: Date?
  public let modified: Date?

  public init(
    posixPermissions: UInt16,
    ownerAccountName: String?,
    extendedAttributes: [String: Data],
    created: Date?,
    modified: Date?
  ) {
    self.posixPermissions = posixPermissions
    self.ownerAccountName = ownerAccountName
    self.extendedAttributes = extendedAttributes
    self.created = created
    self.modified = modified
  }
}

/// One quarantined or archived file in the SafetyNet store. Expiry marks
/// purge eligibility only; nothing is ever purged without explicit
/// confirmation.
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
    self.storedAt = storedAt
    self.expiresAt = expiresAt
    self.isRestored = isRestored
  }
}
