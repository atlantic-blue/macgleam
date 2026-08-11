import Foundation

/// The read side of the file system. The only view of the disk any engine
/// ever gets, which is what makes every engine testable against an in memory
/// implementation.
///
/// Reading only: no method here mutates anything. Enumeration streams records
/// as discovered, never yields the same (volumeID, fileID) pair twice, reports
/// unreadable directories as events rather than throwing, and ends promptly on
/// cancellation. Only volume level failures throw. Order is not guaranteed.
public protocol FileSystemReading: Sendable {
  func enumerate(
    root: AbsolutePath,
    options: EnumerationOptions
  ) -> AsyncThrowingStream<EnumerationEvent, Error>

  func metadata(at path: AbsolutePath) async throws -> FileRecord
  /// The file's permission mode, exact: the three permission triples plus
  /// setuid, setgid and the sticky bit, never the file type bits. The
  /// SafetyNet store snapshots this value and restores it bit for bit, so an
  /// unreadable mode throws rather than defaulting.
  func posixPermissions(at path: AbsolutePath) async throws -> UInt16
  /// Reads at most maxBytes. Used by hashing and YARA scanning.
  func readData(at path: AbsolutePath, maxBytes: UInt64) async throws -> Data
  func extendedAttributes(at path: AbsolutePath) async throws -> [String: Data]
  func exists(_ path: AbsolutePath) async -> Bool
  func volumeInfo(at path: AbsolutePath) async throws -> VolumeInfo
}

public enum EnumerationEvent: Sendable, Equatable {
  case record(FileRecord)
  case inaccessible(AbsolutePath, reason: String)
}

public struct EnumerationOptions: Sendable, Equatable {
  public var includesHiddenFiles: Bool
  public var descendsIntoPackages: Bool
  public var skipSubtrees: [AbsolutePath]

  public init(
    includesHiddenFiles: Bool = false,
    descendsIntoPackages: Bool = false,
    skipSubtrees: [AbsolutePath] = []
  ) {
    self.includesHiddenFiles = includesHiddenFiles
    self.descendsIntoPackages = descendsIntoPackages
    self.skipSubtrees = skipSubtrees
  }

  public static let `default` = EnumerationOptions()
}

public struct FileRecord: Sendable, Equatable {
  public let path: AbsolutePath
  public let fileID: UInt64
  public let volumeID: UInt64
  /// Allocated bytes on disk, the basis of every reclaimable estimate.
  public let allocatedBytes: UInt64
  public let isDirectory: Bool
  public let isExecutable: Bool
  public let created: Date?
  public let modified: Date?
  public let lastOpened: Date?

  public init(
    path: AbsolutePath,
    fileID: UInt64,
    volumeID: UInt64,
    allocatedBytes: UInt64,
    isDirectory: Bool,
    isExecutable: Bool,
    created: Date?,
    modified: Date?,
    lastOpened: Date?
  ) {
    self.path = path
    self.fileID = fileID
    self.volumeID = volumeID
    self.allocatedBytes = allocatedBytes
    self.isDirectory = isDirectory
    self.isExecutable = isExecutable
    self.created = created
    self.modified = modified
    self.lastOpened = lastOpened
  }
}

public struct VolumeInfo: Sendable, Equatable {
  public let root: AbsolutePath
  public let volumeID: UInt64
  public let capacityBytes: UInt64
  public let availableBytes: UInt64
  public let isInternal: Bool

  public init(
    root: AbsolutePath,
    volumeID: UInt64,
    capacityBytes: UInt64,
    availableBytes: UInt64,
    isInternal: Bool
  ) {
    self.root = root
    self.volumeID = volumeID
    self.capacityBytes = capacityBytes
    self.availableBytes = availableBytes
    self.isInternal = isInternal
  }
}
