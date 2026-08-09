import ClutterEngine
import Foundation
import GleamCore
import Testing

@Suite("Duplicate keep one invariant at plan time")
struct DuplicatesPlanInvariantTests {

  private func scannedSet(
    sessionID: UUID,
    files: [DuplicatesFakeFile]
  ) async throws -> Finding {
    let outcome = try await duplicatesRunScan(
      context: duplicatesScanContext(sessionID: sessionID, files: files)
    )
    return try #require(duplicatesSetFindings(in: outcome).first)
  }

  private func threeCopies() -> [DuplicatesFakeFile] {
    let content = duplicatesContent(byte: 0x4E)
    return [
      duplicatesFile("Documents/one.bin", content: content, allocatedBytes: 4_096),
      duplicatesFile("Pictures/two.bin", content: content, allocatedBytes: 8_192),
      duplicatesFile("Desktop/three.bin", content: content, allocatedBytes: 12_288),
    ]
  }

  @Test("selecting a whole set plans a removal for every member except the kept copy")
  func wholeSetSelectionSparesOnlyTheKeptCopy() async throws {
    let sessionID = UUID()
    let files = threeCopies()
    let set = try await scannedSet(sessionID: sessionID, files: files)
    let kept = try #require(duplicatesKeptPath(of: set))
    let plan = try duplicatesEngine().plan(
      selection: [set],
      context: duplicatesPlanContext(sessionID: sessionID)
    )
    let targets = Set(plan.operations.compactMap(duplicatesOperationTarget))
    #expect(targets == Set(set.paths).subtracting([kept]))
  }

  @Test(
    "a forged selection whose kept path is missing from its members is refused with keptCopyMissing"
  )
  func forgedSelectionWithoutKeptMemberIsRefused() async throws {
    let sessionID = UUID()
    let files = threeCopies()
    let set = try await scannedSet(sessionID: sessionID, files: files)
    let strangerPath = AbsolutePath(
      normalising: duplicatesUserHome.value + "/Documents/not a member.bin"
    )
    let kept = try #require(duplicatesKeptPath(of: set))
    let forged = Finding(
      id: UUID(),
      sessionID: sessionID,
      category: .duplicateSet(keptPath: strangerPath),
      entries: set.entries.filter { $0.path != strangerPath },
      risk: set.risk,
      explanation: set.explanation,
      isPreselected: set.isPreselected
    )
    #expect(kept != strangerPath)
    #expect(throws: PlanningError.keptCopyMissing(findingID: forged.id)) {
      try duplicatesEngine().plan(
        selection: [forged],
        context: duplicatesPlanContext(sessionID: sessionID)
      )
    }
  }

  @Test("a tampered selection listing the kept path twice still plans nothing against it")
  func tamperedSelectionRepeatingKeptPathStillSparesIt() async throws {
    let sessionID = UUID()
    let files = threeCopies()
    let set = try await scannedSet(sessionID: sessionID, files: files)
    let kept = try #require(duplicatesKeptPath(of: set))
    let keptEntry = try #require(set.entries.first { $0.path == kept })
    let tampered = Finding(
      id: UUID(),
      sessionID: sessionID,
      category: set.category,
      entries: set.entries + [keptEntry],
      risk: set.risk,
      explanation: set.explanation,
      isPreselected: set.isPreselected
    )
    let plan = try duplicatesEngine().plan(
      selection: [tampered],
      context: duplicatesPlanContext(sessionID: sessionID)
    )
    let targets = plan.operations.compactMap(duplicatesOperationTarget)
    #expect(!targets.contains(kept))
    #expect(!targets.isEmpty)
  }

  @Test("a mixed selection of several sets spares each set's kept copy")
  func mixedSelectionSparesEverySetsKeptCopy() async throws {
    let sessionID = UUID()
    let contentA = duplicatesContent(byte: 0x21)
    let contentB = duplicatesContent(byte: 0x22, count: 128)
    let files = [
      duplicatesFile("Documents/a one.bin", content: contentA),
      duplicatesFile("Documents/a two.bin", content: contentA),
      duplicatesFile("Documents/a three.bin", content: contentA),
      duplicatesFile("Music/b one.bin", content: contentB),
      duplicatesFile("Music/b two.bin", content: contentB),
    ]
    let outcome = try await duplicatesRunScan(
      context: duplicatesScanContext(sessionID: sessionID, files: files)
    )
    let sets = duplicatesSetFindings(in: outcome)
    #expect(sets.count == 2)
    let keptPaths = Set(sets.compactMap(duplicatesKeptPath(of:)))
    let allMembers = Set(sets.flatMap(\.paths))
    let plan = try duplicatesEngine().plan(
      selection: sets,
      context: duplicatesPlanContext(sessionID: sessionID)
    )
    let targets = Set(plan.operations.compactMap(duplicatesOperationTarget))
    #expect(targets == allMembers.subtracting(keptPaths))
    #expect(plan.operations.count == allMembers.count - keptPaths.count)
  }

  @Test(
    "a duplicate plan's total bytes are the allocated bytes of the members excluding the kept copy")
  func planTotalBytesExcludeTheKeptCopy() async throws {
    let sessionID = UUID()
    let files = threeCopies()
    let allocatedByPath = Dictionary(
      uniqueKeysWithValues: files.map { ($0.path, $0.allocatedBytes) }
    )
    let set = try await scannedSet(sessionID: sessionID, files: files)
    let kept = try #require(duplicatesKeptPath(of: set))
    let keptAllocated = try #require(allocatedByPath[kept])
    let allAllocated = files.reduce(UInt64(0)) { $0 + $1.allocatedBytes }
    let plan = try duplicatesEngine().plan(
      selection: [set],
      context: duplicatesPlanContext(sessionID: sessionID)
    )
    #expect(plan.totalBytes == allAllocated - keptAllocated)
  }

  @Test(
    "a duplicate set finding's byte size is the allocated total across all members including the kept copy"
  )
  func findingByteSizeCoversAllMembers() async throws {
    let files = threeCopies()
    let set = try await scannedSet(sessionID: UUID(), files: files)
    let allAllocated = files.reduce(UInt64(0)) { $0 + $1.allocatedBytes }
    #expect(set.byteSize == allAllocated)
  }
}
