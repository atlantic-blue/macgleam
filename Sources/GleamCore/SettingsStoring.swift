/// Loads and persists Settings. Loaded once at startup, validated on load: a
/// corrupt or missing store yields `Settings.defaults`, never a crash, and
/// never a permanent deletion mode the user did not choose. Saves are atomic,
/// and `updates` emits the new value after each successful save so the menu
/// bar scene and open modules react without polling.
public protocol SettingsStoring: Sendable {
  func load() async -> Settings
  func save(_ settings: Settings) async throws
  func updates() -> AsyncStream<Settings>
}
