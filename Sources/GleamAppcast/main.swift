import CryptoKit
import Foundation
import GleamCore

// Writes the appcast entry for one release and signs it with the update key.
//
// The key comes from the environment and nowhere else, because the only copy
// of it lives in the release pipeline's secrets. An entry signed anywhere else
// is refused by every installation, since the public half is in the bundle.

enum AppcastError: Error, CustomStringConvertible {
  case usage
  case missingKey
  case unreadableKey
  case unreadableDiskImage(String)

  var description: String {
    switch self {
    case .usage:
      return
        "usage: GleamAppcast --disk-image <path> --version <version> "
        + "--channel <stable|beta> --out <path>"
    case .missingKey:
      return
        "SPARKLE_PRIVATE_KEY is not set. The update key lives only in the release pipeline's "
        + "secrets, so this tool cannot sign anything without it."
    case .unreadableKey:
      return "SPARKLE_PRIVATE_KEY is not a base64 encoded Ed25519 private key."
    case .unreadableDiskImage(let path):
      return "\(path) could not be read, so there is nothing to publish."
    }
  }
}

func value(of flag: String, in arguments: [String]) -> String? {
  guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
    return nil
  }
  return arguments[index + 1]
}

let arguments = Array(CommandLine.arguments.dropFirst())

do {
  guard let diskImagePath = value(of: "--disk-image", in: arguments),
    let version = value(of: "--version", in: arguments),
    let channelName = value(of: "--channel", in: arguments),
    let out = value(of: "--out", in: arguments),
    let channel = UpdateChannel(rawValue: channelName)
  else { throw AppcastError.usage }

  guard let diskImage = FileManager.default.contents(atPath: diskImagePath) else {
    throw AppcastError.unreadableDiskImage(diskImagePath)
  }
  guard let encodedKey = ProcessInfo.processInfo.environment["SPARKLE_PRIVATE_KEY"],
    !encodedKey.isEmpty
  else { throw AppcastError.missingKey }
  guard let rawKey = Data(base64Encoded: encodedKey),
    let signingKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: rawKey)
  else { throw AppcastError.unreadableKey }

  let signature = try signingKey.signature(for: diskImage).base64EncodedString()
  let published = ISO8601DateFormatter().string(from: Date())
  let name = (diskImagePath as NSString).lastPathComponent
  let appcast = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <title>MacGleam \(channel.rawValue)</title>
        <link>\(channel.appcastURL.absoluteString)</link>
        <item>
          <title>Version \(version)</title>
          <pubDate>\(published)</pubDate>
          <sparkle:version>\(version)</sparkle:version>
          <sparkle:shortVersionString>\(version)</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
          <enclosure
            url="https://updates.macgleam.app/\(name)"
            length="\(diskImage.count)"
            type="application/octet-stream"
            sparkle:edSignature="\(signature)" />
        </item>
      </channel>
    </rss>

    """
  try appcast.write(toFile: out, atomically: true, encoding: .utf8)
  print("Wrote a signed \(channel.rawValue) appcast entry for \(version) into \(out).")
} catch {
  FileHandle.standardError.write(Data("\(error)\n".utf8))
  exit(1)
}
