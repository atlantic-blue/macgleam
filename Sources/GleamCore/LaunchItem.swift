import Foundation

/// One login or background item: an SMAppService registration or a legacy
/// launch agent or daemon, with the app it belongs to where that app can be
/// resolved.
///
/// `path` is where the registration lives, and it exists so a row can be
/// revealed in Finder. It never travels as a finding entry: a `PathEntry` is a
/// removal target and a byte source, and a registration is neither, so a
/// launch item finding carries no entries (C5).
///
/// `scope` is the fact that decides which side of the privileged boundary a
/// change lands on. It is read from the item, which comes from the inventory,
/// never from what a caller claims.
public struct LaunchItem: Codable, Sendable, Equatable, Identifiable {
  public enum Kind: String, Codable, Sendable, Equatable, Hashable {
    case appService
    case legacyLaunchAgent
    case legacyLaunchDaemon
  }

  /// Hashable because `FindingCategory` is Hashable and carries a scope (C5).
  public enum Scope: String, Codable, Sendable, Equatable, Hashable {
    case user, system
  }

  public var id: LaunchItemID { identifier }
  public let identifier: LaunchItemID
  public let label: String
  public let kind: Kind
  public let scope: Scope
  public let owningAppBundleID: String?
  public let owningAppName: String?
  public let path: AbsolutePath
  public let isEnabled: Bool

  public init(
    identifier: LaunchItemID,
    label: String,
    kind: Kind,
    scope: Scope,
    owningAppBundleID: String?,
    owningAppName: String?,
    path: AbsolutePath,
    isEnabled: Bool
  ) {
    self.identifier = identifier
    self.label = label
    self.kind = kind
    self.scope = scope
    self.owningAppBundleID = owningAppBundleID
    self.owningAppName = owningAppName
    self.path = path
    self.isEnabled = isEnabled
  }
}
