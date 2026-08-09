import CryptoKit
import Foundation
import GleamCore

// Produces the embedded rules baseline: generates a fresh Ed25519 key pair,
// signs the baseline catalogue's canonical content encoding, and prints the
// public key bytes and the signed manifest as Swift literals for
// RuleCatalogBaseline.swift. The private key lives only in this process and
// is never printed or stored, so re running this tool mints a new key and
// requires re embedding both literals together.

let baselineDenylist = Denylist(patterns: [
  PathPattern(pattern: "/System"),
  PathPattern(pattern: "/usr"),
  PathPattern(pattern: "/bin"),
  PathPattern(pattern: "/sbin"),
  PathPattern(pattern: "/etc"),
  PathPattern(pattern: "/private/etc"),
  PathPattern(pattern: "/dev"),
  PathPattern(pattern: "/Library/Apple"),
])

let unsigned = RuleCatalog(
  version: RuleCatalogVersion(value: 1),
  signature: Data(),
  cleanupRules: [],
  adwareRules: [],
  denylist: baselineDenylist
)

let signingKey = Curve25519.Signing.PrivateKey()
let signature = try signingKey.signature(for: unsigned.canonicalContentEncoding())
let signed = RuleCatalog(
  version: unsigned.version,
  signature: signature,
  cleanupRules: unsigned.cleanupRules,
  adwareRules: unsigned.adwareRules,
  denylist: unsigned.denylist
)

let publicKeyBytes = signingKey.publicKey.rawRepresentation
  .map { String(format: "0x%02x", $0) }
  .joined(separator: ", ")
let manifestBase64 = try signed.manifestData().base64EncodedString()

print("public key bytes:")
print(publicKeyBytes)
print("manifest base64:")
print(manifestBase64)
