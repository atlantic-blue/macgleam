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

@Suite("Reading and mutating split")
struct FileSystemSurfaceSplitTests {

  @Test("a reading only conformance is possible and is not a mutating file system")
  func readingOnlyConformanceIsNotMutating() {
    let readingOnly: Any = ReadingOnlyFileSystem()
    #expect(!(readingOnly is any FileSystemMutating))
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
