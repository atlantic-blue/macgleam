import CleanupModule
import Foundation
import GleamCore
import Testing

/// C35 against the concrete store this slice implements. The demanded
/// surface is `SettingsStore: SettingsStoring` with `init(directory: URL)`,
/// persisting inside exactly that directory. Tests use a fresh temporary
/// directory each and go only through the protocol surface.
@Suite("Settings store (C35)")
struct SettingsStoreTests {

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("macgleam-settings-store-tests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func customSettings() -> Settings {
    Settings(
      deletionMode: .permanent,
      largeFileThresholdBytes: 5_000_000_000,
      oldFileThresholdDays: 30,
      menuBar: MenuBarPreferences(showsStorage: false, showsMemory: true, showsProcessorLoad: true),
      motion: MotionPreferences(reduceMotionOverride: true)
    )
  }

  @Test("a missing store loads the defaults")
  func aMissingStoreLoadsTheDefaults() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SettingsStore(directory: directory)
    #expect(await store.load() == Settings.defaults)
  }

  @Test("a directory that does not exist loads the defaults, never a crash")
  func aNonexistentDirectoryLoadsTheDefaults() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let missing = directory.appendingPathComponent("never-created", isDirectory: true)
    let store = SettingsStore(directory: missing)
    #expect(await store.load() == Settings.defaults)
  }

  @Test("saved settings load back identically")
  func savedSettingsLoadBackIdentically() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SettingsStore(directory: directory)
    let settings = customSettings()
    try await store.save(settings)
    #expect(await store.load() == settings)
  }

  @Test("saved settings survive a fresh store over the same directory, deletion mode included")
  func savedSettingsSurviveAFreshStore() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let settings = customSettings()
    try await SettingsStore(directory: directory).save(settings)

    let reopened = SettingsStore(directory: directory)
    let loaded = await reopened.load()
    #expect(loaded == settings)
    #expect(loaded.deletionMode == .permanent)
  }

  @Test("a corrupt store loads the defaults and never a permanent deletion mode")
  func aCorruptStoreLoadsTheDefaults() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try await SettingsStore(directory: directory).save(customSettings())

    let fileManager = FileManager.default
    let subpaths = try fileManager.subpathsOfDirectory(atPath: directory.path)
    var corruptedCount = 0
    for subpath in subpaths {
      let fileURL = directory.appendingPathComponent(subpath)
      var isDirectory: ObjCBool = false
      if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
        !isDirectory.boolValue
      {
        try Data(repeating: 0x7F, count: 64).write(to: fileURL)
        corruptedCount += 1
      }
    }
    #expect(corruptedCount > 0, "the store must persist inside the directory it was given")

    let reopened = SettingsStore(directory: directory)
    let loaded = await reopened.load()
    #expect(loaded == Settings.defaults)
    #expect(loaded.deletionMode == .trash)
  }

  @Test("updates emits the new value after each successful save, in order")
  func updatesEmitsAfterEachSuccessfulSave() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SettingsStore(directory: directory)
    let stream = store.updates()
    var iterator = stream.makeAsyncIterator()

    let first = customSettings()
    var second = Settings.defaults
    second.oldFileThresholdDays = 7
    try await store.save(first)
    try await store.save(second)

    #expect(await iterator.next() == first)
    #expect(await iterator.next() == second)
  }

  @Test("a failed save throws, leaves the previous settings on disk, and emits nothing")
  func aFailedSaveLeavesThePreviousSettings() async throws {
    let directory = try makeTemporaryDirectory()
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: directory.path)
      try? FileManager.default.removeItem(at: directory)
    }
    let store = SettingsStore(directory: directory)
    let good = customSettings()
    try await store.save(good)

    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555], ofItemAtPath: directory.path)
    let stream = store.updates()
    var iterator = stream.makeAsyncIterator()
    var rejected = Settings.defaults
    rejected.oldFileThresholdDays = 1
    await #expect(throws: (any Error).self) {
      try await store.save(rejected)
    }

    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: directory.path)
    #expect(await SettingsStore(directory: directory).load() == good)

    var third = Settings.defaults
    third.largeFileThresholdBytes = 42
    try await store.save(third)
    #expect(await iterator.next() == third, "a failed save must not reach the updates stream")
  }
}
