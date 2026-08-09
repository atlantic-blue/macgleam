import CryptoKit
import Foundation

/// Verifies a rule catalogue's Ed25519 signature against a pinned public
/// key. A catalogue that fails verification is never adopted and never
/// partially read into rules.
public struct RuleCatalogVerifier: Sendable {
  private let publicKey: Curve25519.Signing.PublicKey

  /// Takes the raw 32 byte Ed25519 public key. Throws when the bytes are
  /// not a valid key.
  public init(publicKey: Data) throws {
    self.publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
  }

  /// Throws `RuleCatalogError.signatureInvalid` for any signature that does
  /// not verify over the catalogue's canonical content encoding, including
  /// truncated and empty signature blobs.
  public func verify(_ catalog: RuleCatalog) throws {
    let content = try catalog.canonicalContentEncoding()
    guard publicKey.isValidSignature(catalog.signature, for: content) else {
      throw RuleCatalogError.signatureInvalid
    }
  }
}
