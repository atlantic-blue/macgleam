import Foundation
import GleamCore
import GleamHelperCore

/// The root side of the SafetyNet archive: four verbs over one payload path
/// the store chose.
///
/// The division of labour with the store is forced rather than chosen. The
/// measurement has to happen at the origin before anything moves, and the
/// origin may be a path the user process cannot read at all, which is the case
/// a privileged archive exists for. The strip has to happen after the move,
/// and after the move the payload is root owned, so only the mover can contain
/// what it moved. The recording is the reverse: one process holds the
/// manifest, and it is the one that reads it, so this side reports and never
/// writes there.
///
/// What goes back onto the disk at restore time is read from the stamp this
/// helper wrote, never from the request. A request able to name a mode, an
/// attribute set or an origin would be an instruction to root to place chosen
/// content at a chosen path, which is a far larger authority than removing
/// files.
struct HelperArchive: Sendable {
  let fileSystem: DiskFileSystem

  /// The attribute the payload carries while it is in the store: everything
  /// the helper observed at the origin, encoded. Only root can write it on a
  /// root owned file, which is what makes it evidence rather than a label.
  static let stampName = "com.atlanticblue.macgleam.archive"

  // MARK: - Making an archive

  func archive(
    _ target: AbsolutePath,
    to storedPath: AbsolutePath,
    itemID: UUID
  ) async throws -> PrivilegedArchiveReport {
    try await requireSameVolume(target, as: storedPath)
    let metadata = try await snapshot(of: target)
    let allocatedBytes = try await allocatedBytes(ofPayloadAt: target)
    let report = PrivilegedArchiveReport(
      originPath: target, metadata: metadata, allocatedBytes: allocatedBytes)
    try await fileSystem.move(target, to: storedPath)
    try await contain(storedPath, stamping: report)
    return report
  }

  /// A move within one volume or nothing. A cross volume move is a copy, and a
  /// copy is where ownership, extended attributes and hard links are lost; a
  /// payload that comes back different from what left is not a restore.
  private func requireSameVolume(
    _ target: AbsolutePath,
    as storedPath: AbsolutePath
  ) async throws {
    guard let storeDirectory = storedPath.ancestors(downTo: Self.root).first else {
      throw FileSystemError.ioFailure(storedPath, description: Self.noParentSentence)
    }
    let origin = try await fileSystem.volumeInfo(at: target)
    let destination = try await fileSystem.volumeInfo(at: storeDirectory)
    guard origin.volumeID == destination.volumeID else {
      throw FileSystemError.ioFailure(target, description: Self.crossVolumeSentence)
    }
  }

  /// Everything a restore reinstates, read before the payload moves.
  private func snapshot(of path: AbsolutePath) async throws -> FileMetadataSnapshot {
    let mode = try await fileSystem.posixPermissions(at: path)
    let attributes = try await fileSystem.extendedAttributes(at: path)
    let record = try await fileSystem.metadata(at: path)
    return FileMetadataSnapshot(
      posixPermissions: mode,
      extendedAttributes: attributes,
      created: record.created,
      modified: record.modified)
  }

  /// Exact or nothing. An entry the walk could not read fails the measurement
  /// rather than contributing zero, because a total that quietly skipped what
  /// it could not read is a smaller number that looks exactly like a true one.
  private func allocatedBytes(ofPayloadAt path: AbsolutePath) async throws -> UInt64 {
    let record = try await fileSystem.metadata(at: path)
    guard record.isDirectory else { return record.allocatedBytes }
    var total = record.allocatedBytes
    for try await event in fileSystem.enumerate(root: path, options: Self.subtreeOptions) {
      switch event {
      case .record(let child):
        total += child.allocatedBytes
      case .inaccessible(let unreadable, let reason):
        throw FileSystemError.ioFailure(unreadable, description: reason)
      }
    }
    return total
  }

  /// Strips every execute bit and writes the stamp. The payload is never in
  /// the store uncontained: the strip happens before the reply, and a failure
  /// here fails the whole archive.
  private func contain(
    _ storedPath: AbsolutePath,
    stamping report: PrivilegedArchiveReport
  ) async throws {
    try await fileSystem.setPosixPermissions(
      report.metadata.posixPermissions & ~0o111, at: storedPath)
    let encoded = try JSONEncoder().encode(report)
    var attributes = try await fileSystem.extendedAttributes(at: storedPath)
    attributes[Self.stampName] = encoded
    try await fileSystem.setExtendedAttributes(attributes, at: storedPath)
  }

  // MARK: - Acting on an archive already made

  func describe(at storedPath: AbsolutePath) async throws -> PrivilegedArchiveReport {
    try await provenReport(at: storedPath)
  }

  /// Puts the payload back where its own stamp says it came from. The origin
  /// is checked like any other target and must be vacant, so a restore can
  /// reverse what this helper did and can never replace what is there now.
  func restore(
    at storedPath: AbsolutePath,
    admitting isAdmitted: (AbsolutePath) -> Bool
  ) async throws -> AbsolutePath {
    let report = try await provenReport(at: storedPath)
    let originPath = report.originPath
    guard isAdmitted(originPath) else {
      throw FileSystemError.ioFailure(originPath, description: Self.originRefusedSentence)
    }
    guard await !fileSystem.exists(originPath) else {
      throw FileSystemError.destinationOccupied(originPath)
    }
    try await fileSystem.move(storedPath, to: originPath)
    // The snapshot was taken before the stamp existed, so writing it back
    // removes the stamp as a consequence of restoring what was there.
    try await fileSystem.setExtendedAttributes(
      report.metadata.extendedAttributes, at: originPath)
    try await fileSystem.setPosixPermissions(report.metadata.posixPermissions, at: originPath)
    return originPath
  }

  func discard(at storedPath: AbsolutePath) async throws {
    _ = try await provenReport(at: storedPath)
    try await fileSystem.delete(storedPath)
  }

  /// The provenance check: the payload must be root owned and must carry the
  /// stamp this helper wrote when it archived it.
  ///
  /// The user owns the store directory, so anything running as that user can
  /// plant a file in it. What cannot be forged without root is a root owned
  /// file, and that is the whole basis of this check.
  private func provenReport(at storedPath: AbsolutePath) async throws -> PrivilegedArchiveReport {
    guard try isRootOwned(storedPath) else {
      throw FileSystemError.ioFailure(storedPath, description: Self.notOursSentence)
    }
    let attributes = try await fileSystem.extendedAttributes(at: storedPath)
    guard let stamp = attributes[Self.stampName],
      let report = try? JSONDecoder().decode(PrivilegedArchiveReport.self, from: stamp)
    else {
      throw FileSystemError.ioFailure(storedPath, description: Self.notOursSentence)
    }
    return report
  }

  private func isRootOwned(_ path: AbsolutePath) throws -> Bool {
    var record = stat()
    guard lstat(path.value, &record) == 0 else {
      throw FileSystemError.notFound(path)
    }
    return record.st_uid == 0
  }

  private static let root = AbsolutePath(normalising: "/")
  private static let subtreeOptions = EnumerationOptions(
    includesHiddenFiles: true, descendsIntoPackages: true)

  private static let crossVolumeSentence =
    "The item and the SafetyNet store are on different volumes, so it was left where it was."
  private static let noParentSentence =
    "The SafetyNet payload path has no directory to sit in."
  private static let notOursSentence =
    "That payload was not put there by MacGleam's privileged helper, so it was left alone."
  private static let originRefusedSentence =
    "The place this came from is not one the privileged helper may write to."
}

/// What the destination stage can see of the real disk: whether a directory is
/// there, and whether a component is a symbolic link. It follows nothing,
/// because an answer about what a link points at says nothing about the link.
struct HelperDiskPaths: HelperPathInspecting {
  func directoryExists(at path: AbsolutePath) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path.value, isDirectory: &isDirectory) else {
      return false
    }
    return isDirectory.boolValue && !isSymbolicLink(at: path)
  }

  func isSymbolicLink(at path: AbsolutePath) -> Bool {
    var record = stat()
    guard lstat(path.value, &record) == 0 else { return false }
    return (record.st_mode & S_IFMT) == S_IFLNK
  }
}
