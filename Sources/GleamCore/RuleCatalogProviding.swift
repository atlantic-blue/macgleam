import Foundation

/// Owns the current rule catalogue: the embedded baseline plus signed
/// channel updates.
///
/// `current` is always available; first launch with no network serves the
/// embedded baseline. `refreshFromChannel` adopts a catalogue only when its
/// Ed25519 signature verifies against the pinned rules public key and its
/// version is strictly greater than the current one. Any failure leaves
/// `current` exactly as it was and throws a typed error.
public protocol RuleCatalogProviding: Sendable {
  var current: RuleCatalog { get async }
  func refreshFromChannel() async throws -> RuleCatalogUpdate
}

/// The outcome of a successful refresh or apply.
public enum RuleCatalogUpdate: Sendable, Equatable {
  case alreadyCurrent
  case updated(from: RuleCatalogVersion, to: RuleCatalogVersion)
}

public enum RuleCatalogError: Error, Sendable, Equatable {
  case signatureInvalid
  case versionNotNewer(current: RuleCatalogVersion, offered: RuleCatalogVersion)
  case malformedCatalog(description: String)
  case channelUnreachable(description: String)
}
