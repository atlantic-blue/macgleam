import Foundation
import GleamCore
import Testing

/// C18, group restore. An uninstall archives many files as one unit, so a
/// partial restore leaves an application half present, which is worse than
/// not restoring at all. Every failure case here asserts that nothing moved,
/// not merely that something threw.
@Suite("SafetyNet store: group restore is all or nothing")
struct SafetyNetStoreGroupRestoreTests {

  private static let bundleFile = Fixture.path("/Applications/Example.app/Contents/Info.plist")
  private static let preferences = Fixture.path(
    "/Users/julian/Library/Preferences/com.example.app.plist")
  private static let supportFile = Fixture.path(
    "/Users/julian/Library/Application Support/Example/state.json")

  private static let directories = [
    Fixture.path("/Applications/Example.app"),
    Fixture.path("/Applications/Example.app/Contents"),
    Fixture.path("/Users/julian/Library/Application Support/Example"),
  ]

  /// One archived application: three files under one group identifier, and
  /// what each looked like before it was archived.
  private struct ArchivedApp {
    let fileSystem: InMemoryFileSystem
    let store: SafetyNetStore
    let items: [SafetyNetItem]
    let before: [AbsolutePath: SafetyNetPathState]

    func item(for origin: AbsolutePath) -> SafetyNetItem? {
      items.first { $0.originPath == origin }
    }
  }

  private func archiveExampleApp(
    seed: UInt8,
    groupID: UUID = Fixture.groupID
  ) async throws -> ArchivedApp {
    let fileSystem = await safetyNetFileSystem(directories: Self.directories)
    let origins = [Self.bundleFile, Self.preferences, Self.supportFile]
    var before: [AbsolutePath: SafetyNetPathState] = [:]
    for (offset, origin) in origins.enumerated() {
      before[origin] = try await safetyNetSeedFile(
        in: fileSystem,
        at: origin,
        seed: seed &+ UInt8(offset),
        isExecutable: offset == 0
      )
    }
    let store = safetyNetMake(fileSystem: fileSystem)
    var items: [SafetyNetItem] = []
    for origin in origins {
      items.append(try await store.store(origin, source: .uninstallArchive, groupID: groupID))
    }
    return ArchivedApp(fileSystem: fileSystem, store: store, items: items, before: before)
  }

  @Test("restores every file of the group to its own origin path")
  func groupRestorePutsEveryFileBack() async throws {
    let app = try await archiveExampleApp(seed: 50)

    try await app.store.restoreGroup(groupID: Fixture.groupID)

    for item in app.items {
      #expect(await app.fileSystem.exists(item.originPath))
    }
  }

  @Test("restores every file of the group attribute for attribute")
  func groupRestoreIsFaithfulForEveryFile() async throws {
    let app = try await archiveExampleApp(seed: 54)

    try await app.store.restoreGroup(groupID: Fixture.groupID)

    for item in app.items {
      let after = try await safetyNetState(of: item.originPath, in: app.fileSystem)
      let before = try #require(app.before[item.originPath])
      expectSameFile(after, before)
    }
  }

  @Test("empties the store of the group's payloads")
  func groupRestoreRemovesEveryPayload() async throws {
    let app = try await archiveExampleApp(seed: 58)

    try await app.store.restoreGroup(groupID: Fixture.groupID)

    for item in app.items {
      #expect(!(await app.fileSystem.exists(item.storedPath)))
    }
  }

  @Test("marks every item of the group restored")
  func groupRestoreMarksEveryItem() async throws {
    let app = try await archiveExampleApp(seed: 62)

    try await app.store.restoreGroup(groupID: Fixture.groupID)

    let history = try await app.store.items(includingRestored: true)
    for item in app.items {
      #expect(safetyNetItem(item.id, in: history)?.isRestored == true)
    }
  }

  // MARK: - One occupied origin sinks the whole restore

  @Test("names the occupied origin when one file of the group cannot go back")
  func occupiedOriginNamesThePath() async throws {
    let app = try await archiveExampleApp(seed: 66)
    try await safetyNetSeedFile(in: app.fileSystem, at: Self.preferences, seed: 200)

    await #expect(throws: SafetyNetError.originOccupied(Self.preferences)) {
      try await app.store.restoreGroup(groupID: Fixture.groupID)
    }
  }

  @Test("moves no file of the group when one origin is occupied")
  func occupiedOriginLeavesEveryOtherOriginEmpty() async throws {
    let app = try await archiveExampleApp(seed: 70)
    try await safetyNetSeedFile(in: app.fileSystem, at: Self.preferences, seed: 201)

    try? await app.store.restoreGroup(groupID: Fixture.groupID)

    #expect(!(await app.fileSystem.exists(Self.bundleFile)))
    #expect(!(await app.fileSystem.exists(Self.supportFile)))
  }

  @Test("leaves every payload of the group in the store when one origin is occupied")
  func occupiedOriginLeavesEveryPayloadStored() async throws {
    let app = try await archiveExampleApp(seed: 74)
    try await safetyNetSeedFile(in: app.fileSystem, at: Self.preferences, seed: 202)

    try? await app.store.restoreGroup(groupID: Fixture.groupID)

    for item in app.items {
      #expect(await app.fileSystem.exists(item.storedPath))
    }
  }

  @Test("leaves every item of the group unrestored when one origin is occupied")
  func occupiedOriginLeavesEveryItemUnrestored() async throws {
    let app = try await archiveExampleApp(seed: 78)
    try await safetyNetSeedFile(in: app.fileSystem, at: Self.preferences, seed: 203)

    try? await app.store.restoreGroup(groupID: Fixture.groupID)

    let listed = try await app.store.items(includingRestored: false)
    #expect(safetyNetIdentifiers(listed) == safetyNetIdentifiers(app.items))
    for item in app.items {
      #expect(safetyNetItem(item.id, in: listed)?.isRestored == false)
    }
  }

  @Test("leaves the occupying file untouched when it refuses")
  func occupierSurvivesARefusedGroupRestore() async throws {
    let app = try await archiveExampleApp(seed: 82)
    let occupier = try await safetyNetSeedFile(
      in: app.fileSystem, at: Self.preferences, seed: 204)

    try? await app.store.restoreGroup(groupID: Fixture.groupID)

    let after = try await safetyNetState(of: Self.preferences, in: app.fileSystem)
    expectSameFile(after, occupier)
  }

  @Test("restores the whole group once the occupying file is out of the way")
  func groupRestoreSucceedsAfterTheOccupierIsRemoved() async throws {
    let app = try await archiveExampleApp(seed: 86)
    try await safetyNetSeedFile(in: app.fileSystem, at: Self.preferences, seed: 205)
    try? await app.store.restoreGroup(groupID: Fixture.groupID)

    try await app.fileSystem.delete(Self.preferences)
    try await app.store.restoreGroup(groupID: Fixture.groupID)

    for item in app.items {
      let after = try await safetyNetState(of: item.originPath, in: app.fileSystem)
      let before = try #require(app.before[item.originPath])
      expectSameFile(after, before)
    }
  }

  // MARK: - Scope

  @Test("restores the rest of the group when one item was already restored on its own")
  func groupRestoreSkipsAnAlreadyRestoredItem() async throws {
    let app = try await archiveExampleApp(seed: 90)
    let alreadyBack = try #require(app.item(for: Self.supportFile))
    try await app.store.restore(itemID: alreadyBack.id)

    try await app.store.restoreGroup(groupID: Fixture.groupID)

    #expect(await app.fileSystem.exists(Self.bundleFile))
    #expect(await app.fileSystem.exists(Self.preferences))
    let after = try await safetyNetState(of: Self.supportFile, in: app.fileSystem)
    let before = try #require(app.before[Self.supportFile])
    expectSameFile(after, before)
  }

  @Test("leaves items of another group where they are")
  func groupRestoreTouchesOnlyItsOwnGroup() async throws {
    let app = try await archiveExampleApp(seed: 94)
    let otherOrigin = Fixture.path("/Users/julian/Downloads/other.plist")
    try await safetyNetSeedFile(in: app.fileSystem, at: otherOrigin, seed: 206)
    let otherItem = try await app.store.store(
      otherOrigin, source: .uninstallArchive, groupID: Fixture.uuid(0x77))

    try await app.store.restoreGroup(groupID: Fixture.groupID)

    #expect(await app.fileSystem.exists(otherItem.storedPath))
    #expect(!(await app.fileSystem.exists(otherOrigin)))
    let listed = try await app.store.items(includingRestored: false)
    #expect(safetyNetIdentifiers(listed) == [otherItem.id])
  }
}
