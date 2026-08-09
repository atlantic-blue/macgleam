import Foundation
import GleamCore
import Testing

/// The seeding surface of the in memory implementation. Engine tests across
/// the project build fixture trees through it, so seeded values must come
/// back exactly; the shared conformance suite only asserts relations because
/// the real disk sets its own timestamps.
@Suite("In memory file system seeding")
struct InMemoryFileSystemSeedingTests {

  @Test("a fresh instance holds only the root directory")
  func freshInstanceHoldsOnlyTheRoot() async throws {
    let fileSystem = InMemoryFileSystem()
    let root = Fixture.path("/")
    #expect(await fileSystem.exists(root))
    let outcome = try await collectEnumeration(
      fileSystem.enumerate(root: root, options: .default)
    )
    #expect(outcome.records.isEmpty)
    #expect(outcome.inaccessible.isEmpty)
  }

  @Test("seeded dates come back exactly through metadata")
  func seededDatesComeBackExactly() async throws {
    let fileSystem = InMemoryFileSystem()
    let directory = Fixture.path("/data")
    let file = Fixture.path("/data/sample.txt")
    await fileSystem.seedDirectory(at: directory)
    await fileSystem.seedFile(
      at: file,
      contents: FileSystemFixture.contents(40),
      isExecutable: false,
      created: FileSystemFixture.createdDate,
      modified: FileSystemFixture.modifiedDate,
      lastOpened: FileSystemFixture.lastOpenedDate,
      extendedAttributes: [:]
    )
    let record = try await fileSystem.metadata(at: file)
    #expect(record.created == FileSystemFixture.createdDate)
    #expect(record.modified == FileSystemFixture.modifiedDate)
    #expect(record.lastOpened == FileSystemFixture.lastOpenedDate)
  }

  @Test("seeded contents come back exactly through readData")
  func seededContentsComeBackExactly() async throws {
    let fileSystem = InMemoryFileSystem()
    let file = Fixture.path("/sample.bin")
    let contents = FileSystemFixture.contents(41, length: 128)
    await fileSystem.seedFile(
      at: file,
      contents: contents,
      isExecutable: false,
      created: FileSystemFixture.createdDate,
      modified: FileSystemFixture.modifiedDate,
      lastOpened: nil,
      extendedAttributes: [:]
    )
    let read = try await fileSystem.readData(at: file, maxBytes: 1_000_000)
    #expect(read == contents)
  }
}
