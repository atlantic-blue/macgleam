import Foundation
import GleamCore
import Testing

@Suite("Rule catalogue store adoption")
struct RuleCatalogStoreAdoptionTests {

  @Test("the store starts on the baseline it was given")
  func storeStartsOnItsBaseline() async throws {
    let baseline = try makeSignedCatalog(version: 1)
    let store = try RuleCatalogStore(baseline: baseline, verifier: makeVerifier())
    #expect(await store.current == baseline)
  }

  @Test("a store refuses a baseline that fails verification")
  func storeRefusesBaselineThatFailsVerification() throws {
    let baseline = try makeSignedCatalog(version: 1)
    let tampered = replacingSignature(of: baseline, with: flippingOneByte(of: baseline.signature))
    #expect(throws: RuleCatalogError.signatureInvalid) {
      _ = try RuleCatalogStore(baseline: tampered, verifier: makeVerifier())
    }
  }

  @Test("a verified strictly newer catalogue is adopted and becomes current")
  func verifiedStrictlyNewerCatalogueIsAdopted() async throws {
    let store = try makeStore(baselineVersion: 1)
    let candidate = try makeSignedCatalog(version: 2)
    let update = try await store.apply(candidate)
    #expect(
      update == .updated(from: RuleCatalogVersion(value: 1), to: RuleCatalogVersion(value: 2))
    )
    #expect(await store.current == candidate)
  }

  @Test("adoption replaces the cleanup and adware rules with the candidate's")
  func adoptionReplacesRulesWithTheCandidates() async throws {
    let store = try makeStore(baselineVersion: 1)
    let newRule = makeCleanupRule(
      identifier: "xcode-derived-data",
      patterns: ["/Users/*/Library/Developer/Xcode/DerivedData/**"])
    let candidate = try makeSignedCatalog(version: 2, cleanupRules: [newRule], adwareRules: [])
    _ = try await store.apply(candidate)
    #expect(await store.current.cleanupRules == [newRule])
    #expect(await store.current.adwareRules == [])
  }
}

@Suite("Rule catalogue store version monotonicity")
struct RuleCatalogStoreVersionTests {

  @Test("a lower version is rejected naming both versions")
  func lowerVersionIsRejectedNamingBothVersions() async throws {
    let store = try makeStore(baselineVersion: 5)
    let stale = try makeSignedCatalog(version: 4)
    await #expect(
      throws: RuleCatalogError.versionNotNewer(
        current: RuleCatalogVersion(value: 5), offered: RuleCatalogVersion(value: 4)
      )
    ) {
      _ = try await store.apply(stale)
    }
    #expect(await store.current.version == RuleCatalogVersion(value: 5))
  }

  @Test("an equal version is rejected naming both versions")
  func equalVersionIsRejectedNamingBothVersions() async throws {
    let store = try makeStore(baselineVersion: 5)
    let replay = try makeSignedCatalog(version: 5)
    await #expect(
      throws: RuleCatalogError.versionNotNewer(
        current: RuleCatalogVersion(value: 5), offered: RuleCatalogVersion(value: 5)
      )
    ) {
      _ = try await store.apply(replay)
    }
    #expect(await store.current.version == RuleCatalogVersion(value: 5))
  }

  @Test("a strictly higher version is accepted and the stored version advances")
  func strictlyHigherVersionAdvancesTheStoredVersion() async throws {
    let store = try makeStore(baselineVersion: 5)
    _ = try await store.apply(try makeSignedCatalog(version: 6))
    #expect(await store.current.version == RuleCatalogVersion(value: 6))
  }

  @Test("versions compare by value")
  func versionsCompareByValue() {
    #expect(RuleCatalogVersion(value: 1) < RuleCatalogVersion(value: 2))
    #expect(!(RuleCatalogVersion(value: 2) < RuleCatalogVersion(value: 2)))
  }
}

@Suite("Rule catalogue store rejection leaves current untouched")
struct RuleCatalogStoreRejectionAtomicityTests {

  @Test("a tampered candidate is rejected and current is exactly what it was")
  func tamperedCandidateLeavesCurrentExactlyAsItWas() async throws {
    let store = try makeStore(baselineVersion: 1)
    let before = await store.current
    let candidate = try makeSignedCatalog(version: 2)
    let tampered = replacingContent(
      of: candidate,
      cleanupRules: candidate.cleanupRules + [makeCleanupRule(identifier: "smuggled")]
    )
    await #expect(throws: RuleCatalogError.signatureInvalid) {
      _ = try await store.apply(tampered)
    }
    #expect(await store.current == before)
  }

  @Test("a candidate signed with a different key is rejected and current is exactly what it was")
  func wrongKeyCandidateLeavesCurrentExactlyAsItWas() async throws {
    let store = try makeStore(baselineVersion: 1)
    let before = await store.current
    let candidate = try makeSignedCatalog(
      version: 2, signedWith: SigningFixture.unrelatedPrivateKey
    )
    await #expect(throws: RuleCatalogError.signatureInvalid) {
      _ = try await store.apply(candidate)
    }
    #expect(await store.current == before)
  }

  @Test("a stale candidate is rejected and current is exactly what it was")
  func staleCandidateLeavesCurrentExactlyAsItWas() async throws {
    let store = try makeStore(baselineVersion: 3)
    let before = await store.current
    await #expect(throws: RuleCatalogError.self) {
      _ = try await store.apply(try makeSignedCatalog(version: 2))
    }
    #expect(await store.current == before)
  }

  @Test("a rejected candidate leaves the effective denylist exactly as it was")
  func rejectedCandidateLeavesEffectiveDenylistAsItWas() async throws {
    let store = try makeStore(baselineVersion: 1, baselineDenylist: ["/System"])
    let before = await store.effectiveDenylist
    let candidate = try makeSignedCatalog(version: 2, denylist: makeDenylist(["/Applications"]))
    let tampered = replacingSignature(of: candidate, with: flippingOneByte(of: candidate.signature))
    await #expect(throws: RuleCatalogError.signatureInvalid) {
      _ = try await store.apply(tampered)
    }
    #expect(await store.effectiveDenylist == before)
    #expect(await !store.effectiveDenylist.blocks(Fixture.path("/Applications")))
  }
}

@Suite("Effective denylist union supremacy")
struct EffectiveDenylistUnionTests {

  @Test("before any update the effective denylist blocks every baseline entry")
  func beforeAnyUpdateEffectiveDenylistBlocksBaselineEntries() async throws {
    let store = try makeStore(baselineDenylist: ["/System", "/usr/bin"])
    #expect(await store.effectiveDenylist.blocks(Fixture.path("/System")))
    #expect(await store.effectiveDenylist.blocks(Fixture.path("/usr/bin")))
  }

  @Test("an update omitting baseline entries never removes them from the effective denylist")
  func updateOmittingBaselineEntriesNeverRemovesThem() async throws {
    let store = try makeStore(baselineDenylist: ["/System", "/usr/bin"])
    let candidate = try makeSignedCatalog(version: 2, denylist: makeDenylist(["/usr/bin"]))
    _ = try await store.apply(candidate)
    #expect(await store.effectiveDenylist.blocks(Fixture.path("/System")))
    #expect(await store.effectiveDenylist.blocks(Fixture.path("/usr/bin")))
  }

  @Test("an update with a disjoint denylist adds its entries and keeps every baseline entry")
  func updateWithDisjointDenylistAddsAndKeepsBaseline() async throws {
    let store = try makeStore(baselineDenylist: ["/System", "/usr/bin"])
    let candidate = try makeSignedCatalog(
      version: 2, denylist: makeDenylist(["/Library/Apple/**"])
    )
    _ = try await store.apply(candidate)
    #expect(await store.effectiveDenylist.blocks(Fixture.path("/System")))
    #expect(await store.effectiveDenylist.blocks(Fixture.path("/usr/bin")))
    #expect(await store.effectiveDenylist.blocks(Fixture.path("/Library/Apple/Updates")))
  }

  @Test("an update with an empty denylist leaves every baseline entry blocked")
  func updateWithEmptyDenylistLeavesBaselineBlocked() async throws {
    let store = try makeStore(baselineDenylist: ["/System", "/usr/bin"])
    let candidate = try makeSignedCatalog(version: 2, denylist: makeDenylist([]))
    _ = try await store.apply(candidate)
    #expect(await store.effectiveDenylist.blocks(Fixture.path("/System")))
    #expect(await store.effectiveDenylist.blocks(Fixture.path("/usr/bin")))
  }

  @Test("baseline entries survive a chain of updates that each omit them")
  func baselineEntriesSurviveAChainOfUpdates() async throws {
    let store = try makeStore(baselineDenylist: ["/System"])
    _ = try await store.apply(
      try makeSignedCatalog(version: 2, denylist: makeDenylist(["/private/var/db"]))
    )
    _ = try await store.apply(try makeSignedCatalog(version: 3, denylist: makeDenylist([])))
    #expect(await store.effectiveDenylist.blocks(Fixture.path("/System")))
    #expect(await store.effectiveDenylist.blocks(Fixture.path("/System/Library/CoreServices")))
  }

  @Test("the effective denylist blocks descendants of every baseline directory")
  func effectiveDenylistBlocksDescendantsOfBaselineDirectories() async throws {
    let store = try makeStore(baselineDenylist: ["/System"])
    let candidate = try makeSignedCatalog(version: 2, denylist: makeDenylist([]))
    _ = try await store.apply(candidate)
    #expect(await store.effectiveDenylist.blocks(Fixture.path("/System/Library/Kernels/kernel")))
  }
}

@Suite("Rule catalogue providing surface")
struct RuleCatalogProvidingSurfaceTests {

  private struct StaticCatalogProvider: RuleCatalogProviding {
    let catalog: RuleCatalog
    var current: RuleCatalog { catalog }
    func refreshFromChannel() async throws -> RuleCatalogUpdate { .alreadyCurrent }
  }

  @Test("a conforming provider serves its catalogue through current")
  func conformingProviderServesItsCatalogueThroughCurrent() async throws {
    let catalog = try makeSignedCatalog()
    let provider: any RuleCatalogProviding = StaticCatalogProvider(catalog: catalog)
    #expect(await provider.current == catalog)
  }

  @Test("update outcomes compare by their versions")
  func updateOutcomesCompareByTheirVersions() {
    let one = RuleCatalogVersion(value: 1)
    let two = RuleCatalogVersion(value: 2)
    #expect(RuleCatalogUpdate.updated(from: one, to: two) == .updated(from: one, to: two))
    #expect(RuleCatalogUpdate.updated(from: one, to: two) != .alreadyCurrent)
  }
}
