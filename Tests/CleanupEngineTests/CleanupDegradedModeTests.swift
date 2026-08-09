import CleanupEngine
import Foundation
import GleamCore
import Testing

/// Without Full Disk Access the engine scans what the user domain allows,
/// skips the protected categories (mail attachment local copies and trash
/// bins), and says so through degraded events instead of throwing. The
/// honest banner in the interface renders exactly these sentences.
@Suite("Cleanup scan: degraded mode without full disk access")
struct CleanupDegradedModeTests {

  @Test("protected categories are skipped and the skip is reported by name")
  func protectedCategoriesAreSkippedAndNamed() async throws {
    let fileSystem = await JunkTree.seeded()
    let outcome = try await runCleanupScan(
      rules: JunkTree.catalog(),
      over: fileSystem,
      hasFullDiskAccess: false
    )

    #expect(outcome.findings(in: .mailAttachmentLocalCopy).isEmpty)
    #expect(outcome.trashBinFindings.isEmpty)

    #expect(!outcome.degradedMessages.isEmpty)
    for message in outcome.degradedMessages {
      #expect(!message.isEmpty)
    }
    let combined = outcome.degradedMessages.joined(separator: " ").lowercased()
    #expect(combined.contains("mail"))
    #expect(combined.contains("trash"))
  }

  @Test("user domain categories are still found without full disk access")
  func userDomainCategoriesAreStillFound() async throws {
    let fileSystem = await JunkTree.seeded()
    let outcome = try await runCleanupScan(
      rules: JunkTree.catalog(),
      over: fileSystem,
      hasFullDiskAccess: false
    )

    let userCachePaths = outcome.findings(in: .userCache).reduce(into: Set<AbsolutePath>()) {
      $0.formUnion($1.paths)
    }
    #expect(
      userCachePaths == [
        CleanupFixture.path(JunkTree.userCacheState),
        CleanupFixture.path(JunkTree.userCacheThumb),
      ])
    #expect(!outcome.findings(in: .log).isEmpty)
  }

  @Test("a degraded scan completes its phases and never throws")
  func degradedScanCompletesWithoutThrowing() async throws {
    let fileSystem = await JunkTree.seeded()
    let outcome = try await runCleanupScan(
      rules: JunkTree.catalog(),
      over: fileSystem,
      hasFullDiskAccess: false
    )

    #expect(outcome.phases.last == .settling)
  }
}
