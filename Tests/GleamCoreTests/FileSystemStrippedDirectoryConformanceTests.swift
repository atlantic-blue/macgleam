import Foundation
import GleamCore
import Testing

/// C13, a directory whose execute bits are all clear. Part of the shared
/// conformance suite, so every case here runs against the in memory
/// implementation and against the real disk in a temporary directory.
///
/// This is the case that hid the SafetyNet sizing defect of 2026-08-11
/// (GRAPH.md s4e). C18 strips execute from every payload it stores so a
/// quarantined bundle cannot run; on a real volume that also removes
/// traversal, so nothing inside the directory can be reached through it. The
/// in memory implementation traversed such a directory happily, the store
/// sized its own directory payloads to nothing on a real machine, and no test
/// said a word.
///
/// The disk is the reference. An in memory implementation that traverses a
/// stripped directory is wrong, however convenient it is to seed, so the fake
/// is the side that moves.
private let strippedTree = FixtureTree(
  directories: ["payload", "payload/nested", "beside"],
  files: [
    FixtureFile(relativePath: "payload/inside.txt", contents: FileSystemFixture.contents(60)),
    FixtureFile(
      relativePath: "payload/nested/deep.bin",
      contents: FileSystemFixture.contents(61, length: 4096)
    ),
    FixtureFile(relativePath: "beside/visible.txt", contents: FileSystemFixture.contents(62)),
  ]
)

/// The mode the SafetyNet store leaves on a payload: execute cleared, every
/// other bit as it was. Read stays set on purpose, because the distinction
/// this suite exists for is between a directory nobody may read at all (mode
/// 0o000, covered elsewhere) and one whose execute bits alone are gone. An
/// implementation that decides traversal from the read bit passes the first
/// and fails this one.
private let strippedDirectoryMode: UInt16 = 0o644

/// Everything, so no case here depends on an unspecified default.
private func wholeSubtreeOptions() -> EnumerationOptions {
  makeEnumerationOptions(includesHiddenFiles: true, descendsIntoPackages: true)
}

@Suite("File system conformance: a directory stripped of execute")
struct FileSystemStrippedDirectoryConformanceTests {

  @Test(
    "the stripped directory still answers metadata for itself",
    arguments: FileSystemKind.allCases)
  func strippedDirectoryStillAnswersItsOwnMetadata(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: strippedTree) { harness in
      let payload = harness.root.appending("payload")
      try await harness.fileSystem.setPosixPermissions(strippedDirectoryMode, at: payload)

      let record = try await harness.fileSystem.metadata(at: payload)

      #expect(record.path == payload)
      #expect(record.isDirectory)
    }
  }

  @Test(
    "the stripped directory still answers its own permission mode",
    arguments: FileSystemKind.allCases)
  func strippedDirectoryStillAnswersItsOwnMode(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: strippedTree) { harness in
      let payload = harness.root.appending("payload")
      try await harness.fileSystem.setPosixPermissions(strippedDirectoryMode, at: payload)

      let mode = try await harness.fileSystem.posixPermissions(at: payload)

      #expect(mode == strippedDirectoryMode)
      #expect(mode & 0o111 == 0)
    }
  }

  @Test(
    "metadata for a file inside the stripped directory throws permissionDenied",
    arguments: FileSystemKind.allCases)
  func metadataInsideAStrippedDirectoryIsRefused(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: strippedTree) { harness in
      let payload = harness.root.appending("payload")
      let inside = harness.root.appending("payload/inside.txt")
      try await harness.fileSystem.setPosixPermissions(strippedDirectoryMode, at: payload)

      await #expect(throws: FileSystemError.permissionDenied(inside)) {
        _ = try await harness.fileSystem.metadata(at: inside)
      }
    }
  }

  @Test(
    "metadata for a directory inside the stripped directory throws permissionDenied",
    arguments: FileSystemKind.allCases)
  func metadataForANestedDirectoryIsRefused(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: strippedTree) { harness in
      let payload = harness.root.appending("payload")
      let nested = harness.root.appending("payload/nested")
      try await harness.fileSystem.setPosixPermissions(strippedDirectoryMode, at: payload)

      await #expect(throws: FileSystemError.permissionDenied(nested)) {
        _ = try await harness.fileSystem.metadata(at: nested)
      }
    }
  }

  @Test(
    "posixPermissions for a file inside the stripped directory throws permissionDenied",
    arguments: FileSystemKind.allCases)
  func modeInsideAStrippedDirectoryIsRefused(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: strippedTree) { harness in
      let payload = harness.root.appending("payload")
      let inside = harness.root.appending("payload/inside.txt")
      try await harness.fileSystem.setPosixPermissions(strippedDirectoryMode, at: payload)

      await #expect(throws: FileSystemError.permissionDenied(inside)) {
        _ = try await harness.fileSystem.posixPermissions(at: inside)
      }
    }
  }

  @Test(
    "enumeration rooted at the stripped directory yields no record for anything inside it",
    arguments: FileSystemKind.allCases)
  func enumerationRootedAtAStrippedDirectoryYieldsNothingInside(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: strippedTree) { harness in
      let payload = harness.root.appending("payload")
      try await harness.fileSystem.setPosixPermissions(strippedDirectoryMode, at: payload)

      let outcome = try await collectEnumeration(
        harness.fileSystem.enumerate(root: payload, options: wholeSubtreeOptions())
      )

      #expect(outcome.records.isEmpty)
    }
  }

  @Test(
    "enumeration rooted at the stripped directory reports it as inaccessible with a reason",
    arguments: FileSystemKind.allCases)
  func enumerationRootedAtAStrippedDirectoryReportsIt(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: strippedTree) { harness in
      let payload = harness.root.appending("payload")
      try await harness.fileSystem.setPosixPermissions(strippedDirectoryMode, at: payload)

      let outcome = try await collectEnumeration(
        harness.fileSystem.enumerate(root: payload, options: wholeSubtreeOptions())
      )

      let reported = outcome.inaccessible.filter { $0.path == payload }
      #expect(reported.count == 1)
      #expect(!(reported.first?.reason.isEmpty ?? true))
    }
  }

  @Test(
    "enumeration from the parent yields nothing from inside the stripped directory and still yields its siblings",
    arguments: FileSystemKind.allCases)
  func enumerationFromTheParentSkipsTheStrippedSubtreeAndKeepsGoing(kind: FileSystemKind)
    async throws
  {
    try await withHarness(kind, tree: strippedTree) { harness in
      let payload = harness.root.appending("payload")
      try await harness.fileSystem.setPosixPermissions(strippedDirectoryMode, at: payload)

      let outcome = try await collectEnumeration(
        harness.fileSystem.enumerate(root: harness.root, options: wholeSubtreeOptions())
      )

      let insidePayload = outcome.recordPaths.filter { $0.isDescendant(of: payload) }
      #expect(insidePayload.isEmpty)
      #expect(outcome.inaccessible.contains { $0.path == payload })
      // The directory itself is reachable from its parent, so it is a record
      // of its own; only what sits inside it is out of reach.
      #expect(outcome.recordPaths.contains(payload))
      #expect(outcome.recordPaths.contains(harness.root.appending("beside/visible.txt")))
    }
  }

  @Test(
    "giving the execute bits back makes the directory traversable again",
    arguments: FileSystemKind.allCases)
  func restoringExecuteMakesTheDirectoryTraversableAgain(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: strippedTree) { harness in
      let payload = harness.root.appending("payload")
      let inside = harness.root.appending("payload/inside.txt")
      try await harness.fileSystem.setPosixPermissions(strippedDirectoryMode, at: payload)

      try await harness.fileSystem.setPosixPermissions(0o755, at: payload)

      // Without this, an implementation that refused every directory would
      // pass every case above while being just as wrong as one that refuses
      // none.
      let record = try await harness.fileSystem.metadata(at: inside)
      #expect(record.path == inside)
      let outcome = try await collectEnumeration(
        harness.fileSystem.enumerate(root: payload, options: wholeSubtreeOptions())
      )
      #expect(outcome.recordPaths.contains(inside))
      #expect(outcome.inaccessible.isEmpty)
    }
  }
}

/// C13, the byte total clause. A total summed over an enumeration that hit an
/// `inaccessible` event is an absence and never a measurement, and the two are
/// indistinguishable from the number alone: zero bytes looks exactly like a
/// true small number.
///
/// These cases pin the trap rather than a caller's reaction to it. What a
/// caller must do about it is C18's business, and the SafetyNet suites assert
/// that the store refuses rather than records the short figure.
@Suite("File system conformance: a total over an unreadable subtree")
struct FileSystemUnreadableSubtreeTotalConformanceTests {

  @Test(
    "a total that ignores inaccessible events reads an unreadable subtree as zero",
    arguments: FileSystemKind.allCases)
  func aTotalIgnoringInaccessibleEventsReadsZero(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: strippedTree) { harness in
      let payload = harness.root.appending("payload")
      let before = try await collectEnumeration(
        harness.fileSystem.enumerate(root: payload, options: wholeSubtreeOptions())
      )
      let trueTotal = before.records.reduce(UInt64(0)) { $0 + $1.allocatedBytes }
      #expect(trueTotal > 0, "a fixture holding no bytes makes zero afterwards prove nothing")

      try await harness.fileSystem.setPosixPermissions(strippedDirectoryMode, at: payload)

      let after = try await collectEnumeration(
        harness.fileSystem.enumerate(root: payload, options: wholeSubtreeOptions())
      )
      let naiveTotal = after.records.reduce(UInt64(0)) { $0 + $1.allocatedBytes }
      #expect(naiveTotal == 0)
      #expect(naiveTotal != trueTotal)
    }
  }

  @Test(
    "the enumeration says the measurement failed, so nothing has to infer it from the number",
    arguments: FileSystemKind.allCases)
  func theEnumerationReportsTheFailedMeasurement(kind: FileSystemKind) async throws {
    try await withHarness(kind, tree: strippedTree) { harness in
      let payload = harness.root.appending("payload")
      try await harness.fileSystem.setPosixPermissions(strippedDirectoryMode, at: payload)

      let outcome = try await collectEnumeration(
        harness.fileSystem.enumerate(root: payload, options: wholeSubtreeOptions())
      )

      // A caller totalling this enumeration has everything it needs to know
      // the figure is an absence, which is why treating the total as a
      // measurement is a caller's defect and not the boundary's.
      #expect(outcome.inaccessible.contains { $0.path == payload })
    }
  }
}
