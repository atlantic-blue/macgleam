import Foundation
import GleamHelperCore
import ServiceManagement

/// The real privileged service, behind the protocol the coordinator is tested
/// against. Everything here is a pass through, deliberately: this is the one
/// piece of the registration story no automated test can reach, so it is kept
/// small enough to read and hold nothing worth testing.
///
/// A fresh `SMAppService` is made for each call rather than held, because the
/// status is a question about the system right now. An instance kept in a
/// property would answer about the moment it was made, and an approval that
/// lands while the app is running would never be seen.
public struct SystemHelperService: HelperServiceRegistering {
  private let propertyListName: String

  public init(propertyListName: String = GleamHelperService.propertyListName) {
    self.propertyListName = propertyListName
  }

  public var status: HelperServiceStatus {
    Self.status(of: SMAppService.daemon(plistName: propertyListName).status)
  }

  /// Throws exactly what `SMAppService` throws, including the
  /// `SMAppServiceErrorDomain` code 1 of a first registration. What a throw
  /// means is the coordinator's job, not this adapter's, and it decides that
  /// from the status the attempt leaves behind; swallowing the throw here would
  /// hide a real registration failure from it.
  public func register() throws {
    try SMAppService.daemon(plistName: propertyListName).register()
  }

  /// Not part of the protocol, because nothing in the app's normal life
  /// unregisters the helper. It exists so a registration made while checking
  /// the real path can be undone.
  public func unregister() throws {
    try SMAppService.daemon(plistName: propertyListName).unregister()
  }

  private static func status(of status: SMAppService.Status) -> HelperServiceStatus {
    switch status {
    case .enabled:
      return .enabled
    case .requiresApproval:
      return .requiresApproval
    case .notFound:
      return .notFound
    case .notRegistered:
      return .notRegistered
    @unknown default:
      return .notFound
    }
  }
}
