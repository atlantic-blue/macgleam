import Foundation
import GleamCore

/// Where the traces of using this Mac are kept, and what each of them is.
///
/// The table is written out rather than derived, because every entry is a
/// claim about what a person loses when it goes. A browser's history is the
/// list of what they read; its cookies are the sessions they are signed in to;
/// its site data is what pages stored locally. Those are three different
/// losses, so they are three findings a person ticks separately rather than
/// one row called Privacy.
///
/// A location is recognised by path components, the same way a leftover is,
/// and the browser's name comes out of the path rather than being guessed at.
enum PrivacyLocations {

  enum Kind: Sendable, Equatable {
    case browserHistory
    case browserCookies
    case browserSiteData
    case recentItemsList
    case wifiNetworkHistory
  }

  /// One recognised trace: what it is, whose it is, and the path that holds
  /// it. Paths deeper than the root resolve to the root, so a directory of
  /// site data contributes its bytes without its every file becoming a row.
  struct Target: Hashable {
    let root: AbsolutePath
    let kind: Kind
    /// The browser this belongs to, and nil for the traces macOS keeps
    /// itself.
    let browser: String?
  }

  /// The traces macOS itself keeps, and where each of them lives. Both are
  /// lists of where somebody has been: the files they opened, and the networks
  /// this Mac has joined. The first is kept per person and the second for the
  /// whole machine, which is why the table carries the anchor rather than
  /// assuming one.
  private static let userTraces: [(components: [String], kind: Kind)] = [
    (["Application Support", "com.apple.sharedfilelist"], .recentItemsList)
  ]

  private static let machineTraces: [(components: [String], kind: Kind)] = [
    (["Library", "Preferences", "com.apple.wifi.known-networks.plist"], .wifiNetworkHistory)
  ]

  /// A browser's profile directory, and what each file or folder inside it
  /// is. The profile is what a person means by "my browser": a second profile
  /// is a second set of traces and appears as its own rows.
  private struct BrowserProfile {
    let browser: String
    /// The path from the user's Library to the directory holding profiles.
    let libraryPath: [String]
    /// How deep the profile directory sits under `libraryPath`. Zero means
    /// the browser keeps one profile and no directory for it.
    let profileDepth: Int
    let entries: [String: Kind]
  }

  private static let chromiumEntries: [String: Kind] = [
    "History": .browserHistory,
    "Cookies": .browserCookies,
    "Local Storage": .browserSiteData,
    "Session Storage": .browserSiteData,
    "IndexedDB": .browserSiteData,
  ]

  private static let profiles: [BrowserProfile] = [
    BrowserProfile(
      browser: "Safari",
      libraryPath: ["Safari"],
      profileDepth: 0,
      entries: [
        "History.db": .browserHistory,
        "History.db-wal": .browserHistory,
        "LocalStorage": .browserSiteData,
        "Databases": .browserSiteData,
      ]
    ),
    BrowserProfile(
      browser: "Chrome",
      libraryPath: ["Application Support", "Google", "Chrome"],
      profileDepth: 1,
      entries: chromiumEntries
    ),
    BrowserProfile(
      browser: "Edge",
      libraryPath: ["Application Support", "Microsoft Edge"],
      profileDepth: 1,
      entries: chromiumEntries
    ),
    BrowserProfile(
      browser: "Brave",
      libraryPath: ["Application Support", "BraveSoftware", "Brave-Browser"],
      profileDepth: 1,
      entries: chromiumEntries
    ),
    BrowserProfile(
      browser: "Firefox",
      libraryPath: ["Application Support", "Firefox", "Profiles"],
      profileDepth: 1,
      entries: [
        "places.sqlite": .browserHistory,
        "places.sqlite-wal": .browserHistory,
        "cookies.sqlite": .browserCookies,
        "cookies.sqlite-wal": .browserCookies,
        "storage": .browserSiteData,
        "webappsstore.sqlite": .browserSiteData,
      ]
    ),
  ]

  /// Safari keeps its cookies outside its own folder, which is why the table
  /// carries a location rather than a rule about where a browser's files are.
  private static let safariCookies = ["Library", "Cookies"]

  /// The trace a path lies at or inside, or nil when it is not one.
  static func target(containing components: [String]) -> Target? {
    if let system = systemTarget(components) { return system }
    if let cookies = safariCookiesTarget(components) { return cookies }
    return browserTarget(components)
  }

  private static func systemTarget(_ components: [String]) -> Target? {
    for trace in machineTraces where isPrefix(trace.components, of: components) {
      return Target(
        root: path(components.prefix(trace.components.count)), kind: trace.kind, browser: nil)
    }
    guard let library = userLibrary(components) else { return nil }
    let insideLibrary = Array(components.dropFirst(library.depth))
    for trace in userTraces where isPrefix(trace.components, of: insideLibrary) {
      return Target(
        root: path(components.prefix(library.depth + trace.components.count)),
        kind: trace.kind,
        browser: nil)
    }
    return nil
  }

  /// `/Users/<someone>/Library/Cookies`, where Safari's cookies live.
  private static func safariCookiesTarget(_ components: [String]) -> Target? {
    guard let library = userLibrary(components),
      isPrefix(safariCookies, of: Array(components.dropFirst(2)))
    else { return nil }
    return Target(
      root: path(components.prefix(library.depth + safariCookies.count - 1)),
      kind: .browserCookies,
      browser: "Safari")
  }

  private static func browserTarget(_ components: [String]) -> Target? {
    guard let library = userLibrary(components) else { return nil }
    let insideLibrary = Array(components.dropFirst(library.depth))
    for profile in profiles {
      guard isPrefix(profile.libraryPath, of: insideLibrary) else { continue }
      let afterBrowser = Array(insideLibrary.dropFirst(profile.libraryPath.count))
      guard afterBrowser.count > profile.profileDepth else { continue }
      let entryName = afterBrowser[profile.profileDepth]
      guard let kind = profile.entries[entryName] else { continue }
      let depth = library.depth + profile.libraryPath.count + profile.profileDepth + 1
      return Target(
        root: path(components.prefix(depth)), kind: kind, browser: profile.browser)
    }
    return nil
  }

  /// `/Users/<someone>/Library`, as a component count, or nil for a path
  /// outside a user's Library.
  private static func userLibrary(_ components: [String]) -> (depth: Int, home: String)? {
    guard components.count >= 3, components[0] == "Users", components[2] == "Library" else {
      return nil
    }
    return (3, components[1])
  }

  private static func isPrefix(_ prefix: [String], of components: [String]) -> Bool {
    guard components.count >= prefix.count else { return false }
    return Array(components.prefix(prefix.count)) == prefix
  }

  private static func path(_ components: ArraySlice<String>) -> AbsolutePath {
    AbsolutePath(normalising: "/" + components.joined(separator: "/"))
  }

  /// What each kind is called in a finding, and what a person loses with it.
  static func category(of kind: Kind, browser: String?) -> FindingCategory {
    switch kind {
    case .browserHistory: return .browserHistory(browser: browser ?? "")
    case .browserCookies: return .browserCookies(browser: browser ?? "")
    case .browserSiteData: return .browserSiteData(browser: browser ?? "")
    case .recentItemsList: return .recentItemsList
    case .wifiNetworkHistory: return .wifiNetworkHistory
    }
  }

  /// The sentence a row carries. It names exactly what goes and exactly what
  /// stays, because the whole difference between clearing cookies and
  /// clearing history is what a person is signed out of afterwards.
  static func explanation(of kind: Kind, browser: String?) -> String {
    let name = browser ?? "this Mac"
    switch kind {
    case .browserHistory:
      return
        "The list of pages visited in \(name). Bookmarks, passwords and open tabs are not "
        + "touched."
    case .browserCookies:
      return
        "The cookies \(name) is holding. Clearing them signs out of sites that remembered "
        + "this Mac; nothing saved in a password manager is touched."
    case .browserSiteData:
      return
        "What sites stored locally in \(name): local storage, databases and offline caches. "
        + "Signed in sessions and saved passwords are not touched; some sites load more "
        + "slowly the first time afterwards."
    case .recentItemsList:
      return
        "The lists of recently opened files and applications macOS keeps. The files "
        + "themselves are not touched."
    case .wifiNetworkHistory:
      return
        "The record of wireless networks this Mac has joined. Saved passwords stay in the "
        + "keychain, so a network you rejoin still connects."
    }
  }
}
