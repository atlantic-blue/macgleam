import CryptoKit
import Foundation
import GleamCore
import Testing

/// The live rules channel: what a published update has to survive before it
/// changes what this Mac will delete.
///
/// The trust is in the signature and never in the transport. A channel that is
/// compromised, redirected, replayed or simply wrong hands over bytes that are
/// then refused, and the catalogue in force stays in force. These drive the
/// refresh path end to end through a scripted fetch, because the store's own
/// suite proves `apply` and this proves the thing the app actually calls.
@Suite("Rules channel")
struct RulesChannelTests {

  private func signingKey() throws -> Curve25519.Signing.PrivateKey {
    try Curve25519.Signing.PrivateKey(rawRepresentation: catalogSigningSeed)
  }

  private func store(
    baselineVersion: UInt32 = 1,
    answering manifest: @escaping @Sendable () async throws -> Data
  ) throws -> RuleCatalogStore {
    let key = try signingKey()
    let verifier = try RuleCatalogVerifier(publicKey: key.publicKey.rawRepresentation)
    return try RuleCatalogStore(
      baseline: try signedCatalog(version: baselineVersion, blocking: ["/System"]),
      verifier: verifier,
      channelFetch: manifest)
  }

  private func signedCatalog(
    version: UInt32,
    blocking patterns: [String],
    signedWith key: Curve25519.Signing.PrivateKey? = nil
  ) throws -> RuleCatalog {
    let signingKey = try key ?? self.signingKey()
    let unsigned = RuleCatalog(
      version: RuleCatalogVersion(value: version),
      signature: Data(),
      cleanupRules: [],
      adwareRules: [],
      denylist: Denylist(patterns: patterns.map { PathPattern(pattern: $0) }))
    return RuleCatalog(
      version: unsigned.version,
      signature: try signingKey.signature(for: unsigned.canonicalContentEncoding()),
      cleanupRules: unsigned.cleanupRules,
      adwareRules: unsigned.adwareRules,
      denylist: unsigned.denylist)
  }

  // MARK: - What is adopted

  @Test("a newer catalogue the channel publishes is fetched, verified and adopted")
  func aNewerCatalogueIsAdopted() async throws {
    let published = try signedCatalog(version: 2, blocking: ["/System", "/Library/Keychains"])
    let store = try store(answering: { try published.manifestData() })

    let outcome = try await store.refreshFromChannel()

    #expect(
      outcome
        == .updated(from: RuleCatalogVersion(value: 1), to: RuleCatalogVersion(value: 2)))
    #expect(await store.current.version == RuleCatalogVersion(value: 2))
    #expect(await store.effectiveDenylist.blocks(Fixture.path("/Library/Keychains/login.db")))
  }

  @Test("the version already in force is reported as such and changes nothing")
  func theVersionAlreadyInForceChangesNothing() async throws {
    let store = try store(answering: {
      try self.signedCatalog(version: 1, blocking: ["/System"]).manifestData()
    })

    #expect(try await store.refreshFromChannel() == .alreadyCurrent)
    #expect(await store.current.version == RuleCatalogVersion(value: 1))
  }

  // MARK: - What is refused

  @Test("a tampered manifest is refused and the rules in force are untouched")
  func aTamperedManifestIsRefused() async throws {
    let published = try signedCatalog(version: 2, blocking: ["/System"])
    let tampered = RuleCatalog(
      version: published.version,
      signature: published.signature,
      cleanupRules: published.cleanupRules,
      adwareRules: published.adwareRules,
      denylist: Denylist(patterns: [PathPattern(pattern: "/nothing")]))
    let store = try store(answering: { try tampered.manifestData() })

    await #expect(throws: RuleCatalogError.signatureInvalid) {
      _ = try await store.refreshFromChannel()
    }
    #expect(await store.current.version == RuleCatalogVersion(value: 1))
    #expect(await store.effectiveDenylist.blocks(Fixture.path("/System/Library")))
  }

  @Test("a manifest signed with another key is refused, however new it claims to be")
  func aManifestSignedWithAnotherKeyIsRefused() async throws {
    let intruderKey = Curve25519.Signing.PrivateKey()
    let published = try signedCatalog(version: 99, blocking: [], signedWith: intruderKey)
    let store = try store(answering: { try published.manifestData() })

    await #expect(throws: RuleCatalogError.signatureInvalid) {
      _ = try await store.refreshFromChannel()
    }
    #expect(await store.current.version == RuleCatalogVersion(value: 1))
  }

  @Test("an older catalogue replayed at the channel is refused, naming both versions")
  func aReplayedCatalogueIsRefused() async throws {
    let store = try store(
      baselineVersion: 5,
      answering: {
        try self.signedCatalog(version: 4, blocking: ["/System"]).manifestData()
      })

    await #expect(
      throws: RuleCatalogError.versionNotNewer(
        current: RuleCatalogVersion(value: 5), offered: RuleCatalogVersion(value: 4))
    ) {
      _ = try await store.refreshFromChannel()
    }
    #expect(await store.current.version == RuleCatalogVersion(value: 5))
  }

  @Test("a channel that cannot be reached leaves the rules exactly as they were")
  func anUnreachableChannelChangesNothing() async throws {
    struct Unreachable: Error {}
    let store = try store(answering: { throw Unreachable() })

    await #expect(throws: (any Error).self) {
      _ = try await store.refreshFromChannel()
    }
    #expect(await store.current.version == RuleCatalogVersion(value: 1))
    #expect(await store.effectiveDenylist.blocks(Fixture.path("/System/Library")))
  }

  @Test("bytes that are not a catalogue at all are refused")
  func bytesThatAreNotACatalogueAreRefused() async throws {
    let store = try store(answering: { Data("not a manifest".utf8) })

    await #expect(throws: (any Error).self) {
      _ = try await store.refreshFromChannel()
    }
    #expect(await store.current.version == RuleCatalogVersion(value: 1))
  }

  @Test("an update that drops a baseline protection cannot remove it")
  func anUpdateCannotRemoveABaselineProtection() async throws {
    let published = try signedCatalog(version: 2, blocking: ["/Library/Keychains"])
    let store = try store(answering: { try published.manifestData() })

    _ = try await store.refreshFromChannel()

    #expect(
      await store.effectiveDenylist.blocks(Fixture.path("/System/Library")),
      """
      the baseline denylist is the floor. A published catalogue can extend what \
      is protected and can never shrink it, whoever signed it
      """)
  }

  // MARK: - The endpoint

  @Test("the channel names one endpoint, and it is one of the three the app is allowed")
  func theChannelNamesOneEndpoint() {
    let url = RulesChannel.manifestURL
    #expect(url.scheme == "https")
    #expect(url.host() == "rules.macgleam.app")
    #expect(url.query() == nil, "a query would be a place to put something about this Mac")
  }
}

/// A signing seed owned by this file alone. The production rules key never
/// appears in a test.
private let catalogSigningSeed = Data((0..<32).map { UInt8(truncatingIfNeeded: 0x51 &+ $0 &* 11) })
