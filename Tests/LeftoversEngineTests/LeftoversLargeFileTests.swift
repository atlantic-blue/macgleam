import Foundation
import GleamCore
import LeftoversEngine
import Testing

@Suite("Leftovers scan: large files")
struct LeftoversLargeFileTests {

  @Test(
    "a file exactly at the settings threshold is a large file finding itemising its path and allocated size"
  )
  func fileExactlyAtThresholdIsAFinding() async throws {
    let fileSystem = await LeftoversTree.seeded()
    let outcome = try await runLeftoversScan(rules: LeftoversTree.catalog(), over: fileSystem)

    let largeFindings = outcome.findings(in: .largeFile)
    let target = LeftoversFixture.path(LeftoversTree.largeExactlyAtThreshold)
    let finding = try #require(largeFindings.first { $0.paths.contains(target) })
    #expect(finding.paths == [target])
    #expect(finding.byteSize == LeftoversTree.largeThresholdBytes)
    #expect(!finding.explanation.isEmpty)
    #expect(finding.sessionID == LeftoversFixture.sessionID)
  }

  @Test("a file one byte under the threshold is not a large file finding")
  func fileOneByteUnderThresholdIsNotAFinding() async throws {
    let fileSystem = await LeftoversTree.seeded()
    let outcome = try await runLeftoversScan(rules: LeftoversTree.catalog(), over: fileSystem)

    let underThreshold = LeftoversFixture.path(LeftoversTree.largeOneByteUnder)
    #expect(
      outcome.findings(in: .largeFile).allSatisfy { !$0.paths.contains(underThreshold) })
  }

  @Test("allocated bytes decide the threshold, not the logical content length")
  func allocatedBytesDecideNotLogicalLength() async throws {
    let tinyContentLargeOnDisk = "/Users/test/Documents/sparse-but-allocated.dat"
    let largeContentSmallOnDisk = "/Users/test/Documents/compressed-on-disk.dat"
    let backing = await makeSeededFileSystem([
      SeededLeftoversFile(path: tinyContentLargeOnDisk, length: 10),
      SeededLeftoversFile(
        path: largeContentSmallOnDisk, length: Int(LeftoversTree.largeThresholdBytes)),
    ])
    let pinning = AllocationPinningFileSystem(
      backing: backing,
      allocatedBytesByPath: [
        LeftoversFixture.path(tinyContentLargeOnDisk): LeftoversTree.largeThresholdBytes,
        LeftoversFixture.path(largeContentSmallOnDisk): LeftoversTree.largeThresholdBytes - 1,
      ]
    )
    let context = makeScanContext(fileSystem: pinning, rules: try LeftoversTree.catalog())

    let outcome = try await collectScan(makeLeftoversEngine().scan(context))

    let largePathSets = outcome.pathSets(in: .largeFile)
    #expect(largePathSets.contains([LeftoversFixture.path(tinyContentLargeOnDisk)]))
    #expect(!outcome.itemisedPaths.contains(LeftoversFixture.path(largeContentSmallOnDisk)))
    let finding = try #require(
      outcome.findings(in: .largeFile).first {
        $0.paths == [LeftoversFixture.path(tinyContentLargeOnDisk)]
      })
    #expect(finding.byteSize == LeftoversTree.largeThresholdBytes)
  }

  @Test("no finding of any category references a path outside the user home")
  func noFindingReferencesAPathOutsideTheUserHome() async throws {
    let fileSystem = await LeftoversTree.seeded()
    let outcome = try await runLeftoversScan(rules: LeftoversTree.catalog(), over: fileSystem)

    #expect(!outcome.findings.isEmpty)
    let outside = LeftoversFixture.path(LeftoversTree.outsideHomeLargeAndOld)
    for finding in outcome.findings {
      for path in finding.paths {
        #expect(path.isDescendant(of: LeftoversFixture.userHome))
      }
    }
    #expect(!outcome.itemisedPaths.contains(outside))
  }

  @Test("a denylisted file is never a finding however large and old it is")
  func denylistedFileIsNeverAFinding() async throws {
    let fileSystem = await LeftoversTree.seeded()
    let outcome = try await runLeftoversScan(rules: LeftoversTree.catalog(), over: fileSystem)

    let denylisted = LeftoversFixture.path(LeftoversTree.denylistedLargeAndOld)
    #expect(!outcome.itemisedPaths.contains(denylisted))
  }
}
