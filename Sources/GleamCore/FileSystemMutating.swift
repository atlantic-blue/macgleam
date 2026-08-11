import Foundation

/// The write side. Held only by the executor and the SafetyNet store in the
/// user process, and by the helper's own implementation in the root process.
/// Engines can never reach it.
///
/// Moves are atomic per item: on any failure the source is intact at its
/// original path, and cross volume moves preserve metadata and extended
/// attributes or fail whole. Trash uses the platform trash for the item's
/// volume and returns the resulting location.
public protocol FileSystemMutating: Sendable {
  func moveToTrash(_ path: AbsolutePath) async throws -> AbsolutePath
  func move(_ source: AbsolutePath, to destination: AbsolutePath) async throws
  func delete(_ path: AbsolutePath) async throws
  func createDirectory(at path: AbsolutePath) async throws
  /// Replaces the file's contents whole, creating it when absent, and
  /// atomically: a reader sees the previous contents or the new contents and
  /// never a prefix. Writes a file and only a file, so a missing parent
  /// directory throws `notFound` rather than growing a tree.
  func writeData(_ data: Data, to path: AbsolutePath) async throws
  func setPosixPermissions(_ mode: UInt16, at path: AbsolutePath) async throws
  func setExtendedAttributes(_ attributes: [String: Data], at path: AbsolutePath) async throws
}

public typealias FileSystem = FileSystemReading & FileSystemMutating

public enum FileSystemError: Error, Sendable, Equatable {
  case notFound(AbsolutePath)
  case permissionDenied(AbsolutePath)
  case destinationOccupied(AbsolutePath)
  case volumeUnavailable(AbsolutePath)
  case ioFailure(AbsolutePath, description: String)
}

extension FileSystemError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .notFound(let path):
      return "Nothing exists at \(path.value)."
    case .permissionDenied(let path):
      return "Permission was denied for \(path.value)."
    case .destinationOccupied(let path):
      return "Something already exists at \(path.value)."
    case .volumeUnavailable(let path):
      return "The volume holding \(path.value) is unavailable."
    case .ioFailure(let path, let description):
      return "Reading or writing \(path.value) failed: \(description)"
    }
  }
}
