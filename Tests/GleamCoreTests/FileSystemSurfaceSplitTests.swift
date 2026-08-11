import Foundation
import GleamCore
import Testing

/// This conformance is the compile time proof of the C13 and C14 split: it
/// builds only if the reading protocol requires no mutating member. Engines
/// receive `any FileSystemReading`, so a type shaped like this is all an
/// engine can ever hold, and the mutating protocol stays the only deleting
/// surface in the process.
private struct ReadingOnlyFileSystem: FileSystemReading {

  func enumerate(
    root: AbsolutePath,
    options: EnumerationOptions
  ) -> AsyncThrowingStream<EnumerationEvent, Error> {
    AsyncThrowingStream { continuation in
      continuation.finish()
    }
  }

  func metadata(at path: AbsolutePath) async throws -> FileRecord {
    throw FileSystemError.notFound(path)
  }

  func posixPermissions(at path: AbsolutePath) async throws -> UInt16 {
    throw FileSystemError.notFound(path)
  }

  func readData(at path: AbsolutePath, maxBytes: UInt64) async throws -> Data {
    throw FileSystemError.notFound(path)
  }

  func extendedAttributes(at path: AbsolutePath) async throws -> [String: Data] {
    throw FileSystemError.notFound(path)
  }

  func exists(_ path: AbsolutePath) async -> Bool {
    false
  }

  func volumeInfo(at path: AbsolutePath) async throws -> VolumeInfo {
    throw FileSystemError.volumeUnavailable(path)
  }
}

/// The mirror image, and the compile time proof for the other side: this
/// builds only if `writeData` is a member of the mutating protocol. An
/// implementation that put a byte writing method on the reading side would
/// fail to compile here and in the type above at once.
private struct WritingOnlyFileSystem: FileSystemMutating {

  func moveToTrash(_ path: AbsolutePath) async throws -> AbsolutePath {
    throw FileSystemError.notFound(path)
  }

  func move(_ source: AbsolutePath, to destination: AbsolutePath) async throws {
    throw FileSystemError.notFound(source)
  }

  func delete(_ path: AbsolutePath) async throws {
    throw FileSystemError.notFound(path)
  }

  func createDirectory(at path: AbsolutePath) async throws {
    throw FileSystemError.permissionDenied(path)
  }

  func writeData(_ data: Data, to path: AbsolutePath) async throws {
    throw FileSystemError.permissionDenied(path)
  }

  func setPosixPermissions(_ mode: UInt16, at path: AbsolutePath) async throws {
    throw FileSystemError.notFound(path)
  }

  func setExtendedAttributes(_ attributes: [String: Data], at path: AbsolutePath) async throws {
    throw FileSystemError.notFound(path)
  }
}

@Suite("Reading and mutating split")
struct FileSystemSurfaceSplitTests {

  @Test("a reading only conformance is possible and is not a mutating file system")
  func readingOnlyConformanceIsNotMutating() {
    let readingOnly: Any = ReadingOnlyFileSystem()
    #expect(!(readingOnly is any FileSystemMutating))
  }

  @Test("a mutating only conformance is possible and is not a reading file system")
  func mutatingOnlyConformanceIsNotReading() {
    let writingOnly: Any = WritingOnlyFileSystem()
    #expect(!(writingOnly is any FileSystemReading))
  }

  @Test("the combined FileSystem alias carries both the reading and the mutating side")
  func combinedAliasCarriesBothSides() {
    // The typed assignment is the compile time half of the assertion.
    let combined: any FileSystem = InMemoryFileSystem()
    let erased: Any = combined
    #expect(erased is any FileSystemReading)
    #expect(erased is any FileSystemMutating)
  }
}
