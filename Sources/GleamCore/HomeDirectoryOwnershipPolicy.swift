import Foundation

/// The ownership policy both processes decide with.
///
/// It lives here rather than in either process because C16's guarantee is that
/// the answer is the same on both sides: the app routes a system domain path
/// to the helper, and the helper refuses a user domain path as work the app
/// could do itself. Two copies of this rule that drifted would open exactly
/// the gap the refusal exists to close.
///
/// The environment is the deciding user, not whoever is running the code. In
/// the app that is the user; in the daemon, which runs as root, it is the user
/// whose app is connected, so a path in that user's home reads as user domain
/// in the root process too.
public struct HomeDirectoryOwnershipPolicy: PathOwnershipPolicy {
  public init() {}

  public func ownership(of path: AbsolutePath, environment: OwnershipEnvironment)
    -> PathOwnership
  {
    let home = environment.currentUserHome
    guard path == home || path.isDescendant(of: home) else { return .systemDomain }
    return .userDomain
  }
}
