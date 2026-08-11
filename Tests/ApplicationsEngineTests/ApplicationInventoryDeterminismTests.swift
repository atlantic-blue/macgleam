import ApplicationsEngine
import Foundation
import GleamCore
import Testing

/// C15: running a scan twice against the same file system state yields the
/// same answer. C13 promises nothing about enumeration order, so an inventory
/// that hands paths back in the order the disk happened to give them is a
/// list that reorders itself between two runs on the same machine. The order
/// is therefore the engine's to decide and its own to hold still, which is
/// what these tests pin.
@Suite("Applications inventory: determinism")
struct ApplicationInventoryDeterminismTests {

  @Test("two inventories over the same disk are identical")
  func twoInventoriesAreIdentical() async throws {
    let fileSystem = try await ApplicationWorld.seeded()

    let (first, _) = try await runInventory(over: fileSystem)
    let (second, _) = try await runInventory(over: fileSystem)
    expectCompleteInventory(first)

    #expect(first == second)
  }

  @Test("applications come back ordered by bundle identifier")
  func applicationsAreOrderedByBundleIdentifier() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    #expect(entries.map(\.bundleID) == entries.map(\.bundleID).sorted())
  }

  @Test("each application's leftovers come back ordered by path")
  func leftoversAreOrderedByPath() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    for entry in entries {
      let paths = entry.leftoverPaths.map(\.path)
      #expect(paths == paths.sorted(), "\(entry.bundleID) listed its leftovers out of order")
    }
  }

  @Test("no application is listed twice")
  func noApplicationIsListedTwice() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    #expect(Set(entries.map(\.bundleID)).count == entries.count)
  }

  @Test("no leftover is listed twice within one application")
  func noLeftoverIsListedTwiceWithinOneApplication() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    for entry in entries {
      #expect(
        Set(entry.leftoverPaths.map(\.path)).count == entry.leftoverPaths.count,
        "\(entry.bundleID) listed a leftover twice")
    }
  }

  @Test("two scans of the same disk find the same entries, identifiers aside")
  func twoScansFindTheSameEntries() async throws {
    let fileSystem = try await ApplicationWorld.seeded()

    let first = try await runApplicationsScan(over: fileSystem)
    let second = try await runApplicationsScan(over: fileSystem)
    expectCompleteScan(first)

    #expect(first.everyEntryPath == second.everyEntryPath)
    #expect(first.offeredBundleIDs == second.offeredBundleIDs)
    #expect(first.reclaimableByteTotal == second.reclaimableByteTotal)
    for bundleID in first.offeredBundleIDs {
      #expect(
        first.entryPaths(ofLeftoversFor: bundleID) == second.entryPaths(ofLeftoversFor: bundleID))
    }
  }

  @Test("each finding's entries are ordered by path")
  func findingEntriesAreOrderedByPath() async throws {
    let outcome = try await runApplicationsScan()
    expectCompleteScan(outcome)

    for finding in outcome.findings {
      let paths = finding.entries.map(\.path)
      #expect(paths == paths.sorted(), "a finding listed its entries out of order")
    }
  }
}
