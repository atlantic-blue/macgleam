import Foundation

/// Decides which process may touch a path. Shared by the app executor and
/// GleamHelperCore so app and helper cannot drift.
///
/// `userDomain` means the current user can mutate the path without privilege
/// escalation: the user's home, the user's trash directories, user owned
/// temporary locations, and user writable locations on external volumes.
/// Everything else is `systemDomain` and routes to the helper. The decision
/// is a pure function of the path and the environment snapshot: same inputs,
/// same answer, in both processes.
public protocol PathOwnershipPolicy: Sendable {
  func ownership(of path: AbsolutePath, environment: OwnershipEnvironment) -> PathOwnership
}

public enum PathOwnership: String, Codable, Sendable, Equatable {
  case userDomain
  case systemDomain
}

/// The snapshot an ownership decision is made against.
public struct OwnershipEnvironment: Codable, Sendable, Equatable {
  public let currentUserHome: AbsolutePath
  public let currentUserID: UInt32

  public init(currentUserHome: AbsolutePath, currentUserID: UInt32) {
    self.currentUserHome = currentUserHome
    self.currentUserID = currentUserID
  }

  /// The environment of the running process.
  public static var current: OwnershipEnvironment {
    OwnershipEnvironment(
      currentUserHome: AbsolutePath(normalising: NSHomeDirectory()),
      currentUserID: getuid())
  }
}
