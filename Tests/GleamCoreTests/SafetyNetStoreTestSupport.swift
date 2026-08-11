import Foundation
import GleamCore
import Testing

/// Shared fixtures for the C18 SafetyNet store suites.
///
/// Two properties hold across every suite. Nothing reads a wall clock: the
/// instant the store stamps is injected at construction and the instant
/// retention is judged against is an argument. And nothing touches a real
/// file: every test drives the in memory implementation of C13 and C14.
enum SafetyNetFixture {

  /// The instant the injected date source returns, so `storedAt` and
  /// `expiresAt` are exact values rather than ranges.
  static let storeInstant = Date(timeIntervalSince1970: 1_726_000_000)
  static let confirmationInstant = Date(timeIntervalSince1970: 1_726_100_000)

  /// The dates a fixture file carries before it is stored. Both are well
  /// before the store instant, so a restore that quietly re stamps a date
  /// with "now" cannot pass.
  static let createdDate = Date(timeIntervalSince1970: 1_600_000_000)
  static let modifiedDate = Date(timeIntervalSince1970: 1_650_000_000)

  /// Exactly thirty days after `storeInstant`, per C8.
  static var expiryInstant: Date {
    storeInstant.addingTimeInterval(Fixture.thirtyDays)
  }

  static let applicationSupport = Fixture.path("/Users/julian/Library/Application Support")
  static let directory = Fixture.path(
    "/Users/julian/Library/Application Support/MacGleam/SafetyNet")

  /// The app bundle the reinstall suite deletes, to show the manifest does
  /// not live inside the application.
  static let applicationBundle = Fixture.path("/Applications/MacGleam.app")

  static let quarantineAttributeName = "com.apple.quarantine"
  static let tagAttributeName = "com.apple.metadata:_kMDItemUserTags"

  /// Two attributes rather than one, so a store that carries the first and
  /// drops the second is caught.
  static func attributes(_ seed: UInt8) -> [String: Data] {
    [
      quarantineAttributeName: Data([0x00, 0x81, seed, 0x21]),
      tagAttributeName: Data([seed, seed &+ 1, seed &+ 2, seed &+ 3]),
    ]
  }

  static func contents(_ seed: UInt8, length: Int = 96) -> Data {
    FileSystemFixture.contents(seed, length: length)
  }

  /// The mode a payload carries once the store has stripped execute from it.
  /// On a real volume a directory wearing this cannot be traversed (C13),
  /// which is the containment and the reason sizing happens at store time.
  static let strippedDirectoryMode: UInt16 = 0o644
}

// MARK: - The world every suite starts from

/// Seeded shallowest first, because the in memory implementation models a
/// tree and a file needs its ancestors.
private let safetyNetBaseDirectories = [
  "/Applications",
  "/Users",
  "/Users/julian",
  "/Users/julian/Downloads",
  "/Users/julian/Library",
  "/Users/julian/Library/Application Support",
  "/Users/julian/Library/Preferences",
]

/// A file system holding the ancestor directories and nothing else. The store
/// directory itself is deliberately absent: the store owns it and creates it,
/// which is what first launch looks like.
///
/// Extra directories are seeded in the order given, so a caller listing a
/// nested path lists its parent first.
func safetyNetFileSystem(directories extra: [AbsolutePath] = []) async -> InMemoryFileSystem {
  let fileSystem = InMemoryFileSystem()
  for value in safetyNetBaseDirectories {
    await fileSystem.seedDirectory(at: Fixture.path(value))
  }
  for directory in extra {
    await fileSystem.seedDirectory(at: directory)
  }
  return fileSystem
}

/// The construction surface the tests demand of the concrete C18 store.
///
/// The directory is injected so a second store can be built over the same
/// one, which is how reinstall survival is tested. The instant is injected so
/// `storedAt` is a fixed value. The store persists its manifest through the
/// file system it is handed, never through a private path, or a fresh store
/// over the same directory could not see what the old one wrote.
func safetyNetMake(
  fileSystem: any FileSystem,
  denylist: Denylist = makeDenylist([]),
  directory: AbsolutePath = SafetyNetFixture.directory,
  now: @escaping @Sendable () -> Date = { SafetyNetFixture.storeInstant }
) -> SafetyNetStore {
  SafetyNetStore(
    directory: directory,
    fileSystem: fileSystem,
    denylist: denylist,
    now: now
  )
}

// MARK: - Observing a file through the boundary

/// Everything about a file that restore has to reinstate, read back through
/// C13 alone. Compared attribute by attribute rather than whole, so a failure
/// names what was lost.
struct SafetyNetPathState: Equatable, Sendable {
  var contents: Data
  var posixPermissions: UInt16
  var extendedAttributes: [String: Data]
  var created: Date?
  var modified: Date?
}

/// Reads the state of a file. Throws when the path holds nothing, so every
/// call site that expects a file to be there fails loudly when it is not.
func safetyNetState(
  of path: AbsolutePath,
  in fileSystem: any FileSystem
) async throws -> SafetyNetPathState {
  let record = try await fileSystem.metadata(at: path)
  return SafetyNetPathState(
    contents: try await fileSystem.readData(at: path, maxBytes: 1_000_000),
    posixPermissions: try await fileSystem.posixPermissions(at: path),
    extendedAttributes: try await fileSystem.extendedAttributes(at: path),
    created: record.created,
    modified: record.modified
  )
}

/// Seeds one fixture file and returns what the boundary then reports about
/// it. Tests assert against this captured state rather than against literal
/// values, so no assertion depends on how the in memory implementation maps a
/// seed onto a permission mode.
@discardableResult
func safetyNetSeedFile(
  in fileSystem: InMemoryFileSystem,
  at path: AbsolutePath,
  seed: UInt8,
  isExecutable: Bool = false,
  extendedAttributes: [String: Data]? = nil,
  created: Date = SafetyNetFixture.createdDate,
  modified: Date = SafetyNetFixture.modifiedDate,
  sourceLocation: SourceLocation = #_sourceLocation
) async throws -> SafetyNetPathState {
  await fileSystem.seedFile(
    at: path,
    contents: SafetyNetFixture.contents(seed),
    isExecutable: isExecutable,
    created: created,
    modified: modified,
    lastOpened: nil,
    extendedAttributes: extendedAttributes ?? SafetyNetFixture.attributes(seed)
  )
  let state = try await safetyNetState(of: path, in: fileSystem)
  if isExecutable {
    // A fixture carrying no execute bit would let "storing strips execute"
    // pass with the store doing nothing at all.
    #expect(
      state.posixPermissions & 0o111 != 0,
      "an executable fixture must start with execute bits set",
      sourceLocation: sourceLocation
    )
  }
  #expect(
    !state.extendedAttributes.isEmpty,
    "a fixture with no extended attributes cannot prove they are preserved",
    sourceLocation: sourceLocation
  )
  return state
}

// MARK: - Measuring a subtree through the boundary

/// Raised when a walk met a subtree it could not read. An `inaccessible`
/// event is a failed measurement and never a zero contribution (C13), so the
/// tests' own arithmetic obeys the rule the store is held to: no helper here
/// can quietly hand back a short figure.
struct SafetyNetMeasurementRefused: Error, Equatable {
  let path: AbsolutePath
}

/// Everything, so no measurement here depends on an unspecified default and
/// a payload that happens to be a bundle is counted whole.
func safetyNetWholeSubtreeOptions() -> EnumerationOptions {
  makeEnumerationOptions(includesHiddenFiles: true, descendsIntoPackages: true)
}

/// The allocated total of a whole subtree, the path itself included, on the
/// project's usual basis: every record counts toward itself and each of its
/// ancestors. Throws rather than returning a total it could not read whole.
func safetyNetSubtreeBytes(
  of root: AbsolutePath,
  in fileSystem: any FileSystem
) async throws -> UInt64 {
  var total = try await fileSystem.metadata(at: root).allocatedBytes
  for try await event in fileSystem.enumerate(root: root, options: safetyNetWholeSubtreeOptions()) {
    switch event {
    case .record(let record):
      total += record.allocatedBytes
    case .inaccessible(let path, _):
      throw SafetyNetMeasurementRefused(path: path)
    }
  }
  return total
}

/// What a walk that added up what it could read and ignored what it could not
/// would come back with. Never a measurement: the tests use it to show the
/// figure a stripped payload offers anybody who tries to re-derive its size.
func safetyNetNaiveSubtreeBytes(
  of root: AbsolutePath,
  in fileSystem: any FileSystem
) async throws -> UInt64 {
  var total = try await fileSystem.metadata(at: root).allocatedBytes
  for try await event in fileSystem.enumerate(root: root, options: safetyNetWholeSubtreeOptions()) {
    if case .record(let record) = event {
      total += record.allocatedBytes
    }
  }
  return total
}

// MARK: - Directory payloads

/// A directory payload at an origin path, with the figures measured through
/// the boundary before anything moved or stripped it.
struct SafetyNetDirectoryPayload: Sendable {
  let root: AbsolutePath
  /// One file inside the payload, near the top.
  let shallowFile: AbsolutePath
  /// One file further down, so a walk that stopped at the first level is
  /// caught.
  let deepFile: AbsolutePath
  /// A directory inside the payload, the one a test strips to make part of
  /// the payload unreadable.
  let innerDirectory: AbsolutePath
  /// The allocated total of the whole subtree, the payload directory itself
  /// included. What C8 says the item records.
  let subtreeBytes: UInt64
  /// What the payload directory's own record reports. A store that entered
  /// nothing comes back with this, and it is the figure the defect produced.
  let ownBytes: UInt64
}

/// Seeds a directory payload shaped like the thing an uninstall archives:
/// a directory with files at two depths, one of them executable.
///
/// Every uninstall archives directories, so this is the common case rather
/// than an exotic one.
@discardableResult
func safetyNetSeedDirectory(
  in fileSystem: InMemoryFileSystem,
  at root: AbsolutePath,
  seed: UInt8,
  sourceLocation: SourceLocation = #_sourceLocation
) async throws -> SafetyNetDirectoryPayload {
  let contents = root.appending("Contents")
  let macOS = contents.appending("MacOS")
  for directory in [root, contents, macOS] {
    await fileSystem.seedDirectory(at: directory)
  }
  let shallow = root.appending("notes.txt")
  let deep = macOS.appending("tool")
  await fileSystem.seedFile(
    at: shallow,
    contents: FileSystemFixture.contents(seed, length: 512),
    isExecutable: false,
    created: SafetyNetFixture.createdDate,
    modified: SafetyNetFixture.modifiedDate,
    lastOpened: nil,
    extendedAttributes: SafetyNetFixture.attributes(seed)
  )
  await fileSystem.seedFile(
    at: deep,
    contents: FileSystemFixture.contents(seed &+ 1, length: 4096),
    isExecutable: true,
    created: SafetyNetFixture.createdDate,
    modified: SafetyNetFixture.modifiedDate,
    lastOpened: nil,
    extendedAttributes: SafetyNetFixture.attributes(seed &+ 1)
  )

  let ownBytes = try await fileSystem.metadata(at: root).allocatedBytes
  let subtreeBytes = try await safetyNetSubtreeBytes(of: root, in: fileSystem)
  // Without this the recorded size could equal the directory's own record and
  // every assertion about a subtree total would prove nothing.
  #expect(
    subtreeBytes > ownBytes,
    "a payload whose contents weigh nothing cannot prove a subtree total",
    sourceLocation: sourceLocation
  )
  return SafetyNetDirectoryPayload(
    root: root,
    shallowFile: shallow,
    deepFile: deep,
    innerDirectory: contents,
    subtreeBytes: subtreeBytes,
    ownBytes: ownBytes
  )
}

/// Asserts restore fidelity one attribute at a time. A copy passes "the file
/// exists"; only this catches a lost attribute, and it names which one.
func expectSameFile(
  _ actual: SafetyNetPathState,
  _ expected: SafetyNetPathState,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(actual.contents == expected.contents, "contents", sourceLocation: sourceLocation)
  #expect(
    actual.posixPermissions == expected.posixPermissions,
    "permission mode",
    sourceLocation: sourceLocation
  )
  #expect(
    actual.extendedAttributes == expected.extendedAttributes,
    "extended attributes",
    sourceLocation: sourceLocation
  )
  #expect(actual.created == expected.created, "creation date", sourceLocation: sourceLocation)
  #expect(actual.modified == expected.modified, "modification date", sourceLocation: sourceLocation)
}

// MARK: - Items

func safetyNetItem(_ id: UUID, in items: [SafetyNetItem]) -> SafetyNetItem? {
  items.first { $0.id == id }
}

func safetyNetIdentifiers(_ items: [SafetyNetItem]) -> Set<UUID> {
  Set(items.map(\.id))
}

// MARK: - Purge confirmation

/// The bytes a purge accounts for: the sum, over the items named in it, of
/// the sizes those items recorded when they were stored (C18). Nothing here
/// touches the file system, because the store's own payloads cannot be read
/// once execute has been stripped from them and a confirmation is an
/// agreement about a recorded fact rather than a second reading of a disk.
func safetyNetStoredBytes(of items: [SafetyNetItem]) -> UInt64 {
  items.reduce(UInt64(0)) { $0 + $1.allocatedBytes }
}

/// A confirmation that matches the items exactly. Tests that expect a refusal
/// build this and then break one field, so the two mismatch cases differ from
/// the accepted case in exactly one number.
func safetyNetConfirmation(for items: [SafetyNetItem]) -> PurgeConfirmation {
  PurgeConfirmation(
    itemCount: UInt32(items.count),
    byteTotal: safetyNetStoredBytes(of: items),
    confirmedAt: SafetyNetFixture.confirmationInstant
  )
}

// MARK: - Watching what the store reads

/// Every read side call made through the boundary, in request order.
///
/// `exists` and `volumeInfo` are deliberately not recorded. Asking whether a
/// path is there, or what volume it sits on, is not reading what is inside
/// it, and a purge about to remove a payload may reasonably ask. Reading the
/// payload is what C18 forbids at purge time, so that is what this records.
final class FileSystemReadLog: @unchecked Sendable {

  struct Call: Sendable, Equatable, CustomStringConvertible {
    let method: String
    let path: AbsolutePath

    var description: String { "\(method)(\(path.value))" }
  }

  private let lock = NSLock()
  private var storage: [Call] = []

  func note(_ method: String, _ path: AbsolutePath) {
    lock.lock()
    defer { lock.unlock() }
    storage.append(Call(method: method, path: path))
  }

  var calls: [Call] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  /// Forgets everything recorded so far, so a test can watch one operation
  /// rather than the whole session.
  func reset() {
    lock.lock()
    defer { lock.unlock() }
    storage.removeAll()
  }

  /// Every call that read the given path or something under it.
  func callsReading(_ path: AbsolutePath) -> [Call] {
    calls.filter { $0.path == path || $0.path.isDescendant(of: path) }
  }
}

/// A file system that records what was read through it and otherwise behaves
/// exactly like the one it wraps. Nothing is faked; only the calls are
/// counted.
struct ReadRecordingFileSystem: FileSystem {
  let backing: InMemoryFileSystem
  let log: FileSystemReadLog

  func enumerate(
    root: AbsolutePath,
    options: EnumerationOptions
  ) -> AsyncThrowingStream<EnumerationEvent, Error> {
    log.note("enumerate", root)
    return backing.enumerate(root: root, options: options)
  }

  func metadata(at path: AbsolutePath) async throws -> FileRecord {
    log.note("metadata", path)
    return try await backing.metadata(at: path)
  }

  func posixPermissions(at path: AbsolutePath) async throws -> UInt16 {
    log.note("posixPermissions", path)
    return try await backing.posixPermissions(at: path)
  }

  func readData(at path: AbsolutePath, maxBytes: UInt64) async throws -> Data {
    log.note("readData", path)
    return try await backing.readData(at: path, maxBytes: maxBytes)
  }

  func extendedAttributes(at path: AbsolutePath) async throws -> [String: Data] {
    log.note("extendedAttributes", path)
    return try await backing.extendedAttributes(at: path)
  }

  func exists(_ path: AbsolutePath) async -> Bool {
    await backing.exists(path)
  }

  func volumeInfo(at path: AbsolutePath) async throws -> VolumeInfo {
    try await backing.volumeInfo(at: path)
  }

  func moveToTrash(_ path: AbsolutePath) async throws -> AbsolutePath {
    try await backing.moveToTrash(path)
  }

  func move(_ source: AbsolutePath, to destination: AbsolutePath) async throws {
    try await backing.move(source, to: destination)
  }

  func delete(_ path: AbsolutePath) async throws {
    try await backing.delete(path)
  }

  func createDirectory(at path: AbsolutePath) async throws {
    try await backing.createDirectory(at: path)
  }

  func writeData(_ data: Data, to path: AbsolutePath) async throws {
    try await backing.writeData(data, to: path)
  }

  func setPosixPermissions(_ mode: UInt16, at path: AbsolutePath) async throws {
    try await backing.setPosixPermissions(mode, at: path)
  }

  func setExtendedAttributes(_ attributes: [String: Data], at path: AbsolutePath) async throws {
    try await backing.setExtendedAttributes(attributes, at: path)
  }
}
