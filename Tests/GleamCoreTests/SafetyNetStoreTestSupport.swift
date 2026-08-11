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

/// The bytes a purge accounts for: the allocated bytes of the payloads it
/// removes, the same basis every other byte figure in MacGleam uses (C6).
func safetyNetStoredBytes(
  of items: [SafetyNetItem],
  in fileSystem: any FileSystem
) async throws -> UInt64 {
  var total: UInt64 = 0
  for item in items {
    total += try await fileSystem.metadata(at: item.storedPath).allocatedBytes
  }
  return total
}

/// A confirmation that matches the items exactly. Tests that expect a refusal
/// build this and then break one field, so the two mismatch cases differ from
/// the accepted case in exactly one number.
func safetyNetConfirmation(
  for items: [SafetyNetItem],
  in fileSystem: any FileSystem
) async throws -> PurgeConfirmation {
  PurgeConfirmation(
    itemCount: UInt32(items.count),
    byteTotal: try await safetyNetStoredBytes(of: items, in: fileSystem),
    confirmedAt: SafetyNetFixture.confirmationInstant
  )
}
