import Foundation
import GleamCore
import LeftoversEngine
import Testing

@Suite("Duplicate kept copy")
struct DuplicatesKeepRuleTests {

  private func threeCopies() -> [DuplicatesFakeFile] {
    let content = duplicatesContent(byte: 0x7B)
    return [
      duplicatesFile("Documents/kept candidate.bin", content: content),
      duplicatesFile("Downloads/copy in downloads.bin", content: content),
      duplicatesFile("Desktop/copy on desktop.bin", content: content),
    ]
  }

  @Test("the kept path of a duplicate set is always one of its members")
  func keptPathIsAMember() async throws {
    let outcome = try await duplicatesRunScan(
      context: duplicatesScanContext(files: threeCopies())
    )
    let set = try #require(duplicatesSetFindings(in: outcome).first)
    let kept = try #require(duplicatesKeptPath(of: set))
    #expect(set.paths.contains(kept))
  }

  @Test("every duplicate set holds at least two paths")
  func setsHoldAtLeastTwoPaths() async throws {
    let outcome = try await duplicatesRunScan(
      context: duplicatesScanContext(files: threeCopies())
    )
    let sets = duplicatesSetFindings(in: outcome)
    #expect(!sets.isEmpty)
    for set in sets {
      #expect(set.paths.count >= 2)
    }
  }

  @Test("scanning the same tree twice yields the same sets with the same kept copies")
  func keptChoiceIsDeterministicAcrossScans() async throws {
    let first = try await duplicatesRunScan(
      context: duplicatesScanContext(files: threeCopies())
    )
    let second = try await duplicatesRunScan(
      context: duplicatesScanContext(files: threeCopies())
    )
    let firstShapes = duplicatesSetShapes(in: first)
    let secondShapes = duplicatesSetShapes(in: second)
    #expect(!firstShapes.isEmpty)
    #expect(firstShapes == secondShapes)
  }
}
