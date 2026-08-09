import ClutterEngine
import Foundation
import GleamCore
import Testing

@Suite("Duplicate scan session mechanics")
struct DuplicatesSessionMechanicsTests {

  @Test(
    "duplicate findings ride the scan session with advancing phases and counters that only count up"
  )
  func duplicateFindingsRideSessionGuarantees() async throws {
    let sessionID = UUID()
    let content = duplicatesContent(byte: 0x35)
    let files = [
      duplicatesFile("Documents/session one.bin", content: content),
      duplicatesFile("Pictures/session two.bin", content: content),
    ]
    let outcome = try await duplicatesRunScan(
      context: duplicatesScanContext(sessionID: sessionID, files: files)
    )

    let sets = duplicatesSetFindings(in: outcome)
    #expect(!sets.isEmpty)
    for set in sets {
      #expect(set.sessionID == sessionID)
    }

    let ranks = outcome.phases.map(duplicatesPhaseRank)
    #expect(ranks == ranks.sorted())

    var previous = ScanCounters.zero
    for snapshot in outcome.counters {
      #expect(snapshot.filesSeen >= previous.filesSeen)
      #expect(snapshot.bytesReclaimable >= previous.bytesReclaimable)
      #expect(snapshot.findingCount >= previous.findingCount)
      previous = snapshot
    }
  }
}
