import Foundation

/// A restricted glob over absolute paths. Supports literal components, a
/// single component wildcard "*" and a trailing subtree wildcard "**".
/// Deliberately not a regular expression: patterns are reviewable by a human.
public struct PathPattern: Codable, Sendable, Equatable {
  public let pattern: String
  /// The literal components the pattern is compared against, split once at
  /// construction because matching sits on the per file hot path. A trailing
  /// subtree wildcard is recorded as a flag rather than kept as a component.
  private let components: [String]
  private let isSubtree: Bool

  public init(pattern: String) {
    var components = pattern.split(separator: "/").map(String.init)
    let isSubtree = components.last == "**"
    if isSubtree { components.removeLast() }
    self.pattern = pattern
    self.components = components
    self.isSubtree = isSubtree
  }

  /// Componentwise match. "*" matches exactly one component. A trailing "**"
  /// matches any descendant of the prefix, respecting component boundaries.
  public func matches(_ path: AbsolutePath) -> Bool {
    matches(pathComponents: path.components)
  }

  public func matches(pathComponents: [String]) -> Bool {
    if isSubtree {
      guard pathComponents.count > components.count else { return false }
    } else {
      guard pathComponents.count == components.count else { return false }
    }
    return prefixMatches(pathComponents)
  }

  /// True when the pattern matches the path or any ancestor directory of it.
  /// A path's ancestors are its own component prefixes, so this answers the
  /// whole ancestor chain in one componentwise pass with no path building.
  public func matchesPathOrAncestor(of pathComponents: [String]) -> Bool {
    if isSubtree {
      guard pathComponents.count > components.count else { return false }
    } else {
      guard pathComponents.count >= components.count else { return false }
    }
    return prefixMatches(pathComponents)
  }

  private func prefixMatches(_ pathComponents: [String]) -> Bool {
    for index in components.indices where components[index] != "*" {
      guard components[index] == pathComponents[index] else { return false }
    }
    return true
  }

  public static func == (left: PathPattern, right: PathPattern) -> Bool {
    left.pattern == right.pattern
  }

  private enum CodingKeys: String, CodingKey {
    case pattern
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(pattern: try container.decode(String.self, forKey: .pattern))
  }
}

/// The list of paths nothing in MacGleam may ever remove. Pure, total and
/// fast enough to sit on the per operation hot path.
public struct Denylist: Codable, Sendable, Equatable {
  public let patterns: [PathPattern]

  public init(patterns: [PathPattern]) {
    self.patterns = patterns
  }

  /// Blocks a path when the path matches a pattern or is a descendant of a
  /// blocked directory.
  public func blocks(_ path: AbsolutePath) -> Bool {
    blocks(pathComponents: path.components)
  }

  /// The same answer for a path already split into components, so a caller
  /// scanning many rules against one path splits it once.
  public func blocks(pathComponents: [String]) -> Bool {
    patterns.contains { $0.matchesPathOrAncestor(of: pathComponents) }
  }
}

public struct RuleCatalogVersion: Codable, Sendable, Equatable, Comparable {
  public let value: UInt32

  public init(value: UInt32) {
    self.value = value
  }

  public static func < (left: RuleCatalogVersion, right: RuleCatalogVersion) -> Bool {
    left.value < right.value
  }
}

public struct CleanupRule: Codable, Sendable, Equatable {
  public let identifier: String
  public let category: FindingCategory
  public let pathPatterns: [PathPattern]
  public let risk: RiskLevel
  /// Only honoured when risk is safe.
  public let preselectable: Bool
  public let explanation: String

  public init(
    identifier: String,
    category: FindingCategory,
    pathPatterns: [PathPattern],
    risk: RiskLevel,
    preselectable: Bool,
    explanation: String
  ) {
    self.identifier = identifier
    self.category = category
    self.pathPatterns = pathPatterns
    self.risk = risk
    self.preselectable = preselectable
    self.explanation = explanation
  }
}

public struct AdwareRule: Codable, Sendable, Equatable {
  public enum Kind: String, Codable, Sendable, Equatable {
    case launchAgent, launchDaemon, browserExtension, applicationPath
  }

  public let identifier: String
  public let kind: Kind
  public let pathPatterns: [PathPattern]
  public let explanation: String

  public init(identifier: String, kind: Kind, pathPatterns: [PathPattern], explanation: String) {
    self.identifier = identifier
    self.kind = kind
    self.pathPatterns = pathPatterns
    self.explanation = explanation
  }
}

/// The versioned, signed knowledge base: safe to clean paths, adware
/// signatures and the denylist.
public struct RuleCatalog: Codable, Sendable, Equatable {
  public let version: RuleCatalogVersion
  public let signature: Data
  public let cleanupRules: [CleanupRule]
  public let adwareRules: [AdwareRule]
  public let denylist: Denylist

  public init(
    version: RuleCatalogVersion,
    signature: Data,
    cleanupRules: [CleanupRule],
    adwareRules: [AdwareRule],
    denylist: Denylist
  ) {
    self.version = version
    self.signature = signature
    self.cleanupRules = cleanupRules
    self.adwareRules = adwareRules
    self.denylist = denylist
  }

  /// Decodes a catalogue from its manifest bytes. Throws
  /// `RuleCatalogError.malformedCatalog` for anything that is not a
  /// well formed manifest; a malformed manifest is never partially read.
  public init(manifestData: Data) throws {
    let decoder = JSONDecoder()
    do {
      self = try decoder.decode(RuleCatalog.self, from: manifestData)
    } catch {
      throw RuleCatalogError.malformedCatalog(
        description: "The manifest bytes do not decode as a rule catalogue."
      )
    }
  }

  /// The complete manifest bytes for this catalogue, including the
  /// signature. `init(manifestData:)` of these bytes returns an equal
  /// catalogue.
  public func manifestData() throws -> Data {
    try Self.canonicalEncoder().encode(self)
  }

  /// The canonical bytes the Ed25519 signature covers: every field of the
  /// catalogue except the signature itself, in a deterministic encoding.
  /// Equal catalogue content always produces identical bytes.
  public func canonicalContentEncoding() throws -> Data {
    let content = RuleCatalogContent(
      version: version,
      cleanupRules: cleanupRules,
      adwareRules: adwareRules,
      denylist: denylist
    )
    return try Self.canonicalEncoder().encode(content)
  }

  private static func canonicalEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
}

/// The signed portion of a catalogue: everything except the signature.
private struct RuleCatalogContent: Codable {
  let version: RuleCatalogVersion
  let cleanupRules: [CleanupRule]
  let adwareRules: [AdwareRule]
  let denylist: Denylist
}
