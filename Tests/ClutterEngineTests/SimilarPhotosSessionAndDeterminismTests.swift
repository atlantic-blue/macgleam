import Foundation
import GleamCore
import Testing

@Suite("Similar photos: session mechanics and determinism")
struct SimilarPhotosSessionAndDeterminismTests {

  private func phaseOrder(_ phase: ScanPhase) -> Int {
    switch phase {
    case .indeterminate: return 0
    case .determinate: return 1
    case .settling: return 2
    }
  }

  @Test("scan phases only advance during a similar photos scan")
  func scanPhasesOnlyAdvance() async throws {
    let fileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(fileSystem)

    let capture = try await similarPhotosRunScan(fileSystem: fileSystem)

    try #require(!capture.similarSets.isEmpty)
    let order = capture.phases.map(phaseOrder)
    for (earlier, later) in zip(order, order.dropFirst()) {
      #expect(earlier <= later, "phases went backwards: \(capture.phases)")
    }
  }

  @Test("progress counters never decrease during a similar photos scan")
  func progressCountersNeverDecrease() async throws {
    let fileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(fileSystem)

    let capture = try await similarPhotosRunScan(fileSystem: fileSystem)

    try #require(!capture.similarSets.isEmpty)
    for (earlier, later) in zip(capture.progress, capture.progress.dropFirst()) {
      #expect(earlier.filesSeen <= later.filesSeen)
      #expect(earlier.bytesReclaimable <= later.bytesReclaimable)
      #expect(earlier.itemCount <= later.itemCount)
    }
  }

  @Test("similar set findings carry the scan session identifier")
  func similarSetFindingsCarryTheSessionIdentifier() async throws {
    let fileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(fileSystem)
    let sessionID = UUID()

    let capture = try await similarPhotosRunScan(
      fileSystem: fileSystem,
      sessionID: sessionID
    )

    try #require(!capture.similarSets.isEmpty)
    for set in capture.similarSets {
      #expect(set.sessionID == sessionID)
    }
  }

  @Test("two scans of the same tree yield the same sets and kept choices")
  func twoScansYieldTheSameSetsAndKeptChoices() async throws {
    let firstFileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(firstFileSystem)
    let secondFileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(secondFileSystem)

    let first = try await similarPhotosRunScan(fileSystem: firstFileSystem)
    let second = try await similarPhotosRunScan(fileSystem: secondFileSystem)

    try #require(!first.similarSets.isEmpty)
    let firstShapes = Set(first.similarSets.map(SimilarPhotosSetShape.init))
    let secondShapes = Set(second.similarSets.map(SimilarPhotosSetShape.init))
    #expect(firstShapes == secondShapes)
  }
}
