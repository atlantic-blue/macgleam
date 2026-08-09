import CleanupEngine
import Foundation
import GleamCore
import Testing

@Suite("Cleanup scan: rule driven discovery")
struct CleanupRuleDrivenDiscoveryTests {

  @Test("only paths matching a catalogue cleanup rule become findings")
  func onlyMatchingPathsBecomeFindings() async throws {
    let fileSystem = await JunkTree.seeded()
    let singleRuleCatalog = try makeSignedCleanupCatalog(cleanupRules: [
      makeRule(
        identifier: "user-caches",
        category: .userCache,
        patterns: ["/Users/*/Library/Caches/com.example.app/**"]
      )
    ])

    let outcome = try await runCleanupScan(rules: singleRuleCatalog, over: fileSystem)

    #expect(
      outcome.itemisedPaths == [
        CleanupFixture.path(JunkTree.userCacheState),
        CleanupFixture.path(JunkTree.userCacheThumb),
      ])
  }

  @Test("a path no cleanup rule covers is never a finding")
  func uncoveredPathsAreNeverFindings() async throws {
    let fileSystem = await JunkTree.seeded()
    let outcome = try await runCleanupScan(rules: JunkTree.catalog(), over: fileSystem)

    #expect(!outcome.itemisedPaths.contains(CleanupFixture.path(JunkTree.bystanderDocument)))
    #expect(!outcome.itemisedPaths.contains(CleanupFixture.path(JunkTree.bystanderPreferences)))
    #expect(!outcome.itemisedPaths.contains(CleanupFixture.path(JunkTree.bystanderBinary)))
  }
}

@Suite("Cleanup scan: denylist supremacy")
struct CleanupScanDenylistTests {

  @Test("a denylisted path is never yielded even when a cleanup rule matches it")
  func denylistedPathIsNeverYielded() async throws {
    let fileSystem = await JunkTree.seeded()
    let catalog = try makeSignedCleanupCatalog(
      cleanupRules: [
        makeRule(
          identifier: "user-caches",
          category: .userCache,
          patterns: ["/Users/*/Library/Caches/com.example.app/**"]
        )
      ],
      denylist: Denylist(patterns: [
        PathPattern(pattern: "/Users/test/Library/Caches/com.example.app/images")
      ])
    )

    let outcome = try await runCleanupScan(rules: catalog, over: fileSystem)

    #expect(!outcome.itemisedPaths.contains(CleanupFixture.path(JunkTree.userCacheThumb)))
    #expect(outcome.itemisedPaths.contains(CleanupFixture.path(JunkTree.userCacheState)))
  }
}

/// The catalogue is signed and verifies, yet marks risky rules as
/// preselectable. The engine must enforce the conjunction itself: preselected
/// only when the rule says preselectable AND the risk is safe.
struct PreselectionCase: Sendable, CustomTestStringConvertible {
  let label: String
  let category: FindingCategory
  let expectedRisk: RiskLevel
  let expectPreselected: Bool

  var testDescription: String { label }

  static let all: [PreselectionCase] = [
    PreselectionCase(
      label: "safe and preselectable is preselected",
      category: .userCache,
      expectedRisk: .safe,
      expectPreselected: true
    ),
    PreselectionCase(
      label: "review risk stays unselected even when marked preselectable",
      category: .log,
      expectedRisk: .review,
      expectPreselected: false
    ),
    PreselectionCase(
      label: "dangerous risk stays unselected even when marked preselectable",
      category: .applicationCache,
      expectedRisk: .dangerous,
      expectPreselected: false
    ),
    PreselectionCase(
      label: "safe but not preselectable stays unselected",
      category: .temporaryFile,
      expectedRisk: .safe,
      expectPreselected: false
    ),
  ]
}

@Suite("Cleanup scan: risk and preselection")
struct CleanupPreselectionTests {

  private func hostileCatalog() throws -> RuleCatalog {
    try makeSignedCleanupCatalog(cleanupRules: [
      makeRule(
        identifier: "user-caches",
        category: .userCache,
        patterns: ["/Users/*/Library/Caches/com.example.app/**"],
        risk: .safe,
        preselectable: true
      ),
      makeRule(
        identifier: "logs",
        category: .log,
        patterns: ["/Users/*/Library/Logs/**"],
        risk: .review,
        preselectable: true
      ),
      makeRule(
        identifier: "application-caches",
        category: .applicationCache,
        patterns: ["/Users/*/Library/Containers/com.example.app/Data/Library/Caches/**"],
        risk: .dangerous,
        preselectable: true
      ),
      makeRule(
        identifier: "temporary-files",
        category: .temporaryFile,
        patterns: ["/private/tmp/**"],
        risk: .safe,
        preselectable: false
      ),
    ])
  }

  @Test(
    "preselection is the conjunction of preselectable and safe, whatever the catalogue claims",
    arguments: PreselectionCase.all)
  func preselectionClampsToSafe(testCase: PreselectionCase) async throws {
    let fileSystem = await JunkTree.seeded()
    let outcome = try await runCleanupScan(rules: hostileCatalog(), over: fileSystem)

    let categoryFindings = outcome.findings(in: testCase.category)
    #expect(!categoryFindings.isEmpty)
    for finding in categoryFindings {
      #expect(finding.risk == testCase.expectedRisk)
      #expect(finding.isPreselected == testCase.expectPreselected)
    }
  }
}
