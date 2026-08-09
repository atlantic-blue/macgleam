import Foundation
import GleamCore
import os

/// The on disk settings store. One JSON file in the given directory, loaded
/// with validation and saved atomically.
///
/// A missing or corrupt file loads as `Settings.defaults`, never a crash and
/// never a permanent deletion mode the user did not choose: any decoding
/// doubt falls back to defaults, whose deletion mode is trash. A failed save
/// throws and leaves the previous file intact. `updates()` streams the new
/// value to every subscriber after each successful save, in save order.
public struct SettingsStore: SettingsStoring {
  private let directory: URL
  private let fileURL: URL
  private let subscribers: OSAllocatedUnfairLock<[UUID: AsyncStream<Settings>.Continuation]>

  public init(directory: URL) {
    self.directory = directory
    self.fileURL = directory.appendingPathComponent("settings.json", isDirectory: false)
    self.subscribers = OSAllocatedUnfairLock(initialState: [:])
  }

  public func load() async -> Settings {
    guard let data = try? Data(contentsOf: fileURL) else { return .defaults }
    guard let decoded = try? JSONDecoder().decode(Settings.self, from: data) else {
      return .defaults
    }
    return decoded
  }

  public func save(_ settings: Settings) async throws {
    let data = try JSONEncoder().encode(settings)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    try data.write(to: fileURL, options: .atomic)
    let continuations = subscribers.withLock { Array($0.values) }
    for continuation in continuations {
      continuation.yield(settings)
    }
  }

  public func updates() -> AsyncStream<Settings> {
    AsyncStream { continuation in
      let subscriberID = UUID()
      subscribers.withLock { $0[subscriberID] = continuation }
      let subscribers = self.subscribers
      continuation.onTermination = { _ in
        subscribers.withLock { $0[subscriberID] = nil }
      }
    }
  }
}
