import Foundation
import GleamCore
import Testing

/// C18, storing. The store is where a destructive action becomes reversible,
/// so storing has two jobs at once: make the payload harmless where it sits,
/// and record everything restore will need. Both are asserted here; restoring
/// is the next suite.
@Suite("SafetyNet store: storing")
struct SafetyNetStoreQuarantineTests {

  private static let origin = Fixture.path("/Users/julian/Downloads/agent")

  @Test("stores by moving, so the origin is gone and the payload holds the contents")
  func storeMovesRatherThanCopies() async throws {
    let fileSystem = await safetyNetFileSystem()
    let before = try await safetyNetSeedFile(
      in: fileSystem, at: Self.origin, seed: 10, isExecutable: true)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(Self.origin, source: .malwareQuarantine, groupID: nil)

    #expect(!(await fileSystem.exists(Self.origin)))
    #expect(await fileSystem.exists(item.storedPath))
    let payload = try await fileSystem.readData(at: item.storedPath, maxBytes: 1_000_000)
    #expect(payload == before.contents)
  }

  @Test("places the payload inside the store directory")
  func storedPayloadLivesInTheStoreDirectory() async throws {
    let fileSystem = await safetyNetFileSystem()
    try await safetyNetSeedFile(in: fileSystem, at: Self.origin, seed: 11, isExecutable: true)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(Self.origin, source: .malwareQuarantine, groupID: nil)

    #expect(item.storedPath.isDescendant(of: SafetyNetFixture.directory))
  }

  @Test("strips every execute bit from the stored payload")
  func storeStripsExecutePermission() async throws {
    let fileSystem = await safetyNetFileSystem()
    try await safetyNetSeedFile(in: fileSystem, at: Self.origin, seed: 12, isExecutable: true)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(Self.origin, source: .malwareQuarantine, groupID: nil)

    let mode = try await fileSystem.posixPermissions(at: item.storedPath)
    #expect(mode & 0o111 == 0)
  }

  @Test("strips execute and nothing else from the stored payload")
  func storeStripsOnlyExecutePermission() async throws {
    let fileSystem = await safetyNetFileSystem()
    let before = try await safetyNetSeedFile(
      in: fileSystem, at: Self.origin, seed: 13, isExecutable: true)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(Self.origin, source: .malwareQuarantine, groupID: nil)

    let mode = try await fileSystem.posixPermissions(at: item.storedPath)
    #expect(mode == before.posixPermissions & ~UInt16(0o111))
  }

  @Test("preserves the extended attributes on the stored payload")
  func storePreservesExtendedAttributesOnThePayload() async throws {
    let fileSystem = await safetyNetFileSystem()
    let before = try await safetyNetSeedFile(
      in: fileSystem, at: Self.origin, seed: 14, isExecutable: true)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(Self.origin, source: .malwareQuarantine, groupID: nil)

    let attributes = try await fileSystem.extendedAttributes(at: item.storedPath)
    #expect(attributes == before.extendedAttributes)
  }

  @Test("snapshots the permission mode the file had before storing")
  func snapshotCarriesTheOriginalPermissionMode() async throws {
    let fileSystem = await safetyNetFileSystem()
    let before = try await safetyNetSeedFile(
      in: fileSystem, at: Self.origin, seed: 15, isExecutable: true)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(Self.origin, source: .malwareQuarantine, groupID: nil)

    #expect(item.metadata.posixPermissions == before.posixPermissions)
  }

  @Test("snapshots the extended attributes the file had before storing")
  func snapshotCarriesTheOriginalExtendedAttributes() async throws {
    let fileSystem = await safetyNetFileSystem()
    let before = try await safetyNetSeedFile(
      in: fileSystem, at: Self.origin, seed: 16, isExecutable: true)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(Self.origin, source: .malwareQuarantine, groupID: nil)

    #expect(item.metadata.extendedAttributes == before.extendedAttributes)
  }

  @Test("snapshots the creation and modification dates the file had before storing")
  func snapshotCarriesTheOriginalDates() async throws {
    let fileSystem = await safetyNetFileSystem()
    let before = try await safetyNetSeedFile(
      in: fileSystem, at: Self.origin, seed: 17, isExecutable: true)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(Self.origin, source: .malwareQuarantine, groupID: nil)

    #expect(item.metadata.created == before.created)
    #expect(item.metadata.modified == before.modified)
  }

  @Test("records the origin path and the source on the item")
  func itemRecordsOriginAndSource() async throws {
    let fileSystem = await safetyNetFileSystem()
    try await safetyNetSeedFile(in: fileSystem, at: Self.origin, seed: 18, isExecutable: true)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(Self.origin, source: .malwareQuarantine, groupID: nil)

    #expect(item.originPath == Self.origin)
    #expect(item.source == .malwareQuarantine)
    #expect(item.groupID == nil)
    #expect(item.isRestored == false)
  }

  @Test("records the group an archived file belongs to")
  func itemRecordsTheGroup() async throws {
    let fileSystem = await safetyNetFileSystem()
    let path = Fixture.path("/Users/julian/Library/Preferences/com.example.app.plist")
    try await safetyNetSeedFile(in: fileSystem, at: path, seed: 19)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(path, source: .uninstallArchive, groupID: Fixture.groupID)

    #expect(item.groupID == Fixture.groupID)
    #expect(item.source == .uninstallArchive)
  }

  @Test("stamps storedAt from the injected instant, never from a clock")
  func storedAtComesFromTheInjectedInstant() async throws {
    let fileSystem = await safetyNetFileSystem()
    try await safetyNetSeedFile(in: fileSystem, at: Self.origin, seed: 20, isExecutable: true)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(Self.origin, source: .malwareQuarantine, groupID: nil)

    #expect(item.storedAt == SafetyNetFixture.storeInstant)
  }

  @Test("sets expiresAt exactly thirty days after storedAt")
  func expiryIsThirtyDaysAfterStoring() async throws {
    let fileSystem = await safetyNetFileSystem()
    try await safetyNetSeedFile(in: fileSystem, at: Self.origin, seed: 21, isExecutable: true)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(Self.origin, source: .malwareQuarantine, groupID: nil)

    #expect(item.expiresAt == item.storedAt.addingTimeInterval(Fixture.thirtyDays))
    #expect(item.expiresAt == SafetyNetFixture.expiryInstant)
  }

  @Test("lists the item it just stored")
  func storedItemIsListed() async throws {
    let fileSystem = await safetyNetFileSystem()
    try await safetyNetSeedFile(in: fileSystem, at: Self.origin, seed: 22, isExecutable: true)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(Self.origin, source: .malwareQuarantine, groupID: nil)

    let listed = try await store.items(includingRestored: false)
    #expect(safetyNetIdentifiers(listed) == [item.id])
    #expect(safetyNetItem(item.id, in: listed) == item)
  }

  @Test("gives two files sharing a name distinct stored paths")
  func filesSharingANameDoNotCollideInTheStore() async throws {
    let fileSystem = await safetyNetFileSystem(directories: [
      Fixture.path("/Applications/Example.app"),
      Fixture.path("/Applications/Example.app/Contents"),
      Fixture.path("/Users/julian/Library/Application Support/Example"),
    ])
    let first = Fixture.path("/Applications/Example.app/Contents/Info.plist")
    let second = Fixture.path("/Users/julian/Library/Application Support/Example/Info.plist")
    let firstBefore = try await safetyNetSeedFile(in: fileSystem, at: first, seed: 23)
    let secondBefore = try await safetyNetSeedFile(in: fileSystem, at: second, seed: 24)
    let store = safetyNetMake(fileSystem: fileSystem)

    let firstItem = try await store.store(
      first, source: .uninstallArchive, groupID: Fixture.groupID)
    let secondItem = try await store.store(
      second, source: .uninstallArchive, groupID: Fixture.groupID)

    #expect(firstItem.storedPath != secondItem.storedPath)
    let firstPayload = try await fileSystem.readData(at: firstItem.storedPath, maxBytes: 1_000_000)
    let secondPayload = try await fileSystem.readData(
      at: secondItem.storedPath, maxBytes: 1_000_000)
    #expect(firstPayload == firstBefore.contents)
    #expect(secondPayload == secondBefore.contents)
  }

  @Test("refuses a denylisted path")
  func denylistedPathIsRefused() async throws {
    let fileSystem = await safetyNetFileSystem(directories: [
      Fixture.path("/System"),
      Fixture.path("/System/Library"),
    ])
    let guarded = Fixture.path("/System/Library/loginwindow")
    try await safetyNetSeedFile(in: fileSystem, at: guarded, seed: 25, isExecutable: true)
    let store = safetyNetMake(fileSystem: fileSystem, denylist: makeDenylist(["/System"]))

    await #expect(throws: SafetyNetError.denylistedPath(guarded)) {
      _ = try await store.store(guarded, source: .malwareQuarantine, groupID: nil)
    }
  }

  @Test("leaves a denylisted path exactly where it was")
  func denylistedPathIsUntouched() async throws {
    let fileSystem = await safetyNetFileSystem(directories: [
      Fixture.path("/System"),
      Fixture.path("/System/Library"),
    ])
    let guarded = Fixture.path("/System/Library/loginwindow")
    let before = try await safetyNetSeedFile(
      in: fileSystem, at: guarded, seed: 26, isExecutable: true)
    let store = safetyNetMake(fileSystem: fileSystem, denylist: makeDenylist(["/System"]))

    _ = try? await store.store(guarded, source: .malwareQuarantine, groupID: nil)

    let after = try await safetyNetState(of: guarded, in: fileSystem)
    expectSameFile(after, before)
    let history = try await store.items(includingRestored: true)
    #expect(history.isEmpty)
  }
}
