import Foundation
import GleamCore

/// The helper's own gate. Runs inside GleamHelper before any request is acted
/// on: the security model made executable.
///
/// One policy instance guards one connection. The agreed version is
/// connection state, created with the connection and dead with it, so nothing
/// another client did can change what this connection may do.
public protocol HelperPolicy: Sendable {
  func admit(_ request: HelperRequest, from client: ClientIdentity) -> HelperAdmission
}

public enum HelperAdmission: Sendable, Equatable {
  case admitted
  case refused(HelperRefusal)
}

/// The identity a connecting client presents, as the helper reads it from the
/// connection's audit token.
public struct ClientIdentity: Sendable, Equatable {
  public let teamIdentifier: String
  public let bundleIdentifier: String
  public let codeSigningValid: Bool

  public init(teamIdentifier: String, bundleIdentifier: String, codeSigningValid: Bool) {
    self.teamIdentifier = teamIdentifier
    self.bundleIdentifier = bundleIdentifier
    self.codeSigningValid = codeSigningValid
  }
}

/// The one client identity the helper serves. Compiled into the helper rather
/// than read from a file, so nothing on disk can widen it.
public struct ExpectedClientIdentity: Sendable, Equatable {
  public let teamIdentifier: String
  public let bundleIdentifier: String

  public init(teamIdentifier: String, bundleIdentifier: String) {
    self.teamIdentifier = teamIdentifier
    self.bundleIdentifier = bundleIdentifier
  }

  /// MacGleam.app itself.
  ///
  /// The team identifier is a launch milestone dependency: it is the team of
  /// the Developer ID certificate the app and the helper are signed with, and
  /// that certificate does not exist yet (ROADMAP M7, s7b). Until it does,
  /// this carries the real bundle identifier and the stand in below.
  ///
  /// This is the one value in the codebase that fails silently when it is
  /// wrong. A placeholder compiles, passes every identity test and still
  /// admits any signed client that copies the bundle identifier, which turns
  /// client verification into a formality while the suite stays green. The
  /// release pipeline fails the build while the team identifier still reads
  /// DEVELOPERIDPENDING, so it cannot ship by being forgotten, only by being
  /// overruled.
  public static let macGleamApp = ExpectedClientIdentity(
    teamIdentifier: "DEVELOPERIDPENDING",
    bundleIdentifier: "com.atlanticblue.macgleam"
  )
}

/// A version disagreement recorded for one connection: helper side
/// diagnostics, and the pair of numbers the handshake refusal is built from.
/// The two are never equal.
public struct HelperVersionMismatch: Sendable, Equatable {
  public let helperContractVersion: UInt16
  public let clientContractVersion: UInt16

  public init(helperContractVersion: UInt16, clientContractVersion: UInt16) {
    self.helperContractVersion = helperContractVersion
    self.clientContractVersion = clientContractVersion
  }
}

/// How the helper turns a launch item identifier into the file it would
/// mutate. A request names an item, never a path, so the helper resolves the
/// item itself before it can place that file in a domain.
public protocol HelperLaunchItemLocating: Sendable {
  func location(of item: LaunchItemID) -> AbsolutePath?
}
