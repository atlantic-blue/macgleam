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
  private let ownership: any PathOwnershipPolicy
  private let environment: OwnershipEnvironment
  /// The half of this store that can hold a payload only root can move.
  /// Optional in exactly the sense the helper is: a build or a test without
  /// one holds user domain payloads and refuses system domain ones, having
  /// moved nothing. It is never a store that quietly does the user domain part
  /// of a system domain job.
  private let privileged: (any SafetyNetPrivilegedArchiving)?
  private let currentDate: @Sendable () -> Date

  private var manifest: [SafetyNetItem]?
  private var isMutating = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  public init(
    directory: AbsolutePath,
    fileSystem: any FileSystem,
    denylist: Denylist,
    ownership: any PathOwnershipPolicy,
    environment: OwnershipEnvironment,
    privileged: (any SafetyNetPrivilegedArchiving)? = nil,
    now: @escaping @Sendable () -> Date
  ) {
    self.directory = directory
    self.fileSystem = fileSystem
    self.denylist = denylist
    self.ownership = ownership
    self.environment = environment
    self.privileged = privileged
    self.currentDate = now
  }

  /// The manifest's path, inside the store directory and readable through the
  /// same file system.
  private nonisolated var manifestPath: AbsolutePath {
    AbsolutePath(normalising: directory.value + "/" + Self.manifestName)
  }

  // MARK: - Storing

  /// The store routes, not its caller. It reads the origin's ownership and
  /// does the whole operation through the privileged half for a system domain
  /// path. The routing belongs here because this is the only thing that holds
  /// the manifest: anything that sent an archive to the helper itself would
  /// move a file into this store without this store knowing, which is the
  /// defect that made this half exist.
  public func store(
    _ path: AbsolutePath,
    source: SafetyNetItem.Source,
    groupID: UUID?
  ) async throws -> SafetyNetItem {
    try await withExclusiveAccess {
      guard !denylist.blocks(path) else { throw SafetyNetError.denylistedPath(path) }
      let identifier = UUID()
      let storedPath = payloadPath(for: identifier)
      let archived: Archived
      if needsPrivilege(path) {
        archived = try await storeThroughPrivilegedHalf(
          path, identifier: identifier, storedPath: storedPath)
      } else {
        archived = try await storeInThisProcess(path, storedPath: storedPath)
      }
      let storedAt = currentDate()
      let item = SafetyNetItem(
        id: identifier,
        originPath: path,
        storedPath: storedPath,
        source: source,
        groupID: groupID,
        metadata: archived.metadata,
        allocatedBytes: archived.allocatedBytes,
        storedAt: storedAt,
        expiresAt: storedAt.addingTimeInterval(SafetyNetItem.retentionInterval),
        isRestored: false)
      var items = try await loadedManifest()
      items.append(item)
      try await persist(items)
      return item
    }
  }

  /// What an archive observed at the origin, whichever process performed it.
  private struct Archived {
    let metadata: FileMetadataSnapshot
    let allocatedBytes: UInt64
  }

  private func needsPrivilege(_ path: AbsolutePath) -> Bool {
    ownership.ownership(of: path, environment: environment) == .systemDomain
  }

  private func storeInThisProcess(
    _ path: AbsolutePath,
    storedPath: AbsolutePath
  ) async throws -> Archived {
    let snapshot = try await snapshot(of: path)
    let allocatedBytes = try await allocatedBytes(ofPayloadAt: path)
    try await createStoreDirectories()
    try await fileSystem.move(path, to: storedPath)
    try await fileSystem.setPosixPermissions(snapshot.posixPermissions & ~0o111, at: storedPath)
    return Archived(metadata: snapshot, allocatedBytes: allocatedBytes)
  }

  /// One request and one recorded fact. The store names the payload path and
  /// mints the identifier before it asks, so an archive whose reply never
  /// arrives is settled by looking rather than guessed at: the payload is
  /// absent, in which case nothing happened, or it is present, in which case
  /// the store asks what it is and records the stamp root wrote. A payload
  /// sitting in the store that no manifest entry names is the one outcome this
  /// contract does not allow, whatever the transport did.
  private func storeThroughPrivilegedHalf(
    _ path: AbsolutePath,
    identifier: UUID,
    storedPath: AbsolutePath
  ) async throws -> Archived {
    guard let privileged else { throw SafetyNetError.privilegeUnavailable(path) }
    try await createStoreDirectories()
    let report: PrivilegedArchiveReport
    do {
      report = try await privileged.archive(path, to: storedPath, itemID: identifier)
    } catch {
      guard await fileSystem.exists(storedPath) else { throw error }
      report = try await privileged.describeArchived(at: storedPath, itemID: identifier)
    }
    guard report.originPath == path else {
      throw SafetyNetError.privilegedReportDisagreed(identifier)
    }
    return Archived(metadata: report.metadata, allocatedBytes: report.allocatedBytes)
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

  /// The payload's path, chosen here and never by the privileged half, and
  /// chosen before the request goes out so a lost reply leaves something to
  /// look for.
  private func payloadPath(for identifier: UUID) -> AbsolutePath {
    AbsolutePath(normalising: payloadDirectory.value + "/" + identifier.uuidString)
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
  /// group restore all or nothing. A privileged item is asked about the same
  /// way: the payload is root owned, but its origin sits where this process
  /// can see whether something is there.
  private func requireVacantOrigin(of item: SafetyNetItem) async throws {
    if needsPrivilege(item.originPath), privileged == nil {
      throw SafetyNetError.privilegeUnavailable(item.originPath)
    }
    guard await fileSystem.exists(item.originPath) else { return }
    throw SafetyNetError.originOccupied(item.originPath)
  }

  /// Moves the payload back and puts the snapshot back on it. The dates ride
  /// along with the move: a copy would restamp them and restore nothing.
  ///
  /// A privileged item goes back through the privileged half, which reads
  /// where it belongs from the payload's own stamp rather than from anything
  /// this process sends. The two must agree: a restore landing somewhere other
  /// than the origin this store holds is recorded as a disagreement and
  /// nothing is marked restored.
  private func reinstate(_ item: SafetyNetItem) async throws {
    guard needsPrivilege(item.originPath) else {
      if let parent = item.originPath.parent {
        try await fileSystem.createDirectory(at: parent)
      }
      try await fileSystem.move(item.storedPath, to: item.originPath)
      try await fileSystem.setExtendedAttributes(
        item.metadata.extendedAttributes, at: item.originPath)
      try await fileSystem.setPosixPermissions(
        item.metadata.posixPermissions, at: item.originPath)
      return
    }
    guard let privileged else { throw SafetyNetError.privilegeUnavailable(item.originPath) }
    let landed = try await privileged.restoreArchived(at: item.storedPath, itemID: item.id)
    guard landed == item.originPath else {
      throw SafetyNetError.privilegedReportDisagreed(item.id)
    }
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
      for target in targets where needsPrivilege(target.originPath) && privileged == nil {
        throw SafetyNetError.privilegeUnavailable(target.originPath)
      }
      for target in targets {
        try await discard(target)
      }
      let purged = Set(targets.map(\.id))
      items.removeAll { purged.contains($0.id) }
      try await persist(items)
    }
  }

  /// A root owned payload is discarded through the privileged half, because
  /// removing the children of a root owned directory needs write permission on
  /// that directory and this process has none.
  private func discard(_ item: SafetyNetItem) async throws {
    guard needsPrivilege(item.originPath) else {
      try await fileSystem.delete(item.storedPath)
      return
    }
    guard let privileged else { throw SafetyNetError.privilegeUnavailable(item.originPath) }
    try await privileged.discardArchived(at: item.storedPath, itemID: item.id)
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
