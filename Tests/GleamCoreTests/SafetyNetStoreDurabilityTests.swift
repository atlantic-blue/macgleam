import Foundation
import GleamCore
import Testing

/// C18, durability. Two guarantees that only show up over time: the manifest
/// outlives the copy of the app that wrote it, and concurrent work cannot
/// corrupt it.
///
/// Reinstall is simulated by building a second store over the same directory,
/// which is exactly what a reinstalled app does. Nothing real is deleted.
@Suite("SafetyNet store: reinstall survival and serialised mutations")
struct SafetyNetStoreDurabilityTests {

  private static let origin = Fixture.path("/Users/julian/Downloads/agent")
  private static let bundleExecutable = Fixture.path("/Applications/MacGleam.app/MacGleam")

  private func fileSystemWithInstalledApp() async -> InMemoryFileSystem {
    await safetyNetFileSystem(directories: [SafetyNetFixture.applicationBundle])
  }

  @Test("a fresh store over the same directory lists what the old one stored")
  func afterReinstallTheItemsAreStillListed() async throws {
    let fileSystem = await fileSystemWithInstalledApp()
    try await safetyNetSeedFile(
      in: fileSystem, at: Self.bundleExecutable, seed: 120, isExecutable: true)
    try await safetyNetSeedFile(in: fileSystem, at: Self.origin, seed: 121, isExecutable: true)
    let firstInstall = safetyNetMake(fileSystem: fileSystem)
    let item = try await firstInstall.store(
      Self.origin, source: .malwareQuarantine, groupID: nil)

    try await fileSystem.delete(SafetyNetFixture.applicationBundle)
    let secondInstall = safetyNetMake(fileSystem: fileSystem)

    let listed = try await secondInstall.items(includingRestored: false)
    #expect(safetyNetIdentifiers(listed) == [item.id])
  }

  @Test("a fresh store returns every field of the item unchanged")
  func afterReinstallTheItemIsUnchanged() async throws {
    let fileSystem = await fileSystemWithInstalledApp()
    try await safetyNetSeedFile(
      in: fileSystem, at: Self.bundleExecutable, seed: 122, isExecutable: true)
    try await safetyNetSeedFile(in: fileSystem, at: Self.origin, seed: 123, isExecutable: true)
    let firstInstall = safetyNetMake(fileSystem: fileSystem)
    let item = try await firstInstall.store(
      Self.origin, source: .malwareQuarantine, groupID: Fixture.groupID)

    try await fileSystem.delete(SafetyNetFixture.applicationBundle)
    let secondInstall = safetyNetMake(fileSystem: fileSystem)

    let listed = try await secondInstall.items(includingRestored: false)
    let recovered = try #require(safetyNetItem(item.id, in: listed))
    #expect(recovered.originPath == item.originPath)
    #expect(recovered.storedPath == item.storedPath)
    #expect(recovered.source == item.source)
    #expect(recovered.groupID == item.groupID)
    #expect(recovered.storedAt == item.storedAt)
    #expect(recovered.expiresAt == item.expiresAt)
    #expect(recovered.isRestored == item.isRestored)
    #expect(recovered.metadata == item.metadata)
  }

  @Test("a fresh store restores a payload the old one stored, attribute for attribute")
  func afterReinstallTheItemStillRestores() async throws {
    let fileSystem = await fileSystemWithInstalledApp()
    try await safetyNetSeedFile(
      in: fileSystem, at: Self.bundleExecutable, seed: 124, isExecutable: true)
    let before = try await safetyNetSeedFile(
      in: fileSystem, at: Self.origin, seed: 125, isExecutable: true)
    let firstInstall = safetyNetMake(fileSystem: fileSystem)
    let item = try await firstInstall.store(Self.origin, source: .malwareQuarantine, groupID: nil)

    try await fileSystem.delete(SafetyNetFixture.applicationBundle)
    let secondInstall = safetyNetMake(fileSystem: fileSystem)
    try await secondInstall.restore(itemID: item.id)

    let after = try await safetyNetState(of: Self.origin, in: fileSystem)
    expectSameFile(after, before)
  }

  @Test("a fresh store carries the restore history forward")
  func afterReinstallTheHistorySurvives() async throws {
    let fileSystem = await fileSystemWithInstalledApp()
    try await safetyNetSeedFile(in: fileSystem, at: Self.origin, seed: 126, isExecutable: true)
    let firstInstall = safetyNetMake(fileSystem: fileSystem)
    let item = try await firstInstall.store(Self.origin, source: .malwareQuarantine, groupID: nil)
    try await firstInstall.restore(itemID: item.id)

    let secondInstall = safetyNetMake(fileSystem: fileSystem)

    let history = try await secondInstall.items(includingRestored: true)
    #expect(safetyNetItem(item.id, in: history)?.isRestored == true)
    let listed = try await secondInstall.items(includingRestored: false)
    #expect(listed.isEmpty)
  }

  @Test("a fresh store over an empty directory lists nothing rather than failing")
  func aFirstLaunchListsNothing() async throws {
    let fileSystem = await safetyNetFileSystem()
    let store = safetyNetMake(fileSystem: fileSystem)

    let listed = try await store.items(includingRestored: true)

    #expect(listed.isEmpty)
  }

  // MARK: - Serialised mutations

  private static let concurrentCount = 8

  private func seedConcurrentPayloads(in fileSystem: InMemoryFileSystem) async throws
    -> [AbsolutePath]
  {
    var origins: [AbsolutePath] = []
    for index in 0..<Self.concurrentCount {
      let path = Fixture.path("/Users/julian/Downloads/payload-\(index)")
      try await safetyNetSeedFile(
        in: fileSystem, at: path, seed: UInt8(130 + index), isExecutable: true)
      origins.append(path)
    }
    return origins
  }

  @Test("every concurrent store appears in the listing exactly once")
  func concurrentStoresAllLand() async throws {
    let fileSystem = await safetyNetFileSystem()
    let origins = try await seedConcurrentPayloads(in: fileSystem)
    let store = safetyNetMake(fileSystem: fileSystem)

    let items = try await withThrowingTaskGroup(of: SafetyNetItem.self) { group in
      for origin in origins {
        group.addTask {
          try await store.store(origin, source: .malwareQuarantine, groupID: nil)
        }
      }
      var stored: [SafetyNetItem] = []
      for try await item in group {
        stored.append(item)
      }
      return stored
    }

    #expect(safetyNetIdentifiers(items).count == Self.concurrentCount)
    let listed = try await store.items(includingRestored: false)
    #expect(safetyNetIdentifiers(listed) == safetyNetIdentifiers(items))
  }

  @Test("every concurrent store gets its own payload path")
  func concurrentStoresDoNotShareAPayloadPath() async throws {
    let fileSystem = await safetyNetFileSystem()
    let origins = try await seedConcurrentPayloads(in: fileSystem)
    let store = safetyNetMake(fileSystem: fileSystem)

    let items = try await withThrowingTaskGroup(of: SafetyNetItem.self) { group in
      for origin in origins {
        group.addTask {
          try await store.store(origin, source: .malwareQuarantine, groupID: nil)
        }
      }
      var stored: [SafetyNetItem] = []
      for try await item in group {
        stored.append(item)
      }
      return stored
    }

    #expect(Set(items.map(\.storedPath)).count == Self.concurrentCount)
    for item in items {
      #expect(await fileSystem.exists(item.storedPath))
      #expect(!(await fileSystem.exists(item.originPath)))
    }
  }

  @Test("a manifest written concurrently is whole when a fresh store reads it")
  func concurrentStoresSurviveIntoAFreshManifest() async throws {
    let fileSystem = await safetyNetFileSystem()
    let origins = try await seedConcurrentPayloads(in: fileSystem)
    let store = safetyNetMake(fileSystem: fileSystem)
    let items = try await withThrowingTaskGroup(of: SafetyNetItem.self) { group in
      for origin in origins {
        group.addTask {
          try await store.store(origin, source: .malwareQuarantine, groupID: nil)
        }
      }
      var stored: [SafetyNetItem] = []
      for try await item in group {
        stored.append(item)
      }
      return stored
    }

    let reopened = safetyNetMake(fileSystem: fileSystem)

    let listed = try await reopened.items(includingRestored: false)
    #expect(safetyNetIdentifiers(listed) == safetyNetIdentifiers(items))
  }

  @Test("a restore running beside other stores leaves the manifest consistent")
  func aConcurrentRestoreDoesNotCorruptTheManifest() async throws {
    let fileSystem = await safetyNetFileSystem()
    let origins = try await seedConcurrentPayloads(in: fileSystem)
    let store = safetyNetMake(fileSystem: fileSystem)
    let first = try await store.store(origins[0], source: .malwareQuarantine, groupID: nil)
    let rest = Array(origins.dropFirst())

    let stored = try await withThrowingTaskGroup(of: SafetyNetItem?.self) { group in
      group.addTask {
        try await store.restore(itemID: first.id)
        return nil
      }
      for origin in rest {
        group.addTask {
          try await store.store(origin, source: .malwareQuarantine, groupID: nil)
        }
      }
      var items: [SafetyNetItem] = []
      for try await item in group {
        if let item {
          items.append(item)
        }
      }
      return items
    }

    let reopened = safetyNetMake(fileSystem: fileSystem)
    let listed = try await reopened.items(includingRestored: false)
    #expect(safetyNetIdentifiers(listed) == safetyNetIdentifiers(stored))
    let history = try await reopened.items(includingRestored: true)
    #expect(safetyNetItem(first.id, in: history)?.isRestored == true)
    #expect(await fileSystem.exists(origins[0]))
  }
}
