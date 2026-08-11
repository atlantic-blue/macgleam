import Foundation
import GleamCore

/// Where a leftover may live, what a name there means, and which application
/// a name belongs to.
///
/// The rule is conservative in one direction on purpose. A false negative is a
/// leftover nobody swept; a false positive is a stranger's file deleted by an
/// uninstall, and no amount of reclaimed space pays for one of those. So a
/// candidate is an immediate child of a recognised location, its identity is
/// its own name with one recognised extension removed, and it is attributed
/// only when that identity equals an installed application's bundle identifier
/// exactly. A prefix under any separator, a substring, a name that continues
/// past an identifier, a nested directory and a file whose owner is not
/// installed all belong to nothing.
///
/// Group Containers is absent from the recognised locations rather than
/// filtered out of them: a group container is shared between applications by
/// design, so there is no single owner to attribute one to.
enum LeftoverAssociation {
  enum Domain {
    case user
    case system
  }

  /// One candidate leftover: the immediate child of a recognised location that
  /// some path lives at or inside.
  struct Candidate: Hashable {
    let root: AbsolutePath
    let kind: LeftoverPath.Kind
    let domain: Domain
  }

  /// The system domain location, named the way the degraded banner names it.
  static let systemDomainLocation = "/Library/LaunchDaemons"

  /// The recognised locations inside a user's Library, by folder name.
  private static let userLibraryKinds: [String: LeftoverPath.Kind] = [
    "Preferences": .preferences,
    "Caches": .cache,
    "Containers": .container,
    "Application Support": .applicationSupport,
    "LaunchAgents": .launchAgent,
    "Logs": .log,
  ]

  /// `/Users/<someone>/Library/<location>/<candidate>` and
  /// `/Library/LaunchDaemons/<candidate>`, as component counts.
  private enum Depth {
    static let userLibraryCandidate = 5
    static let systemLaunchDaemonCandidate = 3
  }

  /// The extensions a leftover name may carry over its identity. One is
  /// removed, never two, so `com.example.mail.log` is `com.example.mail` and
  /// `com.example.mail.plist.plist` is `com.example.mail.plist`.
  private static let recognisedExtensions = ["plist", "log"]

  /// The candidate a path lies at or inside, or nil when it sits nowhere a
  /// leftover is recognised. A path deeper than the immediate child still
  /// resolves to that child, which is what makes a nested directory contribute
  /// its bytes to its candidate without ever becoming a candidate itself.
  static func candidate(containing components: [String]) -> Candidate? {
    if let candidate = userLibraryCandidate(components) { return candidate }
    return systemLaunchDaemonCandidate(components)
  }

  /// A candidate's identity: its name with one recognised extension removed.
  static func identity(ofCandidateNamed name: String) -> String {
    for fileExtension in recognisedExtensions where name.hasSuffix(".\(fileExtension)") {
      return String(name.dropLast(fileExtension.count + 1))
    }
    return name
  }

  /// The application a candidate belongs to: the one whose bundle identifier
  /// is exactly the candidate's identity, and nothing otherwise.
  static func owner(of candidate: Candidate, installedBundleIDs: Set<String>) -> String? {
    let identity = identity(ofCandidateNamed: candidate.root.lastComponent)
    guard installedBundleIDs.contains(identity) else { return nil }
    return identity
  }

  private static func userLibraryCandidate(_ components: [String]) -> Candidate? {
    guard components.count >= Depth.userLibraryCandidate,
      components[0] == "Users",
      components[2] == "Library",
      let kind = userLibraryKinds[components[3]]
    else { return nil }
    return Candidate(
      root: path(components.prefix(Depth.userLibraryCandidate)), kind: kind, domain: .user)
  }

  private static func systemLaunchDaemonCandidate(_ components: [String]) -> Candidate? {
    guard components.count >= Depth.systemLaunchDaemonCandidate,
      components[0] == "Library",
      components[1] == "LaunchDaemons"
    else { return nil }
    return Candidate(
      root: path(components.prefix(Depth.systemLaunchDaemonCandidate)),
      kind: .launchDaemon,
      domain: .system)
  }

  private static func path(_ components: ArraySlice<String>) -> AbsolutePath {
    AbsolutePath(normalising: "/" + components.joined(separator: "/"))
  }
}
