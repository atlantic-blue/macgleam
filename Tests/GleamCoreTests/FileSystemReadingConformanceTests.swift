import Foundation
import GleamCore
import Testing

/// The reading half of the C13 conformance suite. Every test runs against
/// both the in memory implementation and the real disk in a temporary
/// directory; the behaviours asserted here are the contract, so the two
/// implementations may never disagree.
private let readingTree = FixtureTree(
  directories: ["tools", "caches/com.example", "empty"],
  files: [
    FixtureFile(
      relativePath: "notes.txt",
      contents: FileSystemFixture.contents(1),
      extendedAttributes: [FileSystemFixture.attributeName: FileSystemFixture.attributeValue]
    ),
    FixtureFile(
      relativePath: "payload.bin",
      contents: FileSystemFixture.contents(2, length: 8192)
    ),
    FixtureFile(
      relativePath: "tools/runme",
      contents: FileSystemFixture.contents(3),
      isExecutable: true
    ),
    FixtureFile(
      relativePath: "caches/com.example/cache.dat",
      contents: FileSystemFixture.contents(4)
    ),
  ]
)

@Suite("File system conformance: existence")
struct FileSystemExistenceConformanceTests {

  @Test("exists is true for a seeded file", arguments: FileSystemKind.allCases)
  func existsIsTrueForSeededFile(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      #expect(await harness.fileSystem.exists(harness.root.appending("notes.txt")))
    }
  }

  @Test("exists is true for a seeded directory", arguments: FileSystemKind.allCases)
  func existsIsTrueForSeededDirectory(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      #expect(await harness.fileSystem.exists(harness.root.appending("caches/com.example")))
    }
  }

  @Test("exists is false for an absent path", arguments: FileSystemKind.allCases)
  func existsIsFalseForAbsentPath(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      #expect(!(await harness.fileSystem.exists(harness.root.appending("never-created.txt"))))
    }
  }
}

@Suite("File system conformance: metadata")
struct FileSystemMetadataConformanceTests {

  @Test(
    "metadata echoes the path and marks a file as not a directory",
    arguments: FileSystemKind.allCases)
  func metadataDescribesFile(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let path = harness.root.appending("notes.txt")
      let record = try await harness.fileSystem.metadata(at: path)
      #expect(record.path == path)
      #expect(!record.isDirectory)
    }
  }

  @Test("metadata marks a directory as a directory", arguments: FileSystemKind.allCases)
  func metadataDescribesDirectory(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let record = try await harness.fileSystem.metadata(at: harness.root.appending("tools"))
      #expect(record.isDirectory)
    }
  }

  @Test("allocated bytes cover the logical size of a file", arguments: FileSystemKind.allCases)
  func allocatedBytesCoverLogicalSize(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let record = try await harness.fileSystem.metadata(at: harness.root.appending("payload.bin"))
      #expect(record.allocatedBytes >= 8192)
    }
  }

  @Test(
    "created and modified dates are present and created is not after modified",
    arguments: FileSystemKind.allCases)
  func datesArePresentAndOrdered(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let record = try await harness.fileSystem.metadata(at: harness.root.appending("notes.txt"))
      let created = try #require(record.created)
      let modified = try #require(record.modified)
      #expect(created <= modified)
    }
  }

  @Test("metadata reports the executable bit", arguments: FileSystemKind.allCases)
  func metadataReportsExecutableBit(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let executable = try await harness.fileSystem.metadata(
        at: harness.root.appending("tools/runme"))
      let plain = try await harness.fileSystem.metadata(at: harness.root.appending("notes.txt"))
      #expect(executable.isExecutable)
      #expect(!plain.isExecutable)
    }
  }

  @Test("metadata for a missing path throws notFound", arguments: FileSystemKind.allCases)
  func metadataThrowsNotFoundForMissingPath(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let missing = harness.root.appending("never-created.txt")
      await #expect(throws: FileSystemError.notFound(missing)) {
        _ = try await harness.fileSystem.metadata(at: missing)
      }
    }
  }

  @Test(
    "two files on one volume have distinct file identifiers and one volume identifier",
    arguments: FileSystemKind.allCases)
  func distinctFilesHaveDistinctIdentifiers(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let first = try await harness.fileSystem.metadata(at: harness.root.appending("notes.txt"))
      let second = try await harness.fileSystem.metadata(at: harness.root.appending("payload.bin"))
      #expect(first.fileID != second.fileID)
      #expect(first.volumeID == second.volumeID)
    }
  }
}

/// Modes chosen so no constant can satisfy the round trip and so
/// `FileRecord.isExecutable` cannot stand in for any of it: 0o600 and 0o644
/// differ only in bits that boolean never sees, 0o700 and 0o755 are identical
/// through it, and 0o751 gives the owner, group and other triples three
/// different values.
private let exactModes: [UInt16] = [0o600, 0o644, 0o700, 0o751, 0o755]

/// The three bits above the permission triples. A restore reinstates the
/// mode bit for bit, so a setuid binary that comes back without its setuid
/// bit is a broken restore and a sticky directory that loses its sticky bit
/// is another.
private let specialBitModes: [UInt16] = [0o4755, 0o2711, 0o1755]

@Suite("File system conformance: permission modes")
struct FileSystemPermissionModeConformanceTests {

  @Test(
    "posixPermissions returns the exact mode a file carries",
    arguments: FileSystemKind.allCases, exactModes)
  func exactModeIsReportedForAFile(kind: FileSystemKind, mode: UInt16) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let path = harness.root.appending("notes.txt")
      try await harness.fileSystem.setPosixPermissions(mode, at: path)
      #expect(try await harness.fileSystem.posixPermissions(at: path) == mode)
    }
  }

  @Test(
    "posixPermissions reports the setuid, setgid and sticky bits",
    arguments: FileSystemKind.allCases, specialBitModes)
  func specialBitsAreReported(kind: FileSystemKind, mode: UInt16) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let path = harness.root.appending("tools/runme")
      try await harness.fileSystem.setPosixPermissions(mode, at: path)
      #expect(try await harness.fileSystem.posixPermissions(at: path) == mode)
    }
  }

  @Test(
    "posixPermissions tells apart two files the executable bit cannot",
    arguments: FileSystemKind.allCases)
  func modesAgreeingOnTheExecutableBitAreStillDistinct(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let shared = harness.root.appending("tools/runme")
      let restricted = harness.root.appending("payload.bin")
      try await harness.fileSystem.setPosixPermissions(0o755, at: shared)
      try await harness.fileSystem.setPosixPermissions(0o700, at: restricted)
      let sharedRecord = try await harness.fileSystem.metadata(at: shared)
      let privateRecord = try await harness.fileSystem.metadata(at: restricted)
      // The lossy derivation agrees, which is exactly why the exact read exists.
      #expect(sharedRecord.isExecutable == privateRecord.isExecutable)
      #expect(try await harness.fileSystem.posixPermissions(at: shared) == 0o755)
      #expect(try await harness.fileSystem.posixPermissions(at: restricted) == 0o700)
    }
  }

  @Test(
    "a directory's mode comes back exactly and carries no file type bits",
    arguments: FileSystemKind.allCases)
  func directoryModeCarriesNoFileTypeBits(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let directory = harness.root.appending("tools")
      try await harness.fileSystem.setPosixPermissions(0o750, at: directory)
      let mode = try await harness.fileSystem.posixPermissions(at: directory)
      #expect(mode == 0o750)
      #expect(mode & ~0o7777 == 0)
      // The harness tears down through this directory.
      try await harness.fileSystem.setPosixPermissions(0o755, at: directory)
    }
  }

  @Test(
    "posixPermissions for a missing path throws notFound rather than defaulting",
    arguments: FileSystemKind.allCases)
  func posixPermissionsThrowsNotFoundForMissingPath(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let missing = harness.root.appending("never-created.txt")
      await #expect(throws: FileSystemError.notFound(missing)) {
        _ = try await harness.fileSystem.posixPermissions(at: missing)
      }
    }
  }
}

@Suite("File system conformance: reading data")
struct FileSystemReadDataConformanceTests {

  @Test(
    "readData returns the full contents when maxBytes is ample", arguments: FileSystemKind.allCases)
  func readDataReturnsFullContents(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let data = try await harness.fileSystem.readData(
        at: harness.root.appending("notes.txt"),
        maxBytes: 1_000_000
      )
      #expect(data == FileSystemFixture.contents(1))
    }
  }

  @Test(
    "readData reads at most maxBytes, from the start of the file",
    arguments: FileSystemKind.allCases)
  func readDataTruncatesToMaxBytes(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let data = try await harness.fileSystem.readData(
        at: harness.root.appending("notes.txt"),
        maxBytes: 5
      )
      #expect(data == FileSystemFixture.contents(1).prefix(5))
    }
  }

  @Test("readData for a missing path throws notFound", arguments: FileSystemKind.allCases)
  func readDataThrowsNotFoundForMissingPath(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let missing = harness.root.appending("never-created.txt")
      await #expect(throws: FileSystemError.notFound(missing)) {
        _ = try await harness.fileSystem.readData(at: missing, maxBytes: 1_000_000)
      }
    }
  }

  @Test("extendedAttributes returns every seeded attribute", arguments: FileSystemKind.allCases)
  func extendedAttributesReturnSeededValues(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let attributes = try await harness.fileSystem.extendedAttributes(
        at: harness.root.appending("notes.txt")
      )
      // Superset assertion: the platform may attach attributes of its own,
      // and those are not a conformance failure.
      #expect(attributes[FileSystemFixture.attributeName] == FileSystemFixture.attributeValue)
    }
  }
}

@Suite("File system conformance: volumes")
struct FileSystemVolumeConformanceTests {

  @Test(
    "volumeInfo agrees with the volume identifier on file records",
    arguments: FileSystemKind.allCases)
  func volumeInfoAgreesWithRecords(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let info = try await harness.fileSystem.volumeInfo(at: harness.root)
      let record = try await harness.fileSystem.metadata(at: harness.root.appending("notes.txt"))
      #expect(info.volumeID == record.volumeID)
    }
  }

  @Test("volumeInfo figures are coherent", arguments: FileSystemKind.allCases)
  func volumeInfoFiguresAreCoherent(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let info = try await harness.fileSystem.volumeInfo(at: harness.root)
      #expect(info.capacityBytes > 0)
      #expect(info.availableBytes <= info.capacityBytes)
      #expect(harness.root == info.root || harness.root.isDescendant(of: info.root))
    }
  }
}

@Suite("File system conformance: enumeration")
struct FileSystemEnumerationConformanceTests {

  @Test(
    "enumeration yields every seeded entry exactly once and never the root itself",
    arguments: FileSystemKind.allCases)
  func enumerationYieldsEverySeededEntryExactlyOnce(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let outcome = try await collectEnumeration(
        harness.fileSystem.enumerate(root: harness.root, options: .default)
      )
      #expect(outcome.recordPaths == readingTree.allPaths(under: harness.root))
      #expect(outcome.records.count == readingTree.allPaths(under: harness.root).count)
      #expect(!outcome.recordPaths.contains(harness.root))
    }
  }

  @Test("enumeration never repeats a (volumeID, fileID) pair", arguments: FileSystemKind.allCases)
  func enumerationNeverRepeatsAFileIdentity(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let outcome = try await collectEnumeration(
        harness.fileSystem.enumerate(root: harness.root, options: .default)
      )
      #expect(outcome.identities.count == Set(outcome.identities).count)
    }
  }

  @Test(
    "an enumerated record agrees with metadata for the same path",
    arguments: FileSystemKind.allCases)
  func enumeratedRecordsAgreeWithMetadata(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let path = harness.root.appending("payload.bin")
      let outcome = try await collectEnumeration(
        harness.fileSystem.enumerate(root: harness.root, options: .default)
      )
      let enumerated = try #require(outcome.record(at: path))
      let direct = try await harness.fileSystem.metadata(at: path)
      #expect(enumerated.fileID == direct.fileID)
      #expect(enumerated.volumeID == direct.volumeID)
      #expect(enumerated.allocatedBytes == direct.allocatedBytes)
      #expect(enumerated.isDirectory == direct.isDirectory)
    }
  }

  @Test(
    "enumeration yields nothing at or under a skipped subtree and still yields siblings",
    arguments: FileSystemKind.allCases)
  func enumerationSkipsRequestedSubtrees(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: readingTree) { harness in
      let skipped = harness.root.appending("caches")
      let outcome = try await collectEnumeration(
        harness.fileSystem.enumerate(
          root: harness.root,
          options: makeEnumerationOptions(skipSubtrees: [skipped])
        )
      )
      let underSkipped = outcome.recordPaths.filter {
        $0 == skipped || $0.isDescendant(of: skipped)
      }
      #expect(underSkipped.isEmpty)
      #expect(outcome.recordPaths.contains(harness.root.appending("notes.txt")))
    }
  }

  @Test(
    "enumeration omits dot prefixed entries when hidden files are excluded",
    arguments: FileSystemKind.allCases)
  func enumerationOmitsHiddenFilesWhenExcluded(kind: FileSystemKind) async throws {
    let tree = FixtureTree(files: [
      FixtureFile(relativePath: ".secret", contents: FileSystemFixture.contents(5)),
      FixtureFile(relativePath: "shown.txt", contents: FileSystemFixture.contents(6)),
    ])
    try await withHarness(kind, tree: tree) { harness in
      let outcome = try await collectEnumeration(
        harness.fileSystem.enumerate(
          root: harness.root,
          options: makeEnumerationOptions(includesHiddenFiles: false)
        )
      )
      #expect(!outcome.recordPaths.contains(harness.root.appending(".secret")))
      #expect(outcome.recordPaths.contains(harness.root.appending("shown.txt")))
    }
  }

  @Test(
    "enumeration includes dot prefixed entries when hidden files are included",
    arguments: FileSystemKind.allCases)
  func enumerationIncludesHiddenFilesWhenIncluded(kind: FileSystemKind) async throws {
    let tree = FixtureTree(files: [
      FixtureFile(relativePath: ".secret", contents: FileSystemFixture.contents(5)),
      FixtureFile(relativePath: "shown.txt", contents: FileSystemFixture.contents(6)),
    ])
    try await withHarness(kind, tree: tree) { harness in
      let outcome = try await collectEnumeration(
        harness.fileSystem.enumerate(
          root: harness.root,
          options: makeEnumerationOptions(includesHiddenFiles: true)
        )
      )
      #expect(outcome.recordPaths.contains(harness.root.appending(".secret")))
      #expect(outcome.recordPaths.contains(harness.root.appending("shown.txt")))
    }
  }

  @Test(
    "enumeration yields a package but not its contents when not descending into packages",
    arguments: FileSystemKind.allCases)
  func enumerationStopsAtPackageBoundary(kind: FileSystemKind) async throws {
    let tree = FixtureTree(
      directories: ["Sample.app/Contents"],
      files: [
        FixtureFile(
          relativePath: "Sample.app/Contents/Info.plist", contents: FileSystemFixture.contents(7)),
        FixtureFile(relativePath: "beside.txt", contents: FileSystemFixture.contents(8)),
      ]
    )
    try await withHarness(kind, tree: tree) { harness in
      let package = harness.root.appending("Sample.app")
      let outcome = try await collectEnumeration(
        harness.fileSystem.enumerate(
          root: harness.root,
          options: makeEnumerationOptions(descendsIntoPackages: false)
        )
      )
      #expect(outcome.recordPaths.contains(package))
      let insidePackage = outcome.recordPaths.filter { $0.isDescendant(of: package) }
      #expect(insidePackage.isEmpty)
      #expect(outcome.recordPaths.contains(harness.root.appending("beside.txt")))
    }
  }

  @Test("enumeration descends into packages when asked", arguments: FileSystemKind.allCases)
  func enumerationDescendsIntoPackagesWhenAsked(kind: FileSystemKind) async throws {
    let tree = FixtureTree(
      directories: ["Sample.app/Contents"],
      files: [
        FixtureFile(
          relativePath: "Sample.app/Contents/Info.plist", contents: FileSystemFixture.contents(7))
      ]
    )
    try await withHarness(kind, tree: tree) { harness in
      let outcome = try await collectEnumeration(
        harness.fileSystem.enumerate(
          root: harness.root,
          options: makeEnumerationOptions(descendsIntoPackages: true)
        )
      )
      #expect(
        outcome.recordPaths.contains(harness.root.appending("Sample.app/Contents/Info.plist")))
    }
  }

  @Test(
    "an unreadable directory is reported as inaccessible and siblings still enumerate",
    arguments: FileSystemKind.allCases)
  func unreadableDirectoryIsReportedNotThrown(kind: FileSystemKind) async throws {
    let tree = FixtureTree(
      directories: ["locked", "open"],
      files: [
        FixtureFile(relativePath: "locked/inside.txt", contents: FileSystemFixture.contents(9)),
        FixtureFile(relativePath: "open/visible.txt", contents: FileSystemFixture.contents(10)),
      ]
    )
    try await withHarness(kind, tree: tree) { harness in
      let locked = harness.root.appending("locked")
      try await harness.fileSystem.setPosixPermissions(0o000, at: locked)
      // Collecting to completion is itself the assertion that one locked
      // folder never sinks the scan: nothing may throw out of the stream.
      let outcome = try await collectEnumeration(
        harness.fileSystem.enumerate(root: harness.root, options: .default)
      )
      let reported = outcome.inaccessible.filter { $0.path == locked }
      #expect(reported.count == 1)
      #expect(!(reported.first?.reason.isEmpty ?? true))
      #expect(outcome.recordPaths.contains(harness.root.appending("open/visible.txt")))
      #expect(!outcome.recordPaths.contains(harness.root.appending("locked/inside.txt")))
    }
  }
}

@Suite("File system conformance: cancellation")
struct FileSystemCancellationConformanceTests {

  private static func makeWideTree() -> FixtureTree {
    var tree = FixtureTree()
    for directoryIndex in 0..<4 {
      tree.directories.append("dir\(directoryIndex)")
      for fileIndex in 0..<10 {
        tree.files.append(
          FixtureFile(
            relativePath: "dir\(directoryIndex)/file\(fileIndex).txt",
            contents: FileSystemFixture.contents(UInt8(directoryIndex * 10 + fileIndex))
          )
        )
      }
    }
    return tree
  }

  @Test(
    "cancelling the consuming task ends enumeration promptly and touches nothing",
    arguments: FileSystemKind.allCases)
  func cancellationEndsEnumerationAndTouchesNothing(kind: FileSystemKind) async throws {
    let tree = Self.makeWideTree()
    try await withHarness(kind, tree: tree) { harness in
      let stream = harness.fileSystem.enumerate(root: harness.root, options: .default)
      let (firstRecordSeen, firstRecordContinuation) = AsyncStream.makeStream(of: Void.self)
      let consumer = Task {
        var seen = 0
        do {
          for try await event in stream {
            if case .record = event {
              seen += 1
              if seen == 1 {
                firstRecordContinuation.yield()
              }
            }
          }
        } catch {
          // A stream ending in cancellation is acceptable; the assertion
          // is that it ends promptly and mutated nothing.
        }
        return seen
      }
      var signal = firstRecordSeen.makeAsyncIterator()
      _ = await signal.next()
      consumer.cancel()
      let endedPromptly = await completesPromptly {
        _ = await consumer.value
      }
      #expect(endedPromptly, "enumeration kept running after the consuming task was cancelled")

      var missing: [AbsolutePath] = []
      for path in tree.allPaths(under: harness.root) {
        if !(await harness.fileSystem.exists(path)) {
          missing.append(path)
        }
      }
      #expect(missing.isEmpty)
      let untouched = try await harness.fileSystem.readData(
        at: harness.root.appending("dir0/file0.txt"),
        maxBytes: 1_000_000
      )
      #expect(untouched == FileSystemFixture.contents(0))
    }
  }
}
