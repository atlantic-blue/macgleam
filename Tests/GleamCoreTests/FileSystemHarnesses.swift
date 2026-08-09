import Darwin
import Foundation
import GleamCore
import Testing

/// The two implementations under conformance test. Every shared test is
/// parameterised over both, so the suite is written once and a behaviour
/// difference between the fake and the real disk is a test failure.
enum FileSystemKind: String, CaseIterable, Sendable, CustomTestStringConvertible {
  case inMemory = "in memory"
  case realDisk = "real disk"

  var testDescription: String { rawValue }
}

/// One materialised fixture tree and the file system serving it. Each test
/// builds its own harness, so tests share no state and run in any order.
protocol FileSystemHarness: Sendable {
  var root: AbsolutePath { get }
  var fileSystem: any FileSystem { get }
  func tearDown() async
}

/// Builds the harness for the given kind, runs the body, and tears the
/// harness down whatever the body did.
func withHarness<Result: Sendable>(
  _ kind: FileSystemKind,
  tree: FixtureTree,
  _ body: (any FileSystemHarness) async throws -> Result
) async throws -> Result {
  let harness: any FileSystemHarness
  switch kind {
  case .inMemory:
    harness = try await InMemoryHarness(tree: tree)
  case .realDisk:
    harness = try await DiskHarness(tree: tree)
  }
  do {
    let result = try await body(harness)
    await harness.tearDown()
    return result
  } catch {
    await harness.tearDown()
    throw error
  }
}

// MARK: - In memory

private struct InMemoryHarness: FileSystemHarness {
  let root = Fixture.path("/fixtures")
  private let inMemory: InMemoryFileSystem

  var fileSystem: any FileSystem { inMemory }

  init(tree: FixtureTree) async throws {
    inMemory = InMemoryFileSystem()
    await inMemory.seedDirectory(at: root)
    for directory in tree.allDirectories {
      await inMemory.seedDirectory(at: root.appending(directory))
    }
    for file in tree.files {
      await inMemory.seedFile(
        at: root.appending(file.relativePath),
        contents: file.contents,
        isExecutable: file.isExecutable,
        created: FileSystemFixture.createdDate,
        modified: FileSystemFixture.modifiedDate,
        lastOpened: nil,
        extendedAttributes: file.extendedAttributes
      )
    }
  }

  func tearDown() async {}
}

// MARK: - Real disk

private struct DiskHarness: FileSystemHarness {
  let root: AbsolutePath
  let fileSystem: any FileSystem
  private let directoryPaths: [String]

  init(tree: FixtureTree) async throws {
    let manager = FileManager.default
    // The temporary directory sits behind a symbolic link (/var), so the
    // root is resolved up front and every asserted path stays canonical.
    let base = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
    let rootURL = base.appendingPathComponent(
      "macgleam-conformance-\(UUID().uuidString)",
      isDirectory: true
    )
    try manager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    root = AbsolutePath(normalising: rootURL.path)

    var createdDirectories = [rootURL.path]
    for directory in tree.allDirectories {
      let url = rootURL.appendingPathComponent(directory, isDirectory: true)
      try manager.createDirectory(at: url, withIntermediateDirectories: true)
      createdDirectories.append(url.path)
    }
    for file in tree.files {
      let url = rootURL.appendingPathComponent(file.relativePath)
      try file.contents.write(to: url)
      try manager.setAttributes(
        [.posixPermissions: file.isExecutable ? 0o755 : 0o644],
        ofItemAtPath: url.path
      )
      for (name, value) in file.extendedAttributes {
        try Self.setExtendedAttribute(name: name, value: value, atPath: url.path)
      }
      // Dates go last in one call: earlier writes bump the modification
      // date, and the suite asserts created is not after modified.
      try manager.setAttributes(
        [
          .creationDate: FileSystemFixture.createdDate,
          .modificationDate: FileSystemFixture.modifiedDate,
        ],
        ofItemAtPath: url.path
      )
    }
    directoryPaths = createdDirectories
    fileSystem = DiskFileSystem()
  }

  /// Restores permissions a test may have stripped, then removes the tree.
  /// Best effort on purpose: tests move and delete fixture entries.
  func tearDown() async {
    let manager = FileManager.default
    for path in directoryPaths.reversed() {
      try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }
    try? manager.removeItem(atPath: root.value)
  }

  private static func setExtendedAttribute(
    name: String,
    value: Data,
    atPath path: String
  ) throws {
    let status = value.withUnsafeBytes { buffer in
      setxattr(path, name, buffer.baseAddress, buffer.count, 0, 0)
    }
    guard status == 0 else {
      throw CocoaError(.fileWriteUnknown)
    }
  }
}
