import Foundation

/// Holds the adopted rule catalogue for one process and applies signed
/// updates atomically. Each process verifies its own catalogue: the store
/// re verifies everything it is given, including the embedded baseline.
public actor RuleCatalogStore: RuleCatalogProviding {
  /// Fetches the raw channel manifest bytes. The network transport behind
  /// this closure is injected; the store itself never talks to the network.
  public typealias ChannelFetch = @Sendable () async throws -> Data

  private let baseline: RuleCatalog
  private let verifier: RuleCatalogVerifier
  private let channelFetch: ChannelFetch?

  public private(set) var current: RuleCatalog

  /// Verifies the baseline before accepting it. A tampered baseline throws
  /// `RuleCatalogError.signatureInvalid` and the store never exists.
  public init(
    baseline: RuleCatalog,
    verifier: RuleCatalogVerifier,
    channelFetch: ChannelFetch? = nil
  ) throws {
    try verifier.verify(baseline)
    self.baseline = baseline
    self.verifier = verifier
    self.channelFetch = channelFetch
    self.current = baseline
  }

  /// The union of the baseline denylist and the adopted catalogue's
  /// denylist. Baseline entries are never lost, so an update can extend the
  /// denylist and can never shrink it below the baseline.
  public var effectiveDenylist: Denylist {
    var patterns = baseline.denylist.patterns
    for pattern in current.denylist.patterns where !patterns.contains(pattern) {
      patterns.append(pattern)
    }
    return Denylist(patterns: patterns)
  }

  /// Adopts a candidate catalogue when its signature verifies and its
  /// version is strictly greater than the current one. A rejected candidate
  /// throws and leaves `current` and `effectiveDenylist` exactly untouched.
  public func apply(_ candidate: RuleCatalog) throws -> RuleCatalogUpdate {
    try verifier.verify(candidate)
    guard candidate.version > current.version else {
      throw RuleCatalogError.versionNotNewer(
        current: current.version,
        offered: candidate.version
      )
    }
    let previous = current.version
    current = candidate
    return .updated(from: previous, to: candidate.version)
  }

  /// Fetches the channel manifest through the injected transport, then
  /// applies it. Offering the version already adopted returns
  /// `.alreadyCurrent` without changing anything.
  public func refreshFromChannel() async throws -> RuleCatalogUpdate {
    guard let channelFetch else {
      throw RuleCatalogError.channelUnreachable(
        description: "No rules channel is configured for this store."
      )
    }
    let manifestData: Data
    do {
      manifestData = try await channelFetch()
    } catch {
      throw RuleCatalogError.channelUnreachable(
        description: "The rules channel could not be reached."
      )
    }
    let candidate = try RuleCatalog(manifestData: manifestData)
    try verifier.verify(candidate)
    if candidate.version == current.version {
      return .alreadyCurrent
    }
    return try apply(candidate)
  }
}
