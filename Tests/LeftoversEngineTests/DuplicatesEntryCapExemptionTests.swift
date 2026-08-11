import Foundation
import GleamCore
import LeftoversEngine
import Testing

/// C21: set shaped categories are the one exemption from C15's entry cap. A
/// split set would leave members in a finding whose category names a kept copy
/// it does not contain, so the set stays whole however many members it has.
@Suite("Duplicate sets are exempt from the entry cap")
struct DuplicatesEntryCapExemptionTests {

  /// C15's contracted cap of 2,000 plus 100, written out rather than derived
  /// from `ScanStreamPolicy.maximumFindingEntries`. A fixture sized off the
  /// constant grows with it, so the set would stay over the cap for any value
  /// of the cap and the exemption would have no test that can fail.
  /// `ScanStreamPolicyValueTests` pins the constant to 2,000; the coherence
  /// check below is what ties this fixture to it.
  static let membersOverTheCap = 2_100

  @Test("the fixture really does exceed the entry cap it claims to be exempt from")
  func theFixtureExceedsTheEntryCap() {
    #expect(Self.membersOverTheCap > ScanStreamPolicy.maximumFindingEntries)
  }

  @Test("a duplicate set larger than the entry cap stays one finding")
  func aSetLargerThanTheCapStaysOneFinding() async throws {
    let outcome = try await duplicatesRunScan(
      context: duplicatesScanContext(files: Self.identicalCopies())
    )

    let sets = duplicatesSetFindings(in: outcome)
    #expect(sets.count == 1)
    let set = try #require(sets.first)
    #expect(set.entries.count == Self.membersOverTheCap)
    #expect(set.entries.count > ScanStreamPolicy.maximumFindingEntries)
  }

  @Test("the kept path of an oversized set is a member of that set's own paths")
  func theKeptPathOfAnOversizedSetIsAMember() async throws {
    let outcome = try await duplicatesRunScan(
      context: duplicatesScanContext(files: Self.identicalCopies())
    )

    let set = try #require(duplicatesSetFindings(in: outcome).first)
    let kept = try #require(duplicatesKeptPath(of: set))
    #expect(set.paths.contains(kept))
  }

  private static func identicalCopies() -> [DuplicatesFakeFile] {
    let content = duplicatesContent(byte: 0x5D)
    return (0..<membersOverTheCap).map { index in
      duplicatesFile(
        "Documents/copies/" + String(format: "copy-%05d.bin", index),
        content: content
      )
    }
  }
}
