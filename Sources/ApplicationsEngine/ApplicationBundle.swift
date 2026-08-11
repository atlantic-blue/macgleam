import Foundation
import GleamCore

/// Where applications are installed, and what a bundle says about itself.
enum ApplicationBundle {
  /// What an application claims in its own Info.plist. Only the identifier is
  /// required: it is what every association is decided against, so a bundle
  /// that will not say who it is has nothing to attribute files to.
  struct Identity: Sendable, Equatable {
    let bundleID: String
    let name: String
    let version: String
  }

  private static let bundleExtension = "app"
  private static let infoPlistSuffix = "/Contents/Info.plist"

  /// An Info.plist is a few kilobytes. The ceiling is here so a file that
  /// claims to be one, and is a gigabyte of something else, is read as far as
  /// this and no further.
  private static let maximumInfoPlistBytes: UInt64 = 1 << 20

  /// `/Applications/<someone>.app` and
  /// `/Users/<someone>/Applications/<someone>.app`, as component counts.
  private enum Depth {
    static let systemApplication = 2
    static let userApplication = 4
  }

  /// The application bundle a path lies at or inside, or nil when it sits
  /// outside every install location. A path deeper than the bundle resolves to
  /// the bundle, which is what lets a walk total a bundle's subtree without
  /// treating its contents as bundles of their own.
  static func root(containing components: [String]) -> AbsolutePath? {
    if components.count >= Depth.systemApplication,
      components[0] == "Applications",
      isBundleName(components[Depth.systemApplication - 1])
    {
      return path(components.prefix(Depth.systemApplication))
    }
    guard components.count >= Depth.userApplication,
      components[0] == "Users",
      components[2] == "Applications",
      isBundleName(components[Depth.userApplication - 1])
    else { return nil }
    return path(components.prefix(Depth.userApplication))
  }

  /// Reads the bundle's own account of itself, or nil for a bundle whose
  /// identity cannot be read: no Info.plist, an unreadable one, one that is
  /// not a property list, or one that names no identifier. Nil is the answer
  /// here rather than a thrown error because such a bundle is skipped by
  /// contract, and one unreadable application on a disk must never sink the
  /// scan of every other.
  static func identity(
    atRoot root: AbsolutePath,
    fileSystem: any FileSystemReading
  ) async -> Identity? {
    let infoPlist = AbsolutePath(normalising: root.value + infoPlistSuffix)
    guard
      let data = try? await fileSystem.readData(at: infoPlist, maxBytes: maximumInfoPlistBytes),
      let contents = try? PropertyListSerialization.propertyList(from: data, format: nil),
      let fields = contents as? [String: Any],
      let bundleID = fields["CFBundleIdentifier"] as? String,
      !bundleID.isEmpty
    else { return nil }
    return Identity(
      bundleID: bundleID,
      name: fields["CFBundleName"] as? String ?? displayName(ofBundleAt: root),
      version: fields["CFBundleShortVersionString"] as? String ?? "")
  }

  private static func isBundleName(_ name: String) -> Bool {
    name.hasSuffix(".\(bundleExtension)") && name.count > bundleExtension.count + 1
  }

  private static func displayName(ofBundleAt root: AbsolutePath) -> String {
    String(root.lastComponent.dropLast(bundleExtension.count + 1))
  }

  private static func path(_ components: ArraySlice<String>) -> AbsolutePath {
    AbsolutePath(normalising: "/" + components.joined(separator: "/"))
  }
}
