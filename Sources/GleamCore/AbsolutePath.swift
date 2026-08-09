import Foundation

/// A normalised absolute file system path. The only path representation that
/// crosses any boundary in MacGleam, including the XPC boundary to the helper.
public struct AbsolutePath: Codable, Sendable, Hashable, Comparable {
  public let value: String

  /// Returns nil for any string that is not already a normalised absolute
  /// path: relative strings, trailing slashes, empty components, "." or ".."
  /// components.
  public init?(validating value: String) {
    guard Self.isNormalisedAbsolute(value) else { return nil }
    self.value = value
  }

  /// Total constructor. Resolves trailing slashes, empty and dot components,
  /// and treats relative strings as rooted at "/". ".." above the root stays
  /// at the root.
  public init(normalising value: String) {
    self.value = Self.normalise(value)
  }

  /// Componentwise strict prefix check. "/Library/App" is not a descendant
  /// of "/Library/Ap", and no path is a descendant of itself.
  public func isDescendant(of ancestor: AbsolutePath) -> Bool {
    let own = components
    let ancestorComponents = ancestor.components
    guard own.count > ancestorComponents.count else { return false }
    return zip(ancestorComponents, own).allSatisfy(==)
  }

  public func isAncestor(of descendant: AbsolutePath) -> Bool {
    descendant.isDescendant(of: self)
  }

  public var lastComponent: String {
    components.last ?? "/"
  }

  var components: [String] {
    value.split(separator: "/").map(String.init)
  }

  var parent: AbsolutePath? {
    let own = components
    guard !own.isEmpty else { return nil }
    return AbsolutePath(normalising: "/" + own.dropLast().joined(separator: "/"))
  }

  public static func < (left: AbsolutePath, right: AbsolutePath) -> Bool {
    left.value < right.value
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    guard Self.isNormalisedAbsolute(raw) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Not a normalised absolute path: \(raw)"
      )
    }
    self.value = raw
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }

  private static func isNormalisedAbsolute(_ value: String) -> Bool {
    if value == "/" { return true }
    guard value.hasPrefix("/"), !value.hasSuffix("/") else { return false }
    let rawComponents = value.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
    return rawComponents.allSatisfy { $0.isEmpty == false && $0 != "." && $0 != ".." }
  }

  private static func normalise(_ value: String) -> String {
    var resolved: [String] = []
    for component in value.split(separator: "/") {
      switch component {
      case ".":
        continue
      case "..":
        if !resolved.isEmpty { resolved.removeLast() }
      default:
        resolved.append(String(component))
      }
    }
    guard !resolved.isEmpty else { return "/" }
    return "/" + resolved.joined(separator: "/")
  }
}
