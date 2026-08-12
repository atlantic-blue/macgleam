import Foundation
import GleamCore

/// The boundary to the YARA library, kept narrow so the engine's tests run
/// against a matcher with scripted matches rather than against a real one.
///
/// Guarantees:
/// - `compile` accepts YARA rule source and throws `compileFailed` naming the
///   offending rule rather than a library error string, so the engine can say
///   which rule it disabled.
/// - `match` reads the candidate through `FileSystemReading` alone, so nothing
///   here can change a file it is examining. No match is not an error: it
///   answers with an empty array.
/// - Compiled rules are immutable and may be matched against concurrently.
public protocol YaraScanning: Sendable {
  func compile(rulesSource: String) throws -> CompiledYaraRules
  func match(
    file: AbsolutePath,
    against rules: CompiledYaraRules,
    fileSystem: any FileSystemReading
  ) async throws -> [YaraMatch]
}

public struct CompiledYaraRules: Sendable, Equatable {
  public let ruleCount: Int

  public init(ruleCount: Int) {
    self.ruleCount = ruleCount
  }
}

public struct YaraMatch: Sendable, Equatable {
  public let ruleIdentifier: String

  public init(ruleIdentifier: String) {
    self.ruleIdentifier = ruleIdentifier
  }
}

public enum YaraError: Error, Sendable, Equatable {
  case compileFailed(ruleIdentifier: String, description: String)
  case fileUnreadable(AbsolutePath)
}

/// One named rule source, compiled on its own.
///
/// One at a time rather than one document is what makes a compile failure
/// survivable: a single source holding every rule would take the whole
/// catalogue down with the worst line in it, and the contract says a rule that
/// will not compile disables itself and nothing else.
public struct YaraRuleSource: Sendable, Equatable {
  public let identifier: String
  public let source: String

  public init(identifier: String, source: String) {
    self.identifier = identifier
    self.source = source
  }
}
