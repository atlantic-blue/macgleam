import Foundation

/// The rule catalogue baseline embedded in every build. First launch with no
/// network runs entirely from this catalogue, and its denylist is the floor
/// no signed update can ever shrink below.
///
/// Both literals below were produced in one run of the GleamBaselineGenerator
/// target in this package, which mints an Ed25519 key pair, signs the
/// baseline catalogue's canonical content encoding, and prints the public key
/// bytes and the manifest base64. The private key existed only inside that
/// process and was never printed or stored, so the pair below can only be
/// replaced together by another generator run. This is a development stage
/// key; the production signing key ceremony is an M7 launch task.
public enum RuleCatalogBaseline {
  /// The raw 32 byte Ed25519 public key the baseline is signed with.
  public static let publicKey = Data([
    0xe7, 0xbb, 0xe2, 0x19, 0xd9, 0x0c, 0x67, 0xca, 0xc8, 0x13, 0xea, 0x11, 0xe9, 0x6b, 0x3d,
    0xfe, 0xee, 0x5d, 0x85, 0x72, 0x69, 0x70, 0x72, 0x60, 0x18, 0x6b, 0x4e, 0x33, 0xcd, 0xfc,
    0xb2, 0xd1,
  ])

  private static let manifestBase64 = """
    eyJhZHdhcmVSdWxlcyI6W10sImNsZWFudXBSdWxlcyI6W10sImRlbnlsaXN0Ijp7InBhdHRlcm5zIjpbeyJwYXR0ZXJ\
    uIjoiL1N5c3RlbSJ9LHsicGF0dGVybiI6Ii91c3IifSx7InBhdHRlcm4iOiIvYmluIn0seyJwYXR0ZXJuIjoiL3NiaW\
    4ifSx7InBhdHRlcm4iOiIvZXRjIn0seyJwYXR0ZXJuIjoiL3ByaXZhdGUvZXRjIn0seyJwYXR0ZXJuIjoiL2RldiJ9L\
    HsicGF0dGVybiI6Ii9MaWJyYXJ5L0FwcGxlIn1dfSwic2lnbmF0dXJlIjoiaWF2T2xwbGg4YzJVVzQrVGwxaVNGS3J1\
    aU9XbVE1K2VLLzcwSVE1dnBnU3lWMksvWFBzZHdtcldqa1VwaWEyT0dFWnY5N1pjbmtjcDBFZlpiYmhrQ1E9PSIsInZ\
    lcnNpb24iOnsidmFsdWUiOjF9fQ==
    """

  /// Decodes the embedded baseline manifest. Throws
  /// `RuleCatalogError.malformedCatalog` if the embedded bytes are corrupt.
  public static func load() throws -> RuleCatalog {
    guard let manifestData = Data(base64Encoded: manifestBase64) else {
      throw RuleCatalogError.malformedCatalog(
        description: "The embedded baseline manifest is not valid base64."
      )
    }
    return try RuleCatalog(manifestData: manifestData)
  }
}
