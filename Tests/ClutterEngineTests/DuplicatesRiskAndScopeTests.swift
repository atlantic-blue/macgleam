import ClutterEngine
import Foundation
import GleamCore
import Testing

@Suite("Duplicate risk, preselection and scan scope")
struct DuplicatesRiskAndScopeTests {

  private func pairInsideHome() -> [DuplicatesFakeFile] {
    let content = duplicatesContent(byte: 0x59)
    return [
      duplicatesFile("Documents/inside one.bin", content: content),
      duplicatesFile("Documents/inside two.bin", content: content),
    ]
  }

  @Test("a preselected duplicate finding always carries safe risk")
  func preselectionImpliesSafeRisk() async throws {
    let outcome = try await duplicatesRunScan(
      context: duplicatesScanContext(files: pairInsideHome())
    )
    let sets = duplicatesSetFindings(in: outcome)
    #expect(!sets.isEmpty)
    for set in sets where set.isPreselected {
      #expect(set.risk == .safe)
    }
  }

  @Test("every duplicate finding explains itself in a non empty sentence")
  func findingsCarryAnExplanation() async throws {
    let outcome = try await duplicatesRunScan(
      context: duplicatesScanContext(files: pairInsideHome())
    )
    let sets = duplicatesSetFindings(in: outcome)
    #expect(!sets.isEmpty)
    for set in sets {
      #expect(!set.explanation.isEmpty)
    }
  }

  @Test("an identical copy outside the user home never joins a set")
  func copyOutsideHomeDoesNotJoin() async throws {
    let content = duplicatesContent(byte: 0x77)
    let inside = duplicatesFile("Documents/only copy at home.bin", content: content)
    let outside = duplicatesFileAt(
      absolute: "/Users/stranger/their copy.bin",
      content: content
    )
    let outcome = try await duplicatesRunScan(
      context: duplicatesScanContext(files: [inside, outside])
    )
    #expect(duplicatesSetFindings(in: outcome).isEmpty)
  }

  @Test("byte identical files entirely outside the user home produce no duplicate findings")
  func copiesEntirelyOutsideHomeProduceNothing() async throws {
    let content = duplicatesContent(byte: 0x78)
    let files = [
      duplicatesFileAt(absolute: "/Users/stranger/one.bin", content: content),
      duplicatesFileAt(absolute: "/tmp/two.bin", content: content),
    ]
    let outcome = try await duplicatesRunScan(
      context: duplicatesScanContext(files: files)
    )
    #expect(duplicatesSetFindings(in: outcome).isEmpty)
  }

  @Test("a denylisted copy is never a member nor the kept copy of a set")
  func denylistedCopyIsExcludedFromSets() async throws {
    let content = duplicatesContent(byte: 0x91)
    let blockedDirectory = duplicatesUserHome.value + "/Blocked"
    let free = [
      duplicatesFile("Documents/free one.bin", content: content),
      duplicatesFile("Documents/free two.bin", content: content),
    ]
    let blocked = duplicatesFile("Blocked/blocked copy.bin", content: content)
    let outcome = try await duplicatesRunScan(
      context: duplicatesScanContext(
        files: free + [blocked],
        denylistPatterns: [blockedDirectory]
      )
    )
    let sets = duplicatesSetFindings(in: outcome)
    #expect(sets.count == 1)
    let set = try #require(sets.first)
    #expect(Set(set.paths) == Set(free.map(\.path)))
    #expect(duplicatesKeptPath(of: set) != blocked.path)
  }

  @Test("a set cannot form when the denylist leaves only one copy")
  func denylistLeavingOneCopyFormsNoSet() async throws {
    let content = duplicatesContent(byte: 0x92)
    let blockedDirectory = duplicatesUserHome.value + "/Blocked"
    let files = [
      duplicatesFile("Documents/survivor.bin", content: content),
      duplicatesFile("Blocked/blocked twin.bin", content: content),
    ]
    let outcome = try await duplicatesRunScan(
      context: duplicatesScanContext(
        files: files,
        denylistPatterns: [blockedDirectory]
      )
    )
    #expect(duplicatesSetFindings(in: outcome).isEmpty)
  }
}
