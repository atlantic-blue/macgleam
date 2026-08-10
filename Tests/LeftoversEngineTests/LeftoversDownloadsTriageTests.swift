import Foundation
import GleamCore
import LeftoversEngine
import Testing

/// C21 lists downloads triage as a LeftoversEngine concern and C5 gives the
/// category; neither states a grouping scheme. The suite therefore pins
/// only the shape any grouping must have: the Downloads folder is covered
/// completely, groups partition it, never reach outside it, and account
/// their bytes per C5.
@Suite("Leftovers scan: downloads triage")
struct LeftoversDownloadsTriageTests {

  @Test(
    "every file directly in the Downloads folder appears in exactly one downloads triage finding")
  func downloadsFilesArePartitionedAcrossTriageFindings() async throws {
    let fileSystem = await LeftoversTree.seeded()
    let outcome = try await runLeftoversScan(rules: LeftoversTree.catalog(), over: fileSystem)

    let triageFindings = outcome.findings(in: .downloadsTriage)
    #expect(!triageFindings.isEmpty)
    var coverage: [AbsolutePath: Int] = [:]
    for finding in triageFindings {
      for path in finding.paths {
        coverage[path, default: 0] += 1
      }
    }
    for downloadsFile in LeftoversTree.downloadsPaths {
      #expect(coverage[downloadsFile] == 1)
    }
  }

  @Test("downloads triage findings never reach outside the Downloads folder")
  func triageFindingsNeverReachOutsideDownloads() async throws {
    let fileSystem = await LeftoversTree.seeded()
    let outcome = try await runLeftoversScan(rules: LeftoversTree.catalog(), over: fileSystem)

    for finding in outcome.findings(in: .downloadsTriage) {
      #expect(!finding.paths.isEmpty)
      for path in finding.paths {
        #expect(path.isDescendant(of: LeftoversFixture.downloadsFolder))
      }
    }
  }

  @Test("a downloads triage finding's byte size is the allocated total of its grouped paths")
  func triageByteSizeIsTheAllocatedTotalOfItsPaths() async throws {
    let fileSystem = await LeftoversTree.seeded()
    let outcome = try await runLeftoversScan(rules: LeftoversTree.catalog(), over: fileSystem)

    let triageFindings = outcome.findings(in: .downloadsTriage)
    #expect(!triageFindings.isEmpty)
    for finding in triageFindings {
      let allocated = try await allocatedByteTotal(of: finding.paths, on: fileSystem)
      #expect(finding.byteSize == allocated)
    }
  }

  @Test("every downloads triage finding carries a plain sentence explanation")
  func triageFindingsCarryAnExplanation() async throws {
    let fileSystem = await LeftoversTree.seeded()
    let outcome = try await runLeftoversScan(rules: LeftoversTree.catalog(), over: fileSystem)

    let triageFindings = outcome.findings(in: .downloadsTriage)
    #expect(!triageFindings.isEmpty)
    for finding in triageFindings {
      #expect(!finding.explanation.isEmpty)
    }
  }
}
