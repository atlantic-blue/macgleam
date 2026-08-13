import Foundation
import GleamCore
import Testing

@Suite("AbsolutePath validation")
struct AbsolutePathValidationTests {

  @Test(
    "validating accepts a conforming path and preserves its value",
    arguments: ["/", "/Library", "/Library/Caches", "/Users/test/Library/Application Support"]
  )
  func validatingAcceptsConformingPath(value: String) throws {
    let path = try #require(AbsolutePath(validating: value))
    #expect(path.value == value)
  }

  @Test(
    "validating returns nil for a non conforming string",
    arguments: [
      "",
      ".",
      "..",
      "Library",
      "relative/path",
      "/Library/",
      "//",
      "/Library//Caches",
      "/./Library",
      "/Library/./Caches",
      "/..",
      "/Library/..",
      "/Library/../Caches",
    ]
  )
  func validatingRejectsNonConformingString(value: String) {
    #expect(AbsolutePath(validating: value) == nil)
  }
}

@Suite("AbsolutePath normalisation")
struct AbsolutePathNormalisationTests {

  static let cases: [(input: String, expected: String)] = [
    ("/Library/", "/Library"),
    ("/Library/Caches/", "/Library/Caches"),
    ("/", "/"),
    ("//", "/"),
    ("///", "/"),
    ("/Library//Caches", "/Library/Caches"),
    ("/Library/./Caches", "/Library/Caches"),
    ("/./Library", "/Library"),
    ("/Library/Caches/../Logs", "/Library/Logs"),
    ("/..", "/"),
    ("/../Library", "/Library"),
    ("/a//b/./c/../d/", "/a/b/d"),
  ]

  @Test("normalising resolves slashes and dot segments", arguments: cases)
  func normalisingResolvesSlashesAndDotSegments(testCase: (input: String, expected: String)) {
    #expect(AbsolutePath(normalising: testCase.input).value == testCase.expected)
  }

  @Test(
    "normalising an already normal path is the identity",
    arguments: ["/", "/Library", "/Library/Caches"]
  )
  func normalisingIsIdentityOnNormalPaths(value: String) {
    #expect(AbsolutePath(normalising: value).value == value)
  }

  @Test(
    "normalised output always satisfies the path invariants",
    arguments: ["/a/../../b/", "/....//x", "/a/./././b//", "/../.."]
  )
  func normalisedOutputSatisfiesInvariants(input: String) {
    let value = AbsolutePath(normalising: input).value
    #expect(value.hasPrefix("/"))
    let components = value.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
    if value != "/" {
      #expect(!value.hasSuffix("/"))
      #expect(!components.contains(""))
    }
    #expect(!components.contains("."))
    #expect(!components.contains(".."))
  }
}

@Suite("AbsolutePath descendants")
struct AbsolutePathDescendantTests {

  @Test("a direct child is a descendant of its parent")
  func directChildIsDescendant() {
    let child = Fixture.path("/Library/Caches")
    #expect(child.isDescendant(of: Fixture.path("/Library")))
  }

  @Test("a deep path is a descendant of every ancestor")
  func deepPathIsDescendantOfEveryAncestor() {
    let deep = Fixture.path("/Library/Caches/com.example/Data")
    #expect(deep.isDescendant(of: Fixture.path("/Library")))
    #expect(deep.isDescendant(of: Fixture.path("/Library/Caches")))
    #expect(deep.isDescendant(of: Fixture.path("/Library/Caches/com.example")))
  }

  @Test("a path is not a descendant of itself")
  func pathIsNotItsOwnDescendant() {
    let path = Fixture.path("/Library")
    #expect(!path.isDescendant(of: path))
  }

  @Test("descendant checks compare components, not characters")
  func descendantCheckIsComponentwise() {
    #expect(!Fixture.path("/Library/App").isDescendant(of: Fixture.path("/Library/Ap")))
    #expect(!Fixture.path("/LibraryCache").isDescendant(of: Fixture.path("/Library")))
  }

  @Test("every non root path is a descendant of the root")
  func everyNonRootPathIsDescendantOfRoot() {
    #expect(Fixture.path("/Library").isDescendant(of: Fixture.path("/")))
    #expect(Fixture.path("/Library/Caches/deep").isDescendant(of: Fixture.path("/")))
  }

  @Test("the root is not a descendant of itself")
  func rootIsNotDescendantOfItself() {
    #expect(!Fixture.path("/").isDescendant(of: Fixture.path("/")))
  }

  @Test("an ancestor is not a descendant of its child")
  func ancestorIsNotDescendantOfChild() {
    #expect(!Fixture.path("/Library").isDescendant(of: Fixture.path("/Library/Caches")))
    #expect(!Fixture.path("/").isDescendant(of: Fixture.path("/Library")))
  }

  @Test("a sibling is not a descendant")
  func siblingIsNotDescendant() {
    #expect(!Fixture.path("/Library/Logs").isDescendant(of: Fixture.path("/Library/Caches")))
  }
}

@Suite("AbsolutePath ordering and identity")
struct AbsolutePathOrderingTests {

  @Test("ordering is lexicographic on the path string")
  func orderingIsLexicographic() {
    #expect(Fixture.path("/a") < Fixture.path("/b"))
    #expect(Fixture.path("/Library") < Fixture.path("/Library/Caches"))
    #expect(!(Fixture.path("/b") < Fixture.path("/a")))
    #expect(!(Fixture.path("/a") < Fixture.path("/a")))
  }

  @Test("sorting paths matches sorting their string values")
  func sortingMatchesStringSorting() {
    let values = ["/b", "/a/c", "/a", "/Library", "/"]
    let sorted = values.map(Fixture.path).sorted().map(\.value)
    #expect(sorted == values.sorted())
  }

  @Test("paths with the same value are equal and hash together")
  func equalPathsHashTogether() {
    let set = Set([Fixture.path("/Library/Caches"), Fixture.path("/Library/Caches/")])
    #expect(set.count == 1)
  }

  @Test("paths with different values are not equal")
  func differentPathsAreNotEqual() {
    #expect(Fixture.path("/Library") != Fixture.path("/Library/Caches"))
  }

  @Test("lastComponent is the final path component")
  func lastComponentIsFinalComponent() {
    #expect(Fixture.path("/Library/Caches").lastComponent == "Caches")
    #expect(Fixture.path("/Library").lastComponent == "Library")
  }
}

@Suite("AbsolutePath coding")
struct AbsolutePathCodingTests {

  @Test("encodes as a plain string")
  func encodesAsPlainString() throws {
    let encoded = try JSONEncoder().encode([Fixture.path("/Library/Caches")])
    let asStrings = try JSONEncoder().encode(["/Library/Caches"])
    #expect(encoded == asStrings)
  }

  @Test("decodes from a plain string")
  func decodesFromPlainString() throws {
    let data = try JSONEncoder().encode(["/Library/Caches"])
    let decoded = try JSONDecoder().decode([AbsolutePath].self, from: data)
    #expect(decoded == [Fixture.path("/Library/Caches")])
  }

  @Test("round trips losslessly", arguments: ["/", "/Library", "/Users/test/Library Caches x"])
  func roundTripsLosslessly(value: String) throws {
    try expectLosslessRoundTrip(Fixture.path(value))
  }

  @Test(
    "decoding a non conforming string fails rather than normalising silently",
    arguments: ["/Library/", "/Library//Caches", "relative", "/a/../b"]
  )
  func decodingNonConformingStringFails(value: String) throws {
    let data = try JSONEncoder().encode([value])
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode([AbsolutePath].self, from: data)
    }
  }
}

@Suite("AbsolutePath direct children")
struct AbsolutePathChildTests {

  @Test("a file directly inside a folder is its child")
  func aFileDirectlyInsideIsAChild() {
    #expect(Fixture.path("/Users/ada/Downloads/report.pdf").isChild(of: downloads))
  }

  @Test("a file in a subfolder is not a child")
  func aFileDeeperDownIsNotAChild() {
    #expect(
      !Fixture.path("/Users/ada/Downloads/invoices/2026.pdf").isChild(of: downloads),
      "a triage of the Downloads folder is about what sits loose in it")
  }

  @Test("the folder is not its own child")
  func theFolderIsNotItsOwnChild() {
    #expect(!downloads.isChild(of: downloads))
  }

  @Test("a sibling folder that shares a prefix is not a child")
  func aSharedPrefixIsNotAChild() {
    #expect(!Fixture.path("/Users/ada/DownloadsOld/report.pdf").isChild(of: downloads))
    #expect(!Fixture.path("/Users/ada/Down/report.pdf").isChild(of: downloads))
  }

  @Test("an ancestor is not a child")
  func anAncestorIsNotAChild() {
    #expect(!Fixture.path("/Users/ada").isChild(of: downloads))
  }

  @Test("a folder at the root is a child of the root")
  func aFolderAtTheRootIsAChildOfTheRoot() {
    #expect(Fixture.path("/Applications").isChild(of: Fixture.path("/")))
    #expect(!Fixture.path("/Applications/Safari.app").isChild(of: Fixture.path("/")))
    #expect(!Fixture.path("/").isChild(of: Fixture.path("/")))
  }

  private let downloads = Fixture.path("/Users/ada/Downloads")
}
