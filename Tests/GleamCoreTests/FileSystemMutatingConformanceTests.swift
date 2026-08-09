import Foundation
import GleamCore
import Testing

/// The mutating half of the C14 conformance suite, run against both
/// implementations. The trash tests assert through the contract's own
/// surface only: the returned location exists, holds the contents, and the
/// source is gone. Where the location actually is belongs to the
/// implementation.
@Suite("File system conformance: trash")
struct FileSystemTrashConformanceTests {

  @Test(
    "moveToTrash removes the source and returns a distinct location holding the contents",
    arguments: FileSystemKind.allCases)
  func moveToTrashRemovesSourceAndReturnsLocation(kind: FileSystemKind) async throws {
    let contents = FileSystemFixture.contents(20)
    let tree = FixtureTree(files: [
      FixtureFile(relativePath: "doomed.txt", contents: contents)
    ])
    try await withHarness(kind, tree: tree) { harness in
      let source = harness.root.appending("doomed.txt")
      let trashed = try await harness.fileSystem.moveToTrash(source)
      #expect(trashed != source)
      #expect(!(await harness.fileSystem.exists(source)))
      #expect(await harness.fileSystem.exists(trashed))
      let recovered = try await harness.fileSystem.readData(at: trashed, maxBytes: 1_000_000)
      #expect(recovered == contents)
      // The real implementation trashes into the volume trash; remove the
      // fixture file from it so the test leaves nothing behind.
      try? await harness.fileSystem.delete(trashed)
    }
  }

  @Test("moveToTrash of a missing path throws notFound", arguments: FileSystemKind.allCases)
  func moveToTrashThrowsNotFoundForMissingPath(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: FixtureTree()) { harness in
      let missing = harness.root.appending("never-created.txt")
      await #expect(throws: FileSystemError.notFound(missing)) {
        _ = try await harness.fileSystem.moveToTrash(missing)
      }
    }
  }
}

@Suite("File system conformance: moves")
struct FileSystemMoveConformanceTests {

  @Test("move relocates a file with its contents", arguments: FileSystemKind.allCases)
  func moveRelocatesFile(kind: FileSystemKind) async throws {
    let contents = FileSystemFixture.contents(21)
    let tree = FixtureTree(
      directories: ["moved"],
      files: [FixtureFile(relativePath: "a.txt", contents: contents)]
    )
    try await withHarness(kind, tree: tree) { harness in
      let source = harness.root.appending("a.txt")
      let destination = harness.root.appending("moved/a.txt")
      try await harness.fileSystem.move(source, to: destination)
      #expect(!(await harness.fileSystem.exists(source)))
      let relocated = try await harness.fileSystem.readData(at: destination, maxBytes: 1_000_000)
      #expect(relocated == contents)
    }
  }

  @Test("move preserves extended attributes", arguments: FileSystemKind.allCases)
  func movePreservesExtendedAttributes(kind: FileSystemKind) async throws {
    let tree = FixtureTree(files: [
      FixtureFile(
        relativePath: "tagged.txt",
        contents: FileSystemFixture.contents(22),
        extendedAttributes: [FileSystemFixture.attributeName: FileSystemFixture.attributeValue]
      )
    ])
    try await withHarness(kind, tree: tree) { harness in
      let destination = harness.root.appending("renamed.txt")
      try await harness.fileSystem.move(harness.root.appending("tagged.txt"), to: destination)
      let attributes = try await harness.fileSystem.extendedAttributes(at: destination)
      #expect(attributes[FileSystemFixture.attributeName] == FileSystemFixture.attributeValue)
    }
  }

  @Test(
    "move of a missing source throws notFound and creates nothing at the destination",
    arguments: FileSystemKind.allCases)
  func moveThrowsNotFoundForMissingSource(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: FixtureTree(directories: ["moved"])) { harness in
      let source = harness.root.appending("never-created.txt")
      let destination = harness.root.appending("moved/never-created.txt")
      await #expect(throws: FileSystemError.notFound(source)) {
        try await harness.fileSystem.move(source, to: destination)
      }
      #expect(!(await harness.fileSystem.exists(destination)))
    }
  }

  @Test(
    "move onto an occupied destination fails and leaves both sides intact",
    arguments: FileSystemKind.allCases)
  func moveOntoOccupiedDestinationLeavesBothSidesIntact(kind: FileSystemKind) async throws {
    let sourceContents = FileSystemFixture.contents(23)
    let occupierContents = FileSystemFixture.contents(24)
    let tree = FixtureTree(files: [
      FixtureFile(relativePath: "src.txt", contents: sourceContents),
      FixtureFile(relativePath: "occupied.txt", contents: occupierContents),
    ])
    try await withHarness(kind, tree: tree) { harness in
      let source = harness.root.appending("src.txt")
      let destination = harness.root.appending("occupied.txt")
      await #expect(throws: FileSystemError.destinationOccupied(destination)) {
        try await harness.fileSystem.move(source, to: destination)
      }
      let sourceAfter = try await harness.fileSystem.readData(at: source, maxBytes: 1_000_000)
      let destinationAfter = try await harness.fileSystem.readData(
        at: destination, maxBytes: 1_000_000)
      #expect(sourceAfter == sourceContents)
      #expect(destinationAfter == occupierContents)
    }
  }

  @Test(
    "a failing move in a sequence leaves earlier items moved and later items untouched",
    arguments: FileSystemKind.allCases)
  func failingMoveInSequenceIsAtomicPerItem(kind: FileSystemKind) async throws {
    let firstContents = FileSystemFixture.contents(25)
    let secondContents = FileSystemFixture.contents(26)
    let thirdContents = FileSystemFixture.contents(27)
    let occupierContents = FileSystemFixture.contents(28)
    let tree = FixtureTree(
      directories: ["moved"],
      files: [
        FixtureFile(relativePath: "first.txt", contents: firstContents),
        FixtureFile(relativePath: "second.txt", contents: secondContents),
        FixtureFile(relativePath: "third.txt", contents: thirdContents),
        // The unmovable item: its destination is already occupied.
        FixtureFile(relativePath: "moved/second.txt", contents: occupierContents),
      ]
    )
    try await withHarness(kind, tree: tree) { harness in
      let fileSystem = harness.fileSystem
      try await fileSystem.move(
        harness.root.appending("first.txt"),
        to: harness.root.appending("moved/first.txt")
      )
      await #expect(
        throws: FileSystemError.destinationOccupied(harness.root.appending("moved/second.txt"))
      ) {
        try await fileSystem.move(
          harness.root.appending("second.txt"),
          to: harness.root.appending("moved/second.txt")
        )
      }
      // Item one stays moved.
      #expect(!(await fileSystem.exists(harness.root.appending("first.txt"))))
      let movedFirst = try await fileSystem.readData(
        at: harness.root.appending("moved/first.txt"),
        maxBytes: 1_000_000
      )
      #expect(movedFirst == firstContents)
      // The failing item is intact on both sides.
      let secondAfter = try await fileSystem.readData(
        at: harness.root.appending("second.txt"),
        maxBytes: 1_000_000
      )
      let occupierAfter = try await fileSystem.readData(
        at: harness.root.appending("moved/second.txt"),
        maxBytes: 1_000_000
      )
      #expect(secondAfter == secondContents)
      #expect(occupierAfter == occupierContents)
      // The item after the failure is untouched.
      let thirdAfter = try await fileSystem.readData(
        at: harness.root.appending("third.txt"),
        maxBytes: 1_000_000
      )
      #expect(thirdAfter == thirdContents)
      #expect(!(await fileSystem.exists(harness.root.appending("moved/third.txt"))))
    }
  }
}

@Suite("File system conformance: directories and deletion")
struct FileSystemDirectoryAndDeletionConformanceTests {

  @Test(
    "createDirectory creates a directory visible to the reading side",
    arguments: FileSystemKind.allCases)
  func createDirectoryCreatesDirectory(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: FixtureTree()) { harness in
      let made = harness.root.appending("made")
      try await harness.fileSystem.createDirectory(at: made)
      #expect(await harness.fileSystem.exists(made))
      let record = try await harness.fileSystem.metadata(at: made)
      #expect(record.isDirectory)
    }
  }

  @Test("delete removes a file permanently", arguments: FileSystemKind.allCases)
  func deleteRemovesFile(kind: FileSystemKind) async throws {
    let tree = FixtureTree(files: [
      FixtureFile(relativePath: "gone.txt", contents: FileSystemFixture.contents(29))
    ])
    try await withHarness(kind, tree: tree) { harness in
      let path = harness.root.appending("gone.txt")
      try await harness.fileSystem.delete(path)
      #expect(!(await harness.fileSystem.exists(path)))
    }
  }

  @Test("delete removes a directory together with its contents", arguments: FileSystemKind.allCases)
  func deleteRemovesDirectoryAndContents(kind: FileSystemKind) async throws {
    let tree = FixtureTree(
      directories: ["bundle"],
      files: [
        FixtureFile(relativePath: "bundle/child.txt", contents: FileSystemFixture.contents(30))
      ]
    )
    try await withHarness(kind, tree: tree) { harness in
      let directory = harness.root.appending("bundle")
      try await harness.fileSystem.delete(directory)
      #expect(!(await harness.fileSystem.exists(directory)))
      #expect(!(await harness.fileSystem.exists(harness.root.appending("bundle/child.txt"))))
    }
  }

  @Test("delete of a missing path throws notFound", arguments: FileSystemKind.allCases)
  func deleteThrowsNotFoundForMissingPath(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: FixtureTree()) { harness in
      let missing = harness.root.appending("never-created.txt")
      await #expect(throws: FileSystemError.notFound(missing)) {
        try await harness.fileSystem.delete(missing)
      }
    }
  }
}

@Suite("File system conformance: permissions and attributes")
struct FileSystemPermissionsConformanceTests {

  @Test(
    "removing read permission makes readData throw permissionDenied",
    arguments: FileSystemKind.allCases)
  func strippedPermissionsDenyReading(kind: FileSystemKind) async throws {
    let tree = FixtureTree(files: [
      FixtureFile(relativePath: "guarded.txt", contents: FileSystemFixture.contents(31))
    ])
    try await withHarness(kind, tree: tree) { harness in
      let path = harness.root.appending("guarded.txt")
      try await harness.fileSystem.setPosixPermissions(0o000, at: path)
      await #expect(throws: FileSystemError.permissionDenied(path)) {
        _ = try await harness.fileSystem.readData(at: path, maxBytes: 1_000_000)
      }
    }
  }

  @Test(
    "setExtendedAttributes round trips through the reading side", arguments: FileSystemKind.allCases
  )
  func setExtendedAttributesRoundTrips(kind: FileSystemKind) async throws {
    let tree = FixtureTree(files: [
      FixtureFile(relativePath: "plain.txt", contents: FileSystemFixture.contents(32))
    ])
    try await withHarness(kind, tree: tree) { harness in
      let path = harness.root.appending("plain.txt")
      try await harness.fileSystem.setExtendedAttributes(
        [FileSystemFixture.attributeName: FileSystemFixture.attributeValue],
        at: path
      )
      let attributes = try await harness.fileSystem.extendedAttributes(at: path)
      #expect(attributes[FileSystemFixture.attributeName] == FileSystemFixture.attributeValue)
    }
  }
}
