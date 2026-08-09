import Foundation

/// A restricted glob over absolute paths. Supports literal components, a
/// single component wildcard "*" and a trailing subtree wildcard "**".
/// Deliberately not a regular expression: patterns are reviewable by a human.
public struct PathPattern: Codable, Sendable, Equatable {
  public let pattern: String

  public init(pattern: String) {
    self.pattern = pattern
  }

  /// Componentwise match. "*" matches exactly one component. A trailing "**"
  /// matches any descendant of the prefix, respecting component boundaries.
  public func matches(_ path: AbsolutePath) -> Bool {
    var patternComponents = pattern.split(separator: "/").map(String.init)
    let pathComponents = path.components
    if patternComponents.last == "**" {
      patternComponents.removeLast()
      guard pathComponents.count > patternComponents.count else { return false }
      return zip(patternComponents, pathComponents).allSatisfy(Self.componentMatches)
    }
    guard patternComponents.count == pathComponents.count else { return false }
    return zip(patternComponents, pathComponents).allSatisfy(Self.componentMatches)
  }

  private static func componentMatches(_ patternComponent: String, _ pathComponent: String) -> Bool
  {
    patternComponent == "*" || patternComponent == pathComponent
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
    var candidate: AbsolutePath? = path
    while let current = candidate {
      if patterns.contains(where: { $0.matches(current) }) { return true }
      candidate = current.parent
    }
    return false
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
}
