import CryptoKit
import Foundation
import GleamCore
import Testing

@Suite("Rule catalogue signature verification")
struct RuleCatalogSignatureVerificationTests {

  @Test("a well formed signed catalogue verifies")
  func wellFormedSignedCatalogueVerifies() throws {
    let catalog = try makeSignedCatalog()
    try makeVerifier().verify(catalog)
  }

  @Test("the canonical content encoding excludes the signature")
  func canonicalContentEncodingExcludesTheSignature() throws {
    let catalog = try makeSignedCatalog()
    let resigned = replacingSignature(of: catalog, with: Data([0x01]))
    #expect(try catalog.canonicalContentEncoding() == resigned.canonicalContentEncoding())
  }

  @Test("a signature with one flipped byte is rejected")
  func signatureWithOneFlippedByteIsRejected() throws {
    let catalog = try makeSignedCatalog()
    let tampered = replacingSignature(of: catalog, with: flippingOneByte(of: catalog.signature))
    #expect(throws: RuleCatalogError.signatureInvalid) {
      try makeVerifier().verify(tampered)
    }
  }

  @Test("a catalogue whose rules were mutated after signing is rejected")
  func catalogueMutatedAfterSigningIsRejected() throws {
    let catalog = try makeSignedCatalog()
    let hostile = makeCleanupRule(
      identifier: "hostile", patterns: ["/System/**"], risk: .safe, preselectable: true
    )
    let tampered = replacingContent(of: catalog, cleanupRules: catalog.cleanupRules + [hostile])
    #expect(throws: RuleCatalogError.signatureInvalid) {
      try makeVerifier().verify(tampered)
    }
  }

  @Test("a catalogue whose version was raised after signing is rejected")
  func catalogueVersionRaisedAfterSigningIsRejected() throws {
    let catalog = try makeSignedCatalog(version: 2)
    let tampered = replacingContent(of: catalog, version: 9)
    #expect(throws: RuleCatalogError.signatureInvalid) {
      try makeVerifier().verify(tampered)
    }
  }

  @Test("a catalogue truncated after signing is rejected")
  func catalogueTruncatedAfterSigningIsRejected() throws {
    let catalog = try makeSignedCatalog(
      cleanupRules: [makeCleanupRule(), makeCleanupRule(identifier: "second-rule")]
    )
    let truncated = replacingContent(
      of: catalog, cleanupRules: Array(catalog.cleanupRules.dropLast())
    )
    #expect(throws: RuleCatalogError.signatureInvalid) {
      try makeVerifier().verify(truncated)
    }
  }

  @Test("a catalogue whose denylist was emptied after signing is rejected")
  func catalogueDenylistEmptiedAfterSigningIsRejected() throws {
    let catalog = try makeSignedCatalog(denylist: makeDenylist(["/System"]))
    let tampered = replacingContent(of: catalog, denylist: makeDenylist([]))
    #expect(throws: RuleCatalogError.signatureInvalid) {
      try makeVerifier().verify(tampered)
    }
  }

  @Test("a catalogue signed with a different key is rejected")
  func catalogueSignedWithDifferentKeyIsRejected() throws {
    let catalog = try makeSignedCatalog(signedWith: SigningFixture.unrelatedPrivateKey)
    #expect(throws: RuleCatalogError.signatureInvalid) {
      try makeVerifier().verify(catalog)
    }
  }

  @Test("a truncated signature blob is rejected")
  func truncatedSignatureBlobIsRejected() throws {
    let catalog = try makeSignedCatalog()
    let truncated = replacingSignature(of: catalog, with: catalog.signature.prefix(8))
    #expect(throws: RuleCatalogError.signatureInvalid) {
      try makeVerifier().verify(truncated)
    }
  }

  @Test("an empty signature is rejected")
  func emptySignatureIsRejected() throws {
    let catalog = try makeSignedCatalog()
    let unsigned = replacingSignature(of: catalog, with: Data())
    #expect(throws: RuleCatalogError.signatureInvalid) {
      try makeVerifier().verify(unsigned)
    }
  }
}

@Suite("Rule catalogue manifest decoding")
struct RuleCatalogManifestDecodingTests {

  @Test("a serialized manifest round trips to an equal catalogue that still verifies")
  func serializedManifestRoundTripsAndStillVerifies() throws {
    let catalog = try makeSignedCatalog()
    let decoded = try RuleCatalog(manifestData: catalog.manifestData())
    #expect(decoded == catalog)
    try makeVerifier().verify(decoded)
  }

  @Test("a manifest with the wrong shape is rejected as malformed")
  func manifestWithWrongShapeIsRejectedAsMalformed() throws {
    let wrongShape = Data(#"{"schema": 99, "rules": [], "signature": "AA=="}"#.utf8)
    do {
      _ = try RuleCatalog(manifestData: wrongShape)
      Issue.record("decoded a manifest with the wrong shape")
    } catch let error as RuleCatalogError {
      guard case .malformedCatalog = error else {
        Issue.record("expected malformedCatalog, got \(error)")
        return
      }
    }
  }

  @Test("bytes that are not a manifest at all are rejected as malformed")
  func bytesThatAreNotAManifestAreRejectedAsMalformed() throws {
    let garbage = Data([0x00, 0xFF, 0x13, 0x37, 0x00])
    do {
      _ = try RuleCatalog(manifestData: garbage)
      Issue.record("decoded garbage bytes as a catalogue")
    } catch let error as RuleCatalogError {
      guard case .malformedCatalog = error else {
        Issue.record("expected malformedCatalog, got \(error)")
        return
      }
    }
  }

  @Test("a signed catalogue survives a Codable round trip")
  func signedCatalogueSurvivesCodableRoundTrip() throws {
    try expectLosslessRoundTrip(try makeSignedCatalog())
  }
}

@Suite("Rule catalogue verifier construction")
struct RuleCatalogVerifierConstructionTests {

  @Test("a verifier rejects a public key of the wrong length")
  func verifierRejectsPublicKeyOfWrongLength() {
    #expect(throws: (any Error).self) {
      _ = try RuleCatalogVerifier(publicKey: Data([0x01, 0x02, 0x03]))
    }
  }
}
