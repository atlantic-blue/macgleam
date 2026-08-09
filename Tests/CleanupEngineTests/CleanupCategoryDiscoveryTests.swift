import CleanupEngine
import Foundation
import GleamCore
import Testing

/// One seeded example of every C20 junk category, and what its findings must
/// itemise. Byte totals are asserted against the file system's own allocated
/// figures, never against logical lengths.
struct CategoryExpectation: Sendable, CustomTestStringConvertible {
  let label: String
  let category: FindingCategory
  let paths: [String]

  var testDescription: String { label }

  var absolutePaths: [AbsolutePath] { paths.map(CleanupFixture.path) }

  static let all: [CategoryExpectation] = [
    CategoryExpectation(
      label: "user caches",
      category: .userCache,
      paths: [JunkTree.userCacheState, JunkTree.userCacheThumb]
    ),
    CategoryExpectation(
      label: "application caches",
      category: .applicationCache,
      paths: [JunkTree.applicationCacheBlob]
    ),
    CategoryExpectation(
      label: "logs",
      category: .log,
      paths: [JunkTree.sessionLog]
    ),
    CategoryExpectation(
      label: "broken downloads",
      category: .brokenDownload,
      paths: [JunkTree.brokenDownload]
    ),
    CategoryExpectation(
      label: "Xcode derived data",
      category: .xcodeDerivedData,
      paths: [JunkTree.derivedDataObject]
    ),
    CategoryExpectation(
      label: "simulator caches",
      category: .simulatorCache,
      paths: [JunkTree.simulatorCacheBlob]
    ),
    CategoryExpectation(
      label: "browser caches",
      category: .browserCache,
      paths: [JunkTree.browserCacheDatabase]
    ),
    CategoryExpectation(
      label: "temporary files",
      category: .temporaryFile,
      paths: [JunkTree.temporaryScratch]
    ),
    CategoryExpectation(
      label: "mail attachment local copies",
      category: .mailAttachmentLocalCopy,
      paths: [JunkTree.mailAttachment]
    ),
    CategoryExpectation(
      label: "the boot volume trash bin",
      category: .trashBin(volume: CleanupFixture.path("/")),
      paths: [JunkTree.homeTrashNote, JunkTree.homeTrashDraft]
    ),
    CategoryExpectation(
      label: "an external volume trash bin",
      category: .trashBin(volume: CleanupFixture.path("/Volumes/External")),
      paths: [JunkTree.externalTrashFile]
    ),
  ]
}

@Suite("Cleanup scan: category discovery")
struct CleanupCategoryDiscoveryTests {

  @Test(
    "each junk category is found with its exact seeded paths and allocated byte total",
    arguments: CategoryExpectation.all)
  func categoryIsFoundWithItemisedPathsAndBytes(expectation: CategoryExpectation) async throws {
    let fileSystem = await JunkTree.seeded()
    let outcome = try await runCleanupScan(rules: JunkTree.catalog(), over: fileSystem)

    let categoryFindings = outcome.findings(in: expectation.category)
    #expect(!categoryFindings.isEmpty)

    let itemised = categoryFindings.reduce(into: Set<AbsolutePath>()) {
      $0.formUnion($1.paths)
    }
    #expect(itemised == Set(expectation.absolutePaths))

    let expectedBytes = try await allocatedByteTotal(
      of: expectation.absolutePaths, on: fileSystem)
    let reportedBytes = categoryFindings.reduce(0) { $0 + $1.byteSize }
    #expect(reportedBytes == expectedBytes)

    for finding in categoryFindings {
      #expect(finding.risk == .safe)
      #expect(finding.isPreselected)
      #expect(!finding.explanation.isEmpty)
    }
  }

  @Test(
    "the union of all itemised paths is exactly the seeded junk files, never a directory or a bystander"
  )
  func itemisedPathsAreExactlyTheJunkFiles() async throws {
    let fileSystem = await JunkTree.seeded()
    let outcome = try await runCleanupScan(rules: JunkTree.catalog(), over: fileSystem)

    #expect(outcome.itemisedPaths == JunkTree.junkPaths)
    for finding in outcome.findings {
      #expect(!finding.paths.isEmpty)
      #expect(!finding.explanation.isEmpty)
    }
  }

  @Test("a mail attachment finding's explanation says server state is never touched")
  func mailAttachmentExplanationMentionsServerState() async throws {
    let fileSystem = await JunkTree.seeded()
    let outcome = try await runCleanupScan(rules: JunkTree.catalog(), over: fileSystem)

    let mailFindings = outcome.findings(in: .mailAttachmentLocalCopy)
    #expect(!mailFindings.isEmpty)
    for finding in mailFindings {
      #expect(finding.explanation.lowercased().contains("server"))
    }
  }

  @Test("every finding carries the scan's session identifier")
  func findingsCarryTheScanSessionIdentifier() async throws {
    let fileSystem = await JunkTree.seeded()
    let outcome = try await runCleanupScan(
      rules: JunkTree.catalog(),
      over: fileSystem,
      sessionID: CleanupFixture.sessionID
    )

    #expect(!outcome.findings.isEmpty)
    for finding in outcome.findings {
      #expect(finding.sessionID == CleanupFixture.sessionID)
    }
  }

  @Test("scanning the same file system state twice yields the same findings, identifiers aside")
  func scanningTwiceYieldsTheSameFindings() async throws {
    let fileSystem = await JunkTree.seeded()
    let first = try await runCleanupScan(rules: JunkTree.catalog(), over: fileSystem)
    let second = try await runCleanupScan(rules: JunkTree.catalog(), over: fileSystem)

    #expect(!first.findings.isEmpty)
    #expect(
      Set(first.findings.map(FindingShape.init)) == Set(second.findings.map(FindingShape.init)))
  }
}
