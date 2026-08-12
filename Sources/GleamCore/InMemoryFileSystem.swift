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
    /// A directory is searched with its execute bit, never its read bit. The
    /// read bit lists the names; the execute bit is what resolves a path
    /// through it, so a directory stripped of execute holds contents nothing
    /// can reach (C13).
    var isSearchable: Bool { posixPermissions & 0o100 != 0 }
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
    try requireReachable(path)
    guard let node = nodes[path] else { throw FileSystemError.notFound(path) }
    return node
  }

  /// Path resolution as the disk performs it: every directory on the way to a
  /// path has to be searchable. Reaching a directory needs permission on its
  /// parent rather than on itself, so a directory whose execute bits are clear
  /// still answers for itself while nothing inside it resolves at all.
  private func isReachable(_ path: AbsolutePath) -> Bool {
    var ancestor = path.parent
    while let directory = ancestor {
      if let node = nodes[directory], node.isDirectory, !node.isSearchable { return false }
      ancestor = directory.parent
    }
    return true
  }

  private func requireReachable(_ path: AbsolutePath) throws {
    guard isReachable(path) else { throw FileSystemError.permissionDenied(path) }
  }
}

// MARK: - RawDirectoryReading

extension InMemoryFileSystem: RawDirectoryReading {
  public func children(of directory: AbsolutePath) async throws -> [FileRecord] {
    let node = try existingNode(at: directory)
    guard node.isDirectory else {
      throw FileSystemError.ioFailure(directory, description: "Not a directory.")
    }
    guard node.isReadable, node.isSearchable else {
      throw FileSystemError.permissionDenied(directory)
    }
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

  /// A path nothing can resolve does not exist as far as a reader is
  /// concerned, which is what the platform answers for a path inside a
  /// directory stripped of execute.
  public func exists(_ path: AbsolutePath) async -> Bool {
    nodes[path] != nil && isReachable(path)
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
    try requireReachable(destination)
    guard nodes[destination] == nil else {
      throw FileSystemError.destinationOccupied(destination)
    }
    createIntermediateDirectories(leadingTo: destination)
    moveSubtree(from: source, to: destination)
  }

  /// Deleting descends, and it repairs traversal on the way, because removing
  /// a directory's children needs search and write permission on the directory
  /// holding them. The store contains a payload by stripping its execute bits,
  /// so without this a purge could compute the right total and be unable to
  /// delete what it counted.
  ///
  /// The repair is narrow: owner search and write, added only to directories,
  /// never to a file, and every bit it added is cleared if it cannot finish.
  /// This models what the disk does, and it has to, because dropping
  /// dictionary keys with no permission check is how the fake said yes to what
  /// a real volume refused.
  public func delete(_ path: AbsolutePath) async throws {
    _ = try existingNode(at: path)
    var repaired: [AbsolutePath: UInt16] = [:]
    do {
      try repairTraversal(of: path, recording: &repaired)
      try requireDeletable(path)
    } catch {
      for (directory, mode) in repaired {
        nodes[directory]?.posixPermissions = mode
      }
      throw error
    }
    for member in subtreePaths(of: path) {
      nodes.removeValue(forKey: member)
    }
  }

  /// What the disk refuses: removing a directory's children needs search and
  /// write permission on the directory holding them. Asserted after the repair
  /// rather than instead of it, so a delete that stopped repairing fails here
  /// instead of quietly dropping keys the disk would have kept.
  private func requireDeletable(_ path: AbsolutePath) throws {
    guard let node = nodes[path], node.isDirectory else { return }
    guard node.posixPermissions & 0o300 == 0o300 else {
      throw FileSystemError.permissionDenied(path)
    }
    for child in childPaths(of: path) {
      try requireDeletable(child)
    }
  }

  /// Adds owner search and write to every directory the delete must enter,
  /// remembering the mode each one had so an interrupted delete can put it
  /// back. A directory it cannot repair fails the delete rather than partly
  /// emptying it.
  private func repairTraversal(
    of path: AbsolutePath,
    recording repaired: inout [AbsolutePath: UInt16]
  ) throws {
    guard let node = nodes[path], node.isDirectory else { return }
    if node.posixPermissions & 0o300 != 0o300 {
      repaired[path] = node.posixPermissions
      nodes[path]?.posixPermissions = node.posixPermissions | 0o300
    }
    for child in childPaths(of: path) {
      try repairTraversal(of: child, recording: &repaired)
    }
  }

  public func createDirectory(at path: AbsolutePath) async throws {
    try requireReachable(path)
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
    try requireReachable(path)
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

  /// The direct children of a directory, without the permission checks the
  /// public listing applies: this is the walk a delete performs from inside,
  /// after it has given itself the traversal it needs.
  private func childPaths(of directory: AbsolutePath) -> [AbsolutePath] {
    nodes.keys.filter { $0.parent == directory }
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
