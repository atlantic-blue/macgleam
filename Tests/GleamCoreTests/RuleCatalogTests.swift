import Foundation
import GleamCore
import Testing

@Suite("PathPattern literal matching")
struct PathPatternLiteralTests {

  @Test("a literal pattern matches exactly its path")
  func literalPatternMatchesItsPath() {
    let pattern = PathPattern(pattern: "/Library/Caches")
    #expect(pattern.matches(Fixture.path("/Library/Caches")))
  }

  @Test("a literal pattern does not match a different path")
  func literalPatternDoesNotMatchDifferentPath() {
    let pattern = PathPattern(pattern: "/Library/Caches")
    #expect(!pattern.matches(Fixture.path("/Library/Logs")))
    #expect(!pattern.matches(Fixture.path("/Library")))
  }

  @Test("a literal pattern does not match descendants of its path")
  func literalPatternDoesNotMatchDescendants() {
    let pattern = PathPattern(pattern: "/Library/Caches")
    #expect(!pattern.matches(Fixture.path("/Library/Caches/com.example")))
  }

  @Test("a literal pattern does not match a sibling that shares a character prefix")
  func literalPatternDoesNotMatchSiblingPrefix() {
    let pattern = PathPattern(pattern: "/Library")
    #expect(!pattern.matches(Fixture.path("/LibraryCache")))
  }

  @Test("the root pattern matches the root")
  func rootPatternMatchesRoot() {
    #expect(PathPattern(pattern: "/").matches(Fixture.path("/")))
  }
}

@Suite("PathPattern single component wildcard")
struct PathPatternSingleWildcardTests {

  static let userLibrary = PathPattern(pattern: "/Users/*/Library")

  @Test("the wildcard matches any single component")
  func wildcardMatchesAnySingleComponent() {
    #expect(Self.userLibrary.matches(Fixture.path("/Users/julian/Library")))
    #expect(Self.userLibrary.matches(Fixture.path("/Users/guest/Library")))
  }

  @Test("the wildcard consumes exactly one component, never zero")
  func wildcardConsumesExactlyOneComponentNeverZero() {
    #expect(!Self.userLibrary.matches(Fixture.path("/Users/Library")))
  }

  @Test("the wildcard consumes exactly one component, never two")
  func wildcardConsumesExactlyOneComponentNeverTwo() {
    #expect(!Self.userLibrary.matches(Fixture.path("/Users/julian/extra/Library")))
  }

  @Test("a wildcard match still requires the trailing literals")
  func wildcardMatchStillRequiresTrailingLiterals() {
    #expect(!Self.userLibrary.matches(Fixture.path("/Users/julian/Documents")))
    #expect(!Self.userLibrary.matches(Fixture.path("/Users/julian/Library/Caches")))
  }

  @Test("a trailing single wildcard does not reach into subdirectories")
  func trailingSingleWildcardDoesNotReachIntoSubdirectories() {
    let pattern = PathPattern(pattern: "/Users/*")
    #expect(pattern.matches(Fixture.path("/Users/julian")))
    #expect(!pattern.matches(Fixture.path("/Users/julian/Library")))
    #expect(!pattern.matches(Fixture.path("/Users")))
  }
}

@Suite("PathPattern trailing subtree wildcard")
struct PathPatternSubtreeWildcardTests {

  static let systemSubtree = PathPattern(pattern: "/System/**")

  @Test("the subtree wildcard matches a direct child")
  func subtreeWildcardMatchesDirectChild() {
    #expect(Self.systemSubtree.matches(Fixture.path("/System/Library")))
  }

  @Test("the subtree wildcard matches at any depth")
  func subtreeWildcardMatchesAtAnyDepth() {
    #expect(Self.systemSubtree.matches(Fixture.path("/System/Library/Kernels/kernel")))
  }

  @Test("the subtree wildcard respects component boundaries")
  func subtreeWildcardRespectsComponentBoundaries() {
    #expect(!Self.systemSubtree.matches(Fixture.path("/SystemFiles/Library")))
    #expect(!Self.systemSubtree.matches(Fixture.path("/Sys")))
  }

  @Test("a pattern round trips losslessly")
  func patternRoundTripsLosslessly() throws {
    try expectLosslessRoundTrip(Self.systemSubtree)
    try expectLosslessRoundTrip(PathPattern(pattern: "/Users/*/Library"))
  }
}

@Suite("Denylist blocking")
struct DenylistBlockingTests {

  @Test("an empty denylist blocks nothing")
  func emptyDenylistBlocksNothing() {
    let denylist = makeDenylist([])
    #expect(!denylist.blocks(Fixture.path("/System")))
    #expect(!denylist.blocks(Fixture.path("/")))
  }

  @Test("an exact pattern blocks its path")
  func exactPatternBlocksItsPath() {
    let denylist = makeDenylist(["/System"])
    #expect(denylist.blocks(Fixture.path("/System")))
  }

  @Test("a denylisted directory blocks every descendant")
  func denylistedDirectoryBlocksEveryDescendant() {
    let denylist = makeDenylist(["/System"])
    #expect(denylist.blocks(Fixture.path("/System/Library")))
    #expect(denylist.blocks(Fixture.path("/System/Library/CoreServices/Finder.app")))
  }

  @Test("a denylisted directory does not block a sibling sharing a character prefix")
  func denylistedDirectoryDoesNotBlockSiblingPrefix() {
    let denylist = makeDenylist(["/Library"])
    #expect(!denylist.blocks(Fixture.path("/LibraryCache")))
    #expect(!denylist.blocks(Fixture.path("/LibraryCache/store")))
  }

  @Test("a denylisted directory does not block its own ancestors")
  func denylistedDirectoryDoesNotBlockAncestors() {
    let denylist = makeDenylist(["/Library/Caches"])
    #expect(!denylist.blocks(Fixture.path("/Library")))
    #expect(!denylist.blocks(Fixture.path("/")))
  }

  @Test("a denylisted directory does not block unrelated siblings")
  func denylistedDirectoryDoesNotBlockUnrelatedSiblings() {
    let denylist = makeDenylist(["/Library/Caches"])
    #expect(!denylist.blocks(Fixture.path("/Library/Logs")))
  }

  @Test("a directory matched through a wildcard blocks its descendants")
  func wildcardMatchedDirectoryBlocksDescendants() {
    let denylist = makeDenylist(["/Users/*/Library"])
    #expect(denylist.blocks(Fixture.path("/Users/julian/Library")))
    #expect(denylist.blocks(Fixture.path("/Users/julian/Library/Preferences/com.a.plist")))
    #expect(!denylist.blocks(Fixture.path("/Users/julian/Documents")))
  }

  @Test("a subtree wildcard pattern blocks deep descendants")
  func subtreeWildcardPatternBlocksDeepDescendants() {
    let denylist = makeDenylist(["/System/**"])
    #expect(denylist.blocks(Fixture.path("/System/Library/Kernels/kernel")))
    #expect(!denylist.blocks(Fixture.path("/SystemFiles")))
  }

  @Test("denylisting the root blocks every path")
  func denylistingRootBlocksEveryPath() {
    let denylist = makeDenylist(["/"])
    #expect(denylist.blocks(Fixture.path("/")))
    #expect(denylist.blocks(Fixture.path("/Users/julian/anything")))
  }

  @Test("any pattern in the list is enough to block")
  func anyPatternInListIsEnoughToBlock() {
    let denylist = makeDenylist(["/System", "/Library", "/usr"])
    #expect(denylist.blocks(Fixture.path("/Library/Caches")))
    #expect(denylist.blocks(Fixture.path("/usr/bin/ls")))
    #expect(!denylist.blocks(Fixture.path("/Applications")))
  }

  @Test("a denylist round trips losslessly")
  func denylistRoundTripsLosslessly() throws {
    try expectLosslessRoundTrip(makeDenylist(["/System", "/Users/*/Library", "/private/**"]))
  }
}

@Suite("RuleCatalogVersion")
struct RuleCatalogVersionTests {

  @Test("versions order by their numeric value")
  func versionsOrderByNumericValue() {
    #expect(RuleCatalogVersion(value: 1) < RuleCatalogVersion(value: 2))
    #expect(!(RuleCatalogVersion(value: 2) < RuleCatalogVersion(value: 1)))
    #expect(!(RuleCatalogVersion(value: 2) < RuleCatalogVersion(value: 2)))
  }

  @Test("equal versions are equal")
  func equalVersionsAreEqual() {
    #expect(RuleCatalogVersion(value: 7) == RuleCatalogVersion(value: 7))
    #expect(RuleCatalogVersion(value: 7) != RuleCatalogVersion(value: 8))
  }

  @Test("a version round trips losslessly at the extremes")
  func versionRoundTripsAtExtremes() throws {
    try expectLosslessRoundTrip(RuleCatalogVersion(value: 0))
    try expectLosslessRoundTrip(RuleCatalogVersion(value: UInt32.max))
  }
}

@Suite("RuleCatalog coding")
struct RuleCatalogCodingTests {

  @Test("a fully populated catalogue round trips losslessly")
  func fullyPopulatedCatalogueRoundTrips() throws {
    let catalog = makeRuleCatalog(
      cleanupRules: [
        makeCleanupRule(),
        makeCleanupRule(
          identifier: "external-trash",
          category: .trashBin(volume: Fixture.path("/Volumes/External")),
          patterns: ["/Volumes/*/.Trashes"],
          risk: .review,
          preselectable: false
        ),
      ],
      adwareRules: AdwareRuleCodingTests.allKinds.map {
        makeAdwareRule(identifier: "adware-\($0.rawValue)", kind: $0)
      },
      denylist: makeDenylist(["/System", "/usr", "/bin"])
    )
    try expectLosslessRoundTrip(catalog)
  }

  @Test("a catalogue with empty rule sets round trips losslessly")
  func emptyCatalogueRoundTrips() throws {
    let catalog = makeRuleCatalog(
      cleanupRules: [],
      adwareRules: [],
      denylist: makeDenylist([])
    )
    try expectLosslessRoundTrip(catalog)
  }

  @Test("signature bytes survive coding exactly")
  func signatureBytesSurviveCoding() throws {
    let catalog = makeRuleCatalog()
    let encoded = try JSONEncoder().encode(catalog)
    let decoded = try JSONDecoder().decode(RuleCatalog.self, from: encoded)
    #expect(decoded.signature == Fixture.signatureBytes)
  }

  @Test("a cleanup rule round trips losslessly")
  func cleanupRuleRoundTrips() throws {
    try expectLosslessRoundTrip(makeCleanupRule())
  }
}

@Suite("AdwareRule coding")
struct AdwareRuleCodingTests {

  static let allKinds: [AdwareRule.Kind] = [
    .launchAgent, .launchDaemon, .browserExtension, .applicationPath,
  ]

  @Test("every adware rule kind round trips losslessly", arguments: allKinds)
  func everyKindRoundTrips(kind: AdwareRule.Kind) throws {
    try expectLosslessRoundTrip(makeAdwareRule(kind: kind))
  }
}
