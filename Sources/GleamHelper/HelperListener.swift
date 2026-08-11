import Foundation
import GleamCore
import GleamHelperCore
import os

/// Accepts connections, and decides on identity before anything else.
///
/// Identity is enforced by the system rather than by reading claims off the
/// wire: the connection carries a code signing requirement naming the exact
/// bundle identifier and Developer ID team of MacGleam.app, and XPC (inter
/// process communication) invalidates any connection whose messages do not
/// satisfy it. A request that reaches the handler has therefore already been
/// signature checked, which is why the handler is given a verified identity
/// rather than one the client asserted.
///
/// Each connection gets its own policy instance, because the agreed contract
/// version is connection state (C31): nothing another client did can change
/// what this connection may do.
final class HelperListener: NSObject, NSXPCListenerDelegate {
  private let expectedClient: ExpectedClientIdentity
  private let denylist: Denylist
  private let log = Logger(subsystem: GleamHelperService.label, category: "connections")

  init(expectedClient: ExpectedClientIdentity, denylist: Denylist) {
    self.expectedClient = expectedClient
    self.denylist = denylist
  }

  func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    guard let environment = Self.environment(ofUser: connection.effectiveUserIdentifier) else {
      log.error("A connection arrived from an account with no home directory and was dropped.")
      return false
    }
    connection.exportedInterface = NSXPCInterface(with: GleamHelperXPC.self)
    connection.exportedObject = HelperMessageHandler(
      policy: policy(for: environment),
      client: verifiedIdentity,
      removal: HelperRemoval(fileSystem: DiskFileSystem())
    )
    connection.setCodeSigningRequirement(codeSigningRequirement)
    connection.resume()
    return true
  }

  private func policy(for environment: OwnershipEnvironment) -> HelperConnectionPolicy {
    HelperConnectionPolicy(
      expectedClient: expectedClient,
      contractVersion: HelperContract.version,
      denylist: denylist,
      ownership: HomeDirectoryOwnershipPolicy(),
      environment: environment,
      launchItems: HelperLaunchItemLocator()
    )
  }

  /// The identity a message that survived the requirement above must have had.
  private var verifiedIdentity: ClientIdentity {
    ClientIdentity(
      teamIdentifier: expectedClient.teamIdentifier,
      bundleIdentifier: expectedClient.bundleIdentifier,
      codeSigningValid: true
    )
  }

  /// The one client this daemon serves, in the code signing requirement
  /// language. The team is part of it and stays part of it: a requirement on
  /// the bundle identifier alone would admit any signed application that
  /// copied the identifier, which is the formality C31 warns against.
  private var codeSigningRequirement: String {
    "identifier \"\(expectedClient.bundleIdentifier)\" and anchor apple generic "
      + "and certificate leaf[subject.OU] = \"\(expectedClient.teamIdentifier)\""
  }

  /// The domain decision is made about the connected user, never about root.
  /// Root's own home would place every real person's files outside their home
  /// and so in the system domain, and the helper would then do work the user
  /// process should have done itself.
  private static func environment(ofUser uid: uid_t) -> OwnershipEnvironment? {
    guard let record = getpwuid(uid), let directory = record.pointee.pw_dir else { return nil }
    let home = String(cString: directory)
    guard !home.isEmpty else { return nil }
    return OwnershipEnvironment(
      currentUserHome: AbsolutePath(normalising: home),
      currentUserID: UInt32(uid)
    )
  }
}
