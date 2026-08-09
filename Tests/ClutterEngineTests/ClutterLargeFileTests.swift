import ClutterEngine
import Foundation
import GleamCore
import Testing

@Suite("Clutter scan: large files")
struct ClutterLargeFileTests {

  @Test(
    "a file exactly at the settings threshold is a large file finding itemising its path and allocated size"
  )
  func fileExactlyAtThresholdIsAFinding() async throws {
    let fileSystem = await ClutterTree.seeded()
    let outcome = try await runClutterScan(rules: ClutterTree.catalog(), over: fileSystem)

    let largeFindings = outcome.findings(in: .largeFile)
    let target = ClutterFixture.path(ClutterTree.largeExactlyAtThreshold)
    let finding = try #require(largeFindings.first { $0.paths.contains(target) })
    #expect(finding.paths == [target])
    #expect(finding.byteSize == ClutterTree.largeThresholdBytes)
    #expect(!finding.explanation.isEmpty)
    #expect(finding.sessionID == ClutterFixture.sessionID)
  }

  @Test("a file one byte under the threshold is not a large file finding")
  func fileOneByteUnderThresholdIsNotAFinding() async throws {
    let fileSystem = await ClutterTree.seeded()
    let outcome = try await runClutterScan(rules: ClutterTree.catalog(), over: fileSystem)

    let underThreshold = ClutterFixture.path(ClutterTree.largeOneByteUnder)
    #expect(
      outcome.findings(in: .largeFile).allSatisfy { !$0.paths.contains(underThreshold) })
  }

  @Test("allocated bytes decide the threshold, not the logical content length")
  func allocatedBytesDecideNotLogicalLength() async throws {
    let tinyContentLargeOnDisk = "/Users/test/Documents/sparse-but-allocated.dat"
    let largeContentSmallOnDisk = "/Users/test/Documents/compressed-on-disk.dat"
    let backing = await makeSeededFileSystem([
      SeededClutterFile(path: tinyContentLargeOnDisk, length: 10),
      SeededClutterFile(
        path: largeContentSmallOnDisk, length: Int(ClutterTree.largeThresholdBytes)),
    ])
    let pinning = AllocationPinningFileSystem(
      backing: backing,
      allocatedBytesByPath: [
        ClutterFixture.path(tinyContentLargeOnDisk): ClutterTree.largeThresholdBytes,
        ClutterFixture.path(largeContentSmallOnDisk): ClutterTree.largeThresholdBytes - 1,
      ]
    )
    let context = makeScanContext(fileSystem: pinning, rules: try ClutterTree.catalog())

    let outcome = try await collectScan(makeClutterEngine().scan(context))

    let largePathSets = outcome.pathSets(in: .largeFile)
    #expect(largePathSets.contains([ClutterFixture.path(tinyContentLargeOnDisk)]))
    #expect(!outcome.itemisedPaths.contains(ClutterFixture.path(largeContentSmallOnDisk)))
    let finding = try #require(
      outcome.findings(in: .largeFile).first {
        $0.paths == [ClutterFixture.path(tinyContentLargeOnDisk)]
      })
    #expect(finding.byteSize == ClutterTree.largeThresholdBytes)
  }

  @Test("no finding of any category references a path outside the user home")
  func noFindingReferencesAPathOutsideTheUserHome() async throws {
    let fileSystem = await ClutterTree.seeded()
    let outcome = try await runClutterScan(rules: ClutterTree.catalog(), over: fileSystem)

    #expect(!outcome.findings.isEmpty)
    let outside = ClutterFixture.path(ClutterTree.outsideHomeLargeAndOld)
    for finding in outcome.findings {
      for path in finding.paths {
        #expect(path.isDescendant(of: ClutterFixture.userHome))
      }
    }
    #expect(!outcome.itemisedPaths.contains(outside))
  }

  @Test("a denylisted file is never a finding however large and old it is")
  func denylistedFileIsNeverAFinding() async throws {
    let fileSystem = await ClutterTree.seeded()
    let outcome = try await runClutterScan(rules: ClutterTree.catalog(), over: fileSystem)

    let denylisted = ClutterFixture.path(ClutterTree.denylistedLargeAndOld)
    #expect(!outcome.itemisedPaths.contains(denylisted))
  }
}
