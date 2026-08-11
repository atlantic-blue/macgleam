import Foundation

/// The SafetyNet store, over one directory and one file system. Payloads and
/// manifest both live under that directory and both go through that file
/// system, which is what lets a second store over the same directory list
/// everything the first one wrote: a deleted and reinstalled app is exactly
/// that.
///
/// Storing moves the file in and strips its execute bits; the snapshot keeps
/// the mode the file had, so a restore puts back the mode rather than the
/// stripped one. Nothing reads a clock: the injected date source is the only
/// time in here.
public actor SafetyNetStore: SafetyNetStoring {
  private static let manifestName = "manifest.json"
  private static let payloadDirectoryName = "payloads"
  private static let subtreeOptions = EnumerationOptions(
    includesHiddenFiles: true, descendsIntoPackages: true)

  private let directory: AbsolutePath
  private let fileSystem: any FileSystem
  private let denylist: Denylist
  private let currentDate: @Sendable () -> Date

  private var manifest: [SafetyNetItem]?
  private var isMutating = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  public init(
    directory: AbsolutePath,
    fileSystem: any FileSystem,
    denylist: Denylist,
    now: @escaping @Sendable () -> Date
  ) {
    self.directory = directory
    self.fileSystem = fileSystem
    self.denylist = denylist
    self.currentDate = now
  }

  /// The manifest's path, inside the store directory and readable through the
  /// same file system.
  private nonisolated var manifestPath: AbsolutePath {
    AbsolutePath(normalising: directory.value + "/" + Self.manifestName)
  }

  // MARK: - Storing

  public func store(
    _ path: AbsolutePath,
    source: SafetyNetItem.Source,
    groupID: UUID?
  ) async throws -> SafetyNetItem {
    try await withExclusiveAccess {
      guard !denylist.blocks(path) else { throw SafetyNetError.denylistedPath(path) }
      let snapshot = try await snapshot(of: path)
      let allocatedBytes = try await allocatedBytes(ofPayloadAt: path)
      let identifier = UUID()
      let storedPath = try await movePayloadIntoStore(
        path, identifier: identifier, snapshot: snapshot)
      let storedAt = currentDate()
      let item = SafetyNetItem(
        id: identifier,
        originPath: path,
        storedPath: storedPath,
        source: source,
        groupID: groupID,
        metadata: snapshot,
        allocatedBytes: allocatedBytes,
        storedAt: storedAt,
        expiresAt: storedAt.addingTimeInterval(SafetyNetItem.retentionInterval),
        isRestored: false)
      var items = try await loadedManifest()
      items.append(item)
      try await persist(items)
      return item
    }
  }

  /// Everything restore reinstates, read before the file moves.
  private func snapshot(of path: AbsolutePath) async throws -> FileMetadataSnapshot {
    let mode = try await fileSystem.posixPermissions(at: path)
    let attributes = try await fileSystem.extendedAttributes(at: path)
    let record = try await fileSystem.metadata(at: path)
    return FileMetadataSnapshot(
      posixPermissions: mode,
      extendedAttributes: attributes,
      created: record.created,
      modified: record.modified)
  }

  /// The payload's allocated size at its origin, read before the move and
  /// before the strip: a file's own allocation, a directory's whole subtree
  /// total. Exact or nothing. An entry the walk could not read fails the
  /// measurement rather than contributing zero, because a total that quietly
  /// skipped what it could not read is a smaller number that looks exactly
  /// like a true one.
  private func allocatedBytes(ofPayloadAt path: AbsolutePath) async throws -> UInt64 {
    let record = try await fileSystem.metadata(at: path)
    guard record.isDirectory else { return record.allocatedBytes }
    var total: UInt64 = 0
    for try await event in fileSystem.enumerate(root: path, options: Self.subtreeOptions) {
      switch event {
      case .record(let child):
        total += child.allocatedBytes
      case .inaccessible(let unreadable, let reason):
        throw FileSystemError.ioFailure(unreadable, description: reason)
      }
    }
    return total
  }

  /// Moves the file in and strips every execute bit from the payload, leaving
  /// the rest of the mode alone. Quarantined malware cannot run from here.
  private func movePayloadIntoStore(
    _ path: AbsolutePath,
    identifier: UUID,
    snapshot: FileMetadataSnapshot
  ) async throws -> AbsolutePath {
    try await createStoreDirectories()
    let storedPath = AbsolutePath(
      normalising: payloadDirectory.value + "/" + identifier.uuidString)
    try await fileSystem.move(path, to: storedPath)
    try await fileSystem.setPosixPermissions(snapshot.posixPermissions & ~0o111, at: storedPath)
    return storedPath
  }

  // MARK: - Listing

  public func items(includingRestored: Bool) async throws -> [SafetyNetItem] {
    try await withExclusiveAccess {
      let items = try await loadedManifest()
      return includingRestored ? items : items.filter { !$0.isRestored }
    }
  }

  // MARK: - Restoring

  public func restore(itemID: UUID) async throws {
    try await withExclusiveAccess {
      var items = try await loadedManifest()
      guard let index = items.firstIndex(where: { $0.id == itemID }) else {
        throw SafetyNetError.itemNotFound(itemID)
      }
      guard !items[index].isRestored else { throw SafetyNetError.alreadyRestored(itemID) }
      try await requireVacantOrigin(of: items[index])
      try await reinstate(items[index])
      items[index].isRestored = true
      try await persist(items)
    }
  }

  public func restoreGroup(groupID: UUID) async throws {
    try await withExclusiveAccess {
      var items = try await loadedManifest()
      let members = items.indices.filter { items[$0].groupID == groupID }
      guard !members.isEmpty else { throw SafetyNetError.groupNotFound(groupID) }
      let pending = members.filter { !items[$0].isRestored }
      guard !pending.isEmpty else { throw SafetyNetError.alreadyRestored(groupID) }
      for index in pending {
        try await requireVacantOrigin(of: items[index])
      }
      for index in pending {
        try await reinstate(items[index])
        items[index].isRestored = true
      }
      try await persist(items)
    }
  }

  /// An occupied origin refuses before anything moves, which is what makes a
  /// group restore all or nothing.
  private func requireVacantOrigin(of item: SafetyNetItem) async throws {
    guard await fileSystem.exists(item.originPath) else { return }
    throw SafetyNetError.originOccupied(item.originPath)
  }

  /// Moves the payload back and puts the snapshot back on it. The dates ride
  /// along with the move: a copy would restamp them and restore nothing.
  private func reinstate(_ item: SafetyNetItem) async throws {
    if let parent = item.originPath.parent {
      try await fileSystem.createDirectory(at: parent)
    }
    try await fileSystem.move(item.storedPath, to: item.originPath)
    try await fileSystem.setExtendedAttributes(
      item.metadata.extendedAttributes, at: item.originPath)
    try await fileSystem.setPosixPermissions(
      item.metadata.posixPermissions, at: item.originPath)
  }

  // MARK: - Retention

  public func purgeEligibleItems(asOf now: Date) async throws -> [SafetyNetItem] {
    try await withExclusiveAccess {
      try await loadedManifest().filter { item in
        !item.isRestored && item.expiresAt <= now
      }
    }
  }

  public func purge(itemIDs: [UUID], confirmation: PurgeConfirmation) async throws {
    try await withExclusiveAccess {
      var items = try await loadedManifest()
      let targets = try purgeTargets(for: itemIDs, in: items)
      try verify(confirmation, against: targets)
      for target in targets {
        try await fileSystem.delete(target.storedPath)
      }
      let purged = Set(targets.map(\.id))
      items.removeAll { purged.contains($0.id) }
      try await persist(items)
    }
  }

  /// Identifiers first, counts after: a total computed over a set the store
  /// has already rejected means nothing.
  private func purgeTargets(
    for itemIDs: [UUID],
    in items: [SafetyNetItem]
  ) throws -> [SafetyNetItem] {
    var targets: [SafetyNetItem] = []
    for identifier in itemIDs {
      guard let item = items.first(where: { $0.id == identifier }) else {
        throw SafetyNetError.itemNotFound(identifier)
      }
      targets.append(item)
    }
    if let restored = targets.first(where: \.isRestored) {
      throw SafetyNetError.alreadyRestored(restored.id)
    }
    return targets
  }

  /// The confirmation is an agreement about a recorded fact rather than two
  /// readings of a disk that may have changed between them: both sides sum the
  /// sizes the items recorded when they were stored. Nothing here reads a
  /// payload, which is what makes a purge of a contained directory possible at
  /// all.
  private func verify(
    _ confirmation: PurgeConfirmation,
    against targets: [SafetyNetItem]
  ) throws {
    guard confirmation.itemCount == UInt32(targets.count) else {
      throw SafetyNetError.confirmationMismatch
    }
    let total = targets.reduce(UInt64(0)) { $0 + $1.allocatedBytes }
    guard confirmation.byteTotal == total else { throw SafetyNetError.confirmationMismatch }
  }

  // MARK: - Manifest

  private var payloadDirectory: AbsolutePath {
    AbsolutePath(normalising: directory.value + "/" + Self.payloadDirectoryName)
  }

  private func loadedManifest() async throws -> [SafetyNetItem] {
    if let manifest { return manifest }
    let loaded = try await readManifest()
    manifest = loaded
    return loaded
  }

  private func readManifest() async throws -> [SafetyNetItem] {
    let path = manifestPath
    guard await fileSystem.exists(path) else { return [] }
    let data = try await fileSystem.readData(at: path, maxBytes: UInt64.max)
    do {
      return try JSONDecoder().decode([SafetyNetItem].self, from: data)
    } catch {
      throw FileSystemError.ioFailure(
        path, description: "The SafetyNet manifest is not a readable manifest.")
    }
  }

  /// Written whole and atomically after every mutation, so an interrupted
  /// store, restore or purge leaves a manifest describing the state before it
  /// or the state after it.
  private func persist(_ items: [SafetyNetItem]) async throws {
    try await createStoreDirectories()
    let data = try JSONEncoder().encode(items)
    try await fileSystem.writeData(data, to: manifestPath)
    manifest = items
  }

  private func createStoreDirectories() async throws {
    try await fileSystem.createDirectory(at: directory)
    try await fileSystem.createDirectory(at: payloadDirectory)
  }

  // MARK: - Serialisation

  /// One mutation at a time. The actor alone is not enough: every method here
  /// suspends part way through, so without this two concurrent stores could
  /// each write a manifest missing the other's item.
  private func withExclusiveAccess<T>(_ body: () async throws -> T) async rethrows -> T {
    while isMutating {
      await withCheckedContinuation { continuation in
        waiting.append(continuation)
      }
    }
    isMutating = true
    defer { releaseExclusiveAccess() }
    return try await body()
  }

  private func releaseExclusiveAccess() {
    isMutating = false
    guard !waiting.isEmpty else { return }
    waiting.removeFirst().resume()
  }
}
