import Foundation
import GleamCore
import Testing

@Suite("AppInventoryEntry")
struct AppInventoryEntryTests {

  @Test("an entry is identified by its bundle identifier")
  func entryIsIdentifiedByBundleIdentifier() {
    let entry = makeAppInventoryEntry(bundleID: "com.example.app")
    #expect(entry.id == "com.example.app")
    #expect(entry.id == entry.bundleID)
  }

  @Test("an entry with no leftovers round trips losslessly")
  func entryWithNoLeftoversRoundTrips() throws {
    try expectLosslessRoundTrip(makeAppInventoryEntry(leftoverPaths: []))
  }

  @Test("an entry with every leftover kind round trips losslessly")
  func entryWithEveryLeftoverKindRoundTrips() throws {
    let leftovers = LeftoverPathTests.allKinds.map { kind in
      makeLeftoverPath(
        path: Fixture.path("/Users/test/Library/\(kind.rawValue)/com.example.app"),
        kind: kind
      )
    }
    try expectLosslessRoundTrip(makeAppInventoryEntry(leftoverPaths: leftovers))
  }
}

@Suite("LeftoverPath")
struct LeftoverPathTests {

  static let allKinds: [LeftoverPath.Kind] = [
    .preferences, .cache, .container, .applicationSupport, .launchAgent, .launchDaemon, .log,
  ]

  @Test("every leftover kind round trips losslessly", arguments: allKinds)
  func everyKindRoundTrips(kind: LeftoverPath.Kind) throws {
    try expectLosslessRoundTrip(makeLeftoverPath(kind: kind))
  }

  @Test("a zero byte leftover round trips losslessly")
  func zeroByteLeftoverRoundTrips() throws {
    try expectLosslessRoundTrip(makeLeftoverPath(byteSize: 0))
  }
}
