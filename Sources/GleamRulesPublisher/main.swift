import CryptoKit
import Foundation
import GleamCore

// The rules channel's publisher. It signs a catalogue with the rules key and
// writes the manifest every MacGleam will verify, and it refuses to do
// anything the app would refuse afterwards.
//
// The key comes from the environment and nowhere else, because the only copy
// of it lives in the publishing pipeline's secrets. It is never written to
// disk here, never printed, and never taken from a file path, so a key that
// leaked onto a developer machine cannot be used by running this tool.

enum PublisherError: Error, CustomStringConvertible {
  case usage
  case missingKey
  case unreadableKey
  case unreadableCatalog(String)
  case versionNotAnInteger(String)
  case signatureDoesNotVerify

  var description: String {
    switch self {
    case .usage:
      return """
        usage:
          GleamRulesPublisher --catalog <path> --version <n> --out <path>
          GleamRulesPublisher --verify <manifest path>
        """
    case .missingKey:
      return
        "RULES_SIGNING_KEY is not set. The rules key lives only in the publishing pipeline's "
        + "secrets, so this tool cannot sign anything without it."
    case .unreadableKey:
      return "RULES_SIGNING_KEY is not a base64 encoded Ed25519 private key."
    case .unreadableCatalog(let path):
      return "\(path) is not a rule catalogue this tool can read."
    case .versionNotAnInteger(let value):
      return "\(value) is not a version number."
    case .signatureDoesNotVerify:
      return
        "The manifest does not verify against the pinned public key, so every MacGleam would "
        + "refuse it. Nothing was published."
    }
  }
}

/// What the publisher was asked to do. Two shapes and no third: sign a
/// catalogue, or check a manifest the way the app checks it.
enum Command {
  case sign(catalog: String, version: UInt32, out: String)
  case verify(manifest: String)

  static func parse(_ arguments: [String]) throws -> Command {
    var catalog: String?
    var version: String?
    var out: String?
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--verify":
        guard index + 1 < arguments.count else { throw PublisherError.usage }
        return .verify(manifest: arguments[index + 1])
      case "--catalog":
        guard index + 1 < arguments.count else { throw PublisherError.usage }
        catalog = arguments[index + 1]
        index += 1
      case "--version":
        guard index + 1 < arguments.count else { throw PublisherError.usage }
        version = arguments[index + 1]
        index += 1
      case "--out":
        guard index + 1 < arguments.count else { throw PublisherError.usage }
        out = arguments[index + 1]
        index += 1
      default:
        throw PublisherError.usage
      }
      index += 1
    }
    guard let catalog, let version, let out else { throw PublisherError.usage }
    guard let value = UInt32(version) else {
      throw PublisherError.versionNotAnInteger(version)
    }
    return .sign(catalog: catalog, version: value, out: out)
  }
}

func signingKey() throws -> Curve25519.Signing.PrivateKey {
  guard let encoded = ProcessInfo.processInfo.environment["RULES_SIGNING_KEY"],
    !encoded.isEmpty
  else { throw PublisherError.missingKey }
  guard let raw = Data(base64Encoded: encoded),
    let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
  else { throw PublisherError.unreadableKey }
  return key
}

func readCatalog(at path: String) throws -> RuleCatalog {
  guard let data = FileManager.default.contents(atPath: path),
    let catalog = try? RuleCatalog(manifestData: data)
  else { throw PublisherError.unreadableCatalog(path) }
  return catalog
}

func sign(catalog path: String, version: UInt32, out: String) throws {
  let unsigned = try readCatalog(at: path)
  let content = RuleCatalog(
    version: RuleCatalogVersion(value: version),
    signature: Data(),
    cleanupRules: unsigned.cleanupRules,
    adwareRules: unsigned.adwareRules,
    denylist: unsigned.denylist)
  let signature = try signingKey().signature(for: content.canonicalContentEncoding())
  let signed = RuleCatalog(
    version: content.version,
    signature: signature,
    cleanupRules: content.cleanupRules,
    adwareRules: content.adwareRules,
    denylist: content.denylist)
  try verify(signed)
  let directory = (out as NSString).deletingLastPathComponent
  if !directory.isEmpty {
    try FileManager.default.createDirectory(
      atPath: directory, withIntermediateDirectories: true)
  }
  try signed.manifestData().write(to: URL(fileURLWithPath: out))
  print("Signed catalogue version \(version) into \(out).")
}

/// The same check the app makes, made here, so a manifest that would be
/// refused by every installation is refused before it is published rather
/// than after.
func verify(_ catalog: RuleCatalog) throws {
  let verifier = try RuleCatalogVerifier(publicKey: RuleCatalogBaseline.publicKey)
  do {
    try verifier.verify(catalog)
  } catch {
    throw PublisherError.signatureDoesNotVerify
  }
}

do {
  switch try Command.parse(Array(CommandLine.arguments.dropFirst())) {
  case .sign(let catalog, let version, let out):
    try sign(catalog: catalog, version: version, out: out)
  case .verify(let manifest):
    try verify(try readCatalog(at: manifest))
    print("\(manifest) verifies against the pinned public key.")
  }
} catch {
  FileHandle.standardError.write(Data("\(error)\n".utf8))
  exit(1)
}
