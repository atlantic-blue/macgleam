import Foundation

public struct LeftoverPath: Codable, Sendable, Equatable {
  public enum Kind: String, Codable, Sendable, Equatable {
    case preferences, cache, container, applicationSupport, launchAgent, launchDaemon, log
  }

  public let path: AbsolutePath
  public let kind: Kind
  public let byteSize: UInt64

  public init(path: AbsolutePath, kind: Kind, byteSize: UInt64) {
    self.path = path
    self.kind = kind
    self.byteSize = byteSize
  }
}

/// One installed application and everything MacGleam knows belongs to it.
public struct AppInventoryEntry: Codable, Sendable, Equatable, Identifiable {
  public var id: String { bundleID }

  public let bundleID: String
  public let name: String
  public let version: String
  public let installLocation: AbsolutePath
  public let leftoverPaths: [LeftoverPath]

  public init(
    bundleID: String,
    name: String,
    version: String,
    installLocation: AbsolutePath,
    leftoverPaths: [LeftoverPath]
  ) {
    self.bundleID = bundleID
    self.name = name
    self.version = version
    self.installLocation = installLocation
    self.leftoverPaths = leftoverPaths
  }
}
