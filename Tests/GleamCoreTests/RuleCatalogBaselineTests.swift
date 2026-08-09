import Foundation
import GleamCore
import Testing

@Suite("Embedded rules baseline")
struct RuleCatalogBaselineTests {

  @Test("the embedded baseline loads")
  func embeddedBaselineLoads() throws {
    _ = try RuleCatalogBaseline.load()
  }

  @Test("the embedded baseline verifies against the pinned rules public key")
  func embeddedBaselineVerifiesAgainstPinnedKey() throws {
    let baseline = try RuleCatalogBaseline.load()
    let verifier = try RuleCatalogVerifier(publicKey: RuleCatalogBaseline.publicKey)
    try verifier.verify(baseline)
  }

  @Test("the pinned rules public key is a raw Ed25519 public key")
  func pinnedRulesPublicKeyIsRawEd25519() {
    #expect(RuleCatalogBaseline.publicKey.count == 32)
  }

  @Test("the baseline version starts the monotonic sequence at one or above")
  func baselineVersionStartsTheMonotonicSequence() throws {
    let baseline = try RuleCatalogBaseline.load()
    #expect(baseline.version.value >= 1)
  }

  @Test("the baseline denylist is not empty")
  func baselineDenylistIsNotEmpty() throws {
    let baseline = try RuleCatalogBaseline.load()
    #expect(!baseline.denylist.patterns.isEmpty)
  }

  @Test("the baseline denylist blocks the system volume root")
  func baselineDenylistBlocksSystemVolumeRoot() throws {
    let baseline = try RuleCatalogBaseline.load()
    #expect(baseline.denylist.blocks(Fixture.path("/System")))
  }

  @Test("the baseline denylist blocks descendants of the system volume")
  func baselineDenylistBlocksSystemDescendants() throws {
    let baseline = try RuleCatalogBaseline.load()
    #expect(baseline.denylist.blocks(Fixture.path("/System/Library/CoreServices")))
  }

  @Test("a store seeded with the embedded baseline serves it as current")
  func storeSeededWithEmbeddedBaselineServesItAsCurrent() async throws {
    let baseline = try RuleCatalogBaseline.load()
    let verifier = try RuleCatalogVerifier(publicKey: RuleCatalogBaseline.publicKey)
    let store = try RuleCatalogStore(baseline: baseline, verifier: verifier)
    #expect(await store.current == baseline)
  }

  @Test("the embedded baseline survives a Codable round trip")
  func embeddedBaselineSurvivesCodableRoundTrip() throws {
    try expectLosslessRoundTrip(try RuleCatalogBaseline.load())
  }
}
