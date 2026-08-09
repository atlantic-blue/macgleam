import ClutterEngine
import Foundation
import GleamCore
import Testing

@Suite("Duplicate grouping by content")
struct DuplicatesGroupingTests {

  @Test("byte identical files across different folders and names form one duplicate set")
  func identicalFilesGroupAcrossFoldersAndNames() async throws {
    let content = duplicatesContent(byte: 0xA5)
    let files = [
      duplicatesFile("Documents/report.bin", content: content),
      duplicatesFile("Pictures/holiday copy.bin", content: content),
      duplicatesFile("Desktop/misc/whatever.dat", content: content),
    ]
    let outcome = try await duplicatesRunScan(context: duplicatesScanContext(files: files))
    let sets = duplicatesSetFindings(in: outcome)
    #expect(sets.count == 1)
    let set = try #require(sets.first)
    #expect(Set(set.paths) == Set(files.map(\.path)))
  }

  @Test("files of equal size but different content never form a set")
  func equalSizeDifferentContentDoesNotGroup() async throws {
    var altered = duplicatesContent(byte: 0x11, count: 256)
    altered[128] = 0x22
    let files = [
      duplicatesFile("Documents/original.bin", content: duplicatesContent(byte: 0x11, count: 256)),
      duplicatesFile("Documents/impostor.bin", content: altered),
    ]
    let outcome = try await duplicatesRunScan(context: duplicatesScanContext(files: files))
    #expect(duplicatesSetFindings(in: outcome).isEmpty)
  }

  @Test("a copy with one extra byte appended does not join its shorter original's set")
  func appendedByteBreaksMembership() async throws {
    let content = duplicatesContent(byte: 0x3C, count: 100)
    var appended = content
    appended.append(0x3C)
    let shorterOne = duplicatesFile("Documents/pair one.bin", content: content)
    let shorterTwo = duplicatesFile("Music/pair two.bin", content: content)
    let longer = duplicatesFile("Movies/longer.bin", content: appended)
    let outcome = try await duplicatesRunScan(
      context: duplicatesScanContext(files: [shorterOne, shorterTwo, longer])
    )
    let sets = duplicatesSetFindings(in: outcome)
    #expect(sets.count == 1)
    let set = try #require(sets.first)
    #expect(Set(set.paths) == Set([shorterOne.path, shorterTwo.path]))
  }

  @Test("two byte identical empty files do not form a duplicate set")
  func identicalEmptyFilesDoNotGroup() async throws {
    let files = [
      duplicatesFile("Documents/empty one.txt", content: Data(), allocatedBytes: 0),
      duplicatesFile("Documents/empty two.txt", content: Data(), allocatedBytes: 0),
    ]
    let outcome = try await duplicatesRunScan(context: duplicatesScanContext(files: files))
    #expect(duplicatesSetFindings(in: outcome).isEmpty)
  }

  @Test("distinct contents form distinct sets that never share a member")
  func distinctContentsFormDisjointSets() async throws {
    let contentA = duplicatesContent(byte: 0x01)
    let contentB = duplicatesContent(byte: 0x02)
    let groupA = [
      duplicatesFile("Documents/alpha one.bin", content: contentA),
      duplicatesFile("Documents/alpha two.bin", content: contentA),
    ]
    let groupB = [
      duplicatesFile("Pictures/beta one.bin", content: contentB),
      duplicatesFile("Pictures/beta two.bin", content: contentB),
    ]
    let outcome = try await duplicatesRunScan(
      context: duplicatesScanContext(files: groupA + groupB)
    )
    let shapes = duplicatesSetShapes(in: outcome)
    #expect(shapes.map(\.paths).contains(Set(groupA.map(\.path))))
    #expect(shapes.map(\.paths).contains(Set(groupB.map(\.path))))
    #expect(shapes.count == 2)
  }
}
