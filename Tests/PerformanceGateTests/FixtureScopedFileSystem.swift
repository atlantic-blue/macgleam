import Foundation
import GleamCore

/// Every root an engine asked to enumerate, in request order. Recorded so a
/// gate can prove it measured one pass over the fixture: an engine that
/// enumerated three roots would scan the fixture three times and the elapsed
/// figure would silently mean something else.
final class EnumerationRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var roots: [String] = []

  func record(_ root: AbsolutePath) {
    lock.lock()
    defer { lock.unlock() }
    roots.append(root.value)
  }

  var requestedRoots: [String] {
    lock.lock()
    defer { lock.unlock() }
    return roots
  }
}

/// A real `DiskFileSystem` with exactly one redirect: the volume root an
/// engine asks to enumerate is served from the fixture subtree instead.
///
/// The redirect exists because a Cleanup scan takes no scope. `ScanContext`
/// (C15) carries a file system, rules, settings and the access flag, and the
/// engine enumerates the whole volume from `/`, so pointed at the real disk
/// the gate would measure whatever happens to sit on the machine running it:
/// unbounded, unrepeatable, and different on every developer's laptop.
///
/// Nothing is faked. Enumeration is `DiskFileSystem`'s own real enumeration
/// (the same code path the app runs, over real directories the fixture just
/// created), and every other method delegates untouched, so metadata, byte
/// sizes, volume lookups and reads all hit the real kernel. Only the starting
/// point moves.
struct FixtureScopedDiskFileSystem: FileSystemReading {
  let fixtureRoot: AbsolutePath
  let recorder: EnumerationRecorder

  private let disk = DiskFileSystem()

  func enumerate(
    root: AbsolutePath,
    options: EnumerationOptions
  ) -> AsyncThrowingStream<EnumerationEvent, Error> {
    recorder.record(root)
    return disk.enumerate(root: fixtureRoot, options: options)
  }

  func metadata(at path: AbsolutePath) async throws -> FileRecord {
    try await disk.metadata(at: path)
  }

  func posixPermissions(at path: AbsolutePath) async throws -> UInt16 {
    try await disk.posixPermissions(at: path)
  }

  func readData(at path: AbsolutePath, maxBytes: UInt64) async throws -> Data {
    try await disk.readData(at: path, maxBytes: maxBytes)
  }

  func extendedAttributes(at path: AbsolutePath) async throws -> [String: Data] {
    try await disk.extendedAttributes(at: path)
  }

  func exists(_ path: AbsolutePath) async -> Bool {
    await disk.exists(path)
  }

  func volumeInfo(at path: AbsolutePath) async throws -> VolumeInfo {
    try await disk.volumeInfo(at: path)
  }
}
