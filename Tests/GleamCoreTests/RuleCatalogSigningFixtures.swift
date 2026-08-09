import CryptoKit
import Foundation
import GleamCore

/// Deterministic signing fixtures for the rule catalogue tests. Both private
/// keys derive from fixed bytes, so every run signs with the same keys. The
/// production rules key never appears here: catalogues are signed with the
/// test key and verified through a verifier constructed with the matching
/// test public key.
enum SigningFixture {

  static let rulesPrivateKey = try! Curve25519.Signing.PrivateKey(
    rawRepresentation: Data(repeating: 0x11, count: 32)
  )

  static let unrelatedPrivateKey = try! Curve25519.Signing.PrivateKey(
    rawRepresentation: Data(repeating: 0x22, count: 32)
  )

  static var rulesPublicKeyData: Data {
    rulesPrivateKey.publicKey.rawRepresentation
  }
}

func makeVerifier() throws -> RuleCatalogVerifier {
  try RuleCatalogVerifier(publicKey: SigningFixture.rulesPublicKeyData)
}

/// Builds a catalogue and signs its canonical content encoding, so the
/// result verifies against the key it was signed with.
func makeSignedCatalog(
  version: UInt32 = 2,
  cleanupRules: [CleanupRule] = [makeCleanupRule()],
  adwareRules: [AdwareRule] = [makeAdwareRule()],
  denylist: Denylist = makeDenylist(["/System"]),
  signedWith key: Curve25519.Signing.PrivateKey = SigningFixture.rulesPrivateKey
) throws -> RuleCatalog {
  let unsigned = RuleCatalog(
    version: RuleCatalogVersion(value: version),
    signature: Data(),
    cleanupRules: cleanupRules,
    adwareRules: adwareRules,
    denylist: denylist
  )
  let signature = try key.signature(for: unsigned.canonicalContentEncoding())
  return RuleCatalog(
    version: unsigned.version,
    signature: signature,
    cleanupRules: unsigned.cleanupRules,
    adwareRules: unsigned.adwareRules,
    denylist: unsigned.denylist
  )
}

/// Reconstructs a catalogue with one field changed while keeping the
/// original signature, which is what a tampered payload looks like.
func replacingContent(
  of catalog: RuleCatalog,
  version: UInt32? = nil,
  cleanupRules: [CleanupRule]? = nil,
  adwareRules: [AdwareRule]? = nil,
  denylist: Denylist? = nil
) -> RuleCatalog {
  RuleCatalog(
    version: version.map(RuleCatalogVersion.init(value:)) ?? catalog.version,
    signature: catalog.signature,
    cleanupRules: cleanupRules ?? catalog.cleanupRules,
    adwareRules: adwareRules ?? catalog.adwareRules,
    denylist: denylist ?? catalog.denylist
  )
}

func replacingSignature(of catalog: RuleCatalog, with signature: Data) -> RuleCatalog {
  RuleCatalog(
    version: catalog.version,
    signature: signature,
    cleanupRules: catalog.cleanupRules,
    adwareRules: catalog.adwareRules,
    denylist: catalog.denylist
  )
}

func flippingOneByte(of data: Data) -> Data {
  var mutated = data
  mutated[mutated.startIndex] ^= 0xFF
  return mutated
}

/// A store seeded with a signed baseline at the given version, verifying
/// with the test key.
func makeStore(
  baselineVersion: UInt32 = 1,
  baselineDenylist: [String] = ["/System", "/usr/bin"]
) throws -> RuleCatalogStore {
  let baseline = try makeSignedCatalog(
    version: baselineVersion,
    denylist: makeDenylist(baselineDenylist)
  )
  return try RuleCatalogStore(baseline: baseline, verifier: makeVerifier())
}
