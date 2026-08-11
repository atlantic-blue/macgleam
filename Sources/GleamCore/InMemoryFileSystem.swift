import Foundation

/// A complete `FileSystem` held in memory, the implementation every engine
/// test runs against. One volume, rooted at "/". Seeding creates intermediate
/// directories implicitly. Allocated bytes equal the seeded content length.
public actor InMemoryFileSystem {
  private struct Node {
    var isDirectory: Bool
    var contents: Data
    var isExecutable: Bool
    var created: Date?
    var modified: Date?
    var lastOpened: Date?
    var extendedAttributes: [String: Data]
    var posixPermissions: UInt16
    let fileID: UInt64

    var isReadable: Bool { posixPermissions & 0o400 != 0 }
  }

  private static let volumeID: UInt64 = 1
  private static let root = AbsolutePath(normalising: "/")
  private static let trashDirectory = AbsolutePath(normalising: "/.Trash")

  private var nodes: [AbsolutePath: Node] = [:]
  private var nextFileID: UInt64 = 1

  public init() {
    nodes[Self.root] = Self.directoryNode(fileID: 1)
    nextFileID = 2
  }

  private static func directoryNode(fileID: UInt64) -> Node {
    Node(
      isDirectory: true, contents: Data(), isExecutable: false, created: nil,
      modified: nil, lastOpened: nil, extendedAttributes: [:], posixPermissions: 0o755,
      fileID: fileID)
  }

  // MARK: - Seeding

  public func seedDirectory(at path: AbsolutePath) {
    createIntermediateDirectories(leadingTo: path)
    guard nodes[path]?.isDirectory != true else { return }
    nodes[path] = Self.directoryNode(fileID: allocateFileID())
  }

  public func seedFile(
    at path: AbsolutePath,
    contents: Data = Data(),
    isExecutable: Bool = false,
    created: Date? = nil,
    modified: Date? = nil,
    lastOpened: Date? = nil,
    extendedAttributes: [String: Data] = [:]
  ) {
    createIntermediateDirectories(leadingTo: path)
    nodes[path] = Node(
      isDirectory: false, contents: contents, isExecutable: isExecutable, created: created,
      modified: modified, lastOpened: lastOpened, extendedAttributes: extendedAttributes,
      posixPermissions: isExecutable ? 0o755 : 0o644, fileID: allocateFileID())
  }

  private func createIntermediateDirectories(leadingTo path: AbsolutePath) {
    guard let parent = path.parent else { return }
    createIntermediateDirectories(leadingTo: parent)
    guard nodes[parent]?.isDirectory != true else { return }
    nodes[parent] = Self.directoryNode(fileID: allocateFileID())
  }

  private func allocateFileID() -> UInt64 {
    defer { nextFileID += 1 }
    return nextFileID
  }

  private func record(at path: AbsolutePath, node: Node) -> FileRecord {
    FileRecord(
      path: path,
      fileID: node.fileID,
      volumeID: Self.volumeID,
      allocatedBytes: node.isDirectory ? 0 : UInt64(node.contents.count),
      isDirectory: node.isDirectory,
      isExecutable: node.isExecutable,
      created: node.created,
      modified: node.modified,
      lastOpened: node.lastOpened)
  }

  private func existingNode(at path: AbsolutePath) throws -> Node {
    guard let node = nodes[path] else { throw FileSystemError.notFound(path) }
    return node
  }
}

// MARK: - RawDirectoryReading

extension InMemoryFileSystem: RawDirectoryReading {
  public func children(of directory: AbsolutePath) async throws -> [FileRecord] {
    let node = try existingNode(at: directory)
    guard node.isDirectory else {
      throw FileSystemError.ioFailure(directory, description: "Not a directory.")
    }
    guard node.isReadable else { throw FileSystemError.permissionDenied(directory) }
    return nodes.compactMap { path, node in
      guard path.parent == directory else { return nil }
      return record(at: path, node: node)
    }
  }
}

// MARK: - FileSystemReading

extension InMemoryFileSystem: FileSystemReading {
  public nonisolated func enumerate(
    root: AbsolutePath,
    options: EnumerationOptions
  ) -> AsyncThrowingStream<EnumerationEvent, Error> {
    FileSystemEnumerator(source: self).enumerate(root: root, options: options)
  }

  public func metadata(at path: AbsolutePath) async throws -> FileRecord {
    record(at: path, node: try existingNode(at: path))
  }

  public func posixPermissions(at path: AbsolutePath) async throws -> UInt16 {
    try existingNode(at: path).posixPermissions & 0o7777
  }

  public func readData(at path: AbsolutePath, maxBytes: UInt64) async throws -> Data {
    let node = try existingNode(at: path)
    guard !node.isDirectory else {
      throw FileSystemError.ioFailure(path, description: "Not a readable file.")
    }
    guard node.isReadable else { throw FileSystemError.permissionDenied(path) }
    let limit = Int(min(maxBytes, UInt64(node.contents.count)))
    return node.contents.prefix(limit)
  }

  public func extendedAttributes(at path: AbsolutePath) async throws -> [String: Data] {
    try existingNode(at: path).extendedAttributes
  }

  public func exists(_ path: AbsolutePath) async -> Bool {
    nodes[path] != nil
  }

  public func volumeInfo(at path: AbsolutePath) async throws -> VolumeInfo {
    _ = try existingNode(at: path)
    return VolumeInfo(
      root: Self.root,
      volumeID: Self.volumeID,
      capacityBytes: 512 * 1024 * 1024 * 1024,
      availableBytes: 256 * 1024 * 1024 * 1024,
      isInternal: true)
  }
}

// MARK: - FileSystemMutating

extension InMemoryFileSystem: FileSystemMutating {
  public func moveToTrash(_ path: AbsolutePath) async throws -> AbsolutePath {
    _ = try existingNode(at: path)
    seedDirectory(at: Self.trashDirectory)
    let destination = availableTrashPath(for: path)
    moveSubtree(from: path, to: destination)
    return destination
  }

  public func move(_ source: AbsolutePath, to destination: AbsolutePath) async throws {
    _ = try existingNode(at: source)
    guard nodes[destination] == nil else {
      throw FileSystemError.destinationOccupied(destination)
    }
    createIntermediateDirectories(leadingTo: destination)
    moveSubtree(from: source, to: destination)
  }

  public func delete(_ path: AbsolutePath) async throws {
    _ = try existingNode(at: path)
    for member in subtreePaths(of: path) {
      nodes.removeValue(forKey: member)
    }
  }

  public func createDirectory(at path: AbsolutePath) async throws {
    if let node = nodes[path] {
      guard node.isDirectory else { throw FileSystemError.destinationOccupied(path) }
      return
    }
    seedDirectory(at: path)
  }

  /// Replaces the node's contents whole, creating the node when absent. A
  /// missing parent directory throws rather than being created, so the fake
  /// refuses the mistyped path the real file system refuses.
  public func writeData(_ data: Data, to path: AbsolutePath) async throws {
    guard let parent = path.parent else { throw FileSystemError.destinationOccupied(path) }
    guard nodes[parent]?.isDirectory == true else { throw FileSystemError.notFound(parent) }
    if let existing = nodes[path] {
      guard !existing.isDirectory else { throw FileSystemError.destinationOccupied(path) }
      nodes[path]?.contents = data
      return
    }
    nodes[path] = Node(
      isDirectory: false, contents: data, isExecutable: false, created: nil, modified: nil,
      lastOpened: nil, extendedAttributes: [:], posixPermissions: 0o644,
      fileID: allocateFileID())
  }

  public func setPosixPermissions(_ mode: UInt16, at path: AbsolutePath) async throws {
    let node = try existingNode(at: path)
    nodes[path]?.posixPermissions = mode
    nodes[path]?.isExecutable = !node.isDirectory && mode & 0o100 != 0
  }

  public func setExtendedAttributes(
    _ attributes: [String: Data],
    at path: AbsolutePath
  ) async throws {
    _ = try existingNode(at: path)
    nodes[path]?.extendedAttributes = attributes
  }

  private func subtreePaths(of path: AbsolutePath) -> [AbsolutePath] {
    nodes.keys.filter { $0 == path || $0.isDescendant(of: path) }
  }

  private func moveSubtree(from source: AbsolutePath, to destination: AbsolutePath) {
    for path in subtreePaths(of: source) {
      guard let node = nodes.removeValue(forKey: path) else { continue }
      let suffix = String(path.value.dropFirst(source.value.count))
      nodes[AbsolutePath(normalising: destination.value + suffix)] = node
    }
  }

  private func availableTrashPath(for path: AbsolutePath) -> AbsolutePath {
    let base = Self.trashDirectory.value + "/" + path.lastComponent
    var candidate = AbsolutePath(normalising: base)
    var counter = 2
    while nodes[candidate] != nil {
      candidate = AbsolutePath(normalising: "\(base) \(counter)")
      counter += 1
    }
    return candidate
  }
}
