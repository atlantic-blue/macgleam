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
  /// of "/Library/Ap", and no path is a descendant of itself. Both values are
  /// normalised, so a component boundary is exactly a "/" in the string.
  public func isDescendant(of ancestor: AbsolutePath) -> Bool {
    guard ancestor.value != "/" else { return value != "/" }
    let own = value.utf8
    let ancestorBytes = ancestor.value.utf8
    guard own.count > ancestorBytes.count else { return false }
    var index = own.startIndex
    for byte in ancestorBytes {
      guard own[index] == byte else { return false }
      own.formIndex(after: &index)
    }
    return own[index] == UInt8(ascii: "/")
  }

  /// Whether this path sits directly inside `folder`, with nothing between
  /// them. It answers without building the parent path, because a walk asks
  /// this of every file it sees, and a path built per file costs more than
  /// reading the file did.
  public func isChild(of folder: AbsolutePath) -> Bool {
    guard isDescendant(of: folder) else { return false }
    let consumed = folder.value == "/" ? 1 : folder.value.utf8.count + 1
    return !value.utf8.dropFirst(consumed).contains(UInt8(ascii: "/"))
  }

  public func isAncestor(of descendant: AbsolutePath) -> Bool {
    descendant.isDescendant(of: self)
  }

  /// This path's ancestor directories, nearest first, down to and including
  /// `root`. Empty when the path is not a descendant of `root`.
  public func ancestors(downTo root: AbsolutePath) -> [AbsolutePath] {
    guard isDescendant(of: root) else { return [] }
    let rootLength = root.value.utf8.count
    var result: [AbsolutePath] = []
    var current = value
    while current.utf8.count > rootLength {
      guard let slash = current.lastIndex(of: "/") else { break }
      current = slash == current.startIndex ? "/" : String(current[..<slash])
      result.append(AbsolutePath(normalised: current))
    }
    return result
  }

  public var lastComponent: String {
    components.last ?? "/"
  }

  public var components: [String] {
    value.split(separator: "/").map(String.init)
  }

  /// Wraps a value the caller already knows is normalised. Only for values
  /// derived from another path's own value, such as a prefix of it.
  private init(normalised value: String) {
    self.value = value
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
