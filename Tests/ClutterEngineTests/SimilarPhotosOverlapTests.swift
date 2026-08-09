import Foundation
import GleamCore
import Testing

@Suite("Similar photos: sets never overlap")
struct SimilarPhotosOverlapTests {

  @Test("a photo appears in at most one similar set")
  func photoAppearsInAtMostOneSimilarSet() async throws {
    let fileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(fileSystem)

    let capture = try await similarPhotosRunScan(fileSystem: fileSystem)

    #expect(!capture.similarSets.isEmpty)
    var seen: [String: Int] = [:]
    for set in capture.similarSets {
      for member in set.paths {
        seen[member.value, default: 0] += 1
      }
    }
    for (path, count) in seen {
      #expect(count == 1, "\(path) appears in \(count) similar sets")
    }
  }

  // Pin: C21 orders no precedence between duplicate and similar sets. Pinned
  // so one file is never claimed by both categories, otherwise one removal
  // flow can invalidate the kept guarantee of the other.
  @Test("no path is claimed by both a duplicate set and a similar set")
  func noPathClaimedByBothCategories() async throws {
    let fileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(fileSystem)

    let capture = try await similarPhotosRunScan(fileSystem: fileSystem)

    #expect(!capture.similarSets.isEmpty)
    let similarMembers = Set(capture.similarSets.flatMap { $0.paths.map(\.value) })
    let duplicateMembers = Set(capture.duplicateSets.flatMap { $0.paths.map(\.value) })
    #expect(similarMembers.intersection(duplicateMembers).isEmpty)
  }

  // Pin: byte identical photos satisfy any similarity measure, and C21 is
  // silent on which category wins. Pinned: byte identical photos are
  // duplicates, never members of a similar set.
  @Test("byte identical photos are duplicates never similar")
  func byteIdenticalPhotosAreDuplicatesNeverSimilar() async throws {
    let fileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(fileSystem)
    let archive = "\(SimilarPhotosFixtures.home.value)/Pictures/archive"
    let identicalPair = ["\(archive)/copy-one.png", "\(archive)/copy-two.png"]

    let capture = try await similarPhotosRunScan(fileSystem: fileSystem)

    #expect(!capture.similarSets.isEmpty)
    let duplicateMembers = Set(capture.duplicateSets.flatMap { $0.paths.map(\.value) })
    let similarMembers = Set(capture.similarSets.flatMap { $0.paths.map(\.value) })
    for path in identicalPair {
      #expect(duplicateMembers.contains(path), "\(path) should be in a duplicate set")
      #expect(!similarMembers.contains(path), "\(path) must not be in a similar set")
    }
  }
}
