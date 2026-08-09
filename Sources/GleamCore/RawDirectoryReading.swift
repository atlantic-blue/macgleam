import Foundation

/// The single primitive the enumeration engine is built on: list the
/// immediate children of one directory as full records. Implementations may
/// repeat entries (the platform sometimes does); the enumerator deduplicates.
///
/// Errors are typed `FileSystemError` values. A throwing directory is
/// reported by the enumerator as inaccessible, except `volumeUnavailable`,
/// which fails the whole enumeration.
public protocol RawDirectoryReading: Sendable {
  func children(of directory: AbsolutePath) async throws -> [FileRecord]
}
