import ClutterEngine
import Foundation
import GleamCore
import Testing

@Suite("Similar photos: risk, scope and denylist")
struct SimilarPhotosRiskAndScopeTests {

  @Test("similar sets are never preselected above safe risk")
  func neverPreselectedAboveSafeRisk() async throws {
    let fileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(fileSystem)

    let capture = try await similarPhotosRunScan(fileSystem: fileSystem)

    try #require(!capture.similarSets.isEmpty)
    for set in capture.similarSets {
      #expect(!(set.isPreselected && set.risk != .safe))
    }
  }

  @Test("every similar set carries a non empty explanation")
  func everySetCarriesANonEmptyExplanation() async throws {
    let fileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(fileSystem)

    let capture = try await similarPhotosRunScan(fileSystem: fileSystem)

    try #require(!capture.similarSets.isEmpty)
    for set in capture.similarSets {
      #expect(!set.explanation.isEmpty)
    }
  }

  // Pin: C10 makes denylisted paths unremovable at plan time; C21 is silent
  // on scan time membership. Pinned per the slice verification list:
  // denylisted photos are never members nor kept.
  @Test("denylisted photos are never members nor kept")
  func denylistedPhotosAreNeverMembersNorKept() async throws {
    let fileSystem = InMemoryFileSystem()
    let pictures = "\(SimilarPhotosFixtures.home.value)/Pictures"
    let blockedOne = "\(pictures)/blocked/checker.png"
    let blockedTwo = "\(pictures)/blocked/checker-annotated.png"
    await similarPhotosSeed(
      fileSystem,
      files: [
        ("\(pictures)/open/beach.png", SimilarPhotosImageFactory.beach),
        ("\(pictures)/open/beach-annotated.png", SimilarPhotosImageFactory.beachAnnotated),
        (blockedOne, SimilarPhotosImageFactory.checker),
        (blockedTwo, SimilarPhotosImageFactory.checkerAnnotated),
      ])

    let capture = try await similarPhotosRunScan(
      fileSystem: fileSystem,
      denylistPatterns: [blockedOne, blockedTwo]
    )

    try #require(!capture.similarSets.isEmpty)
    for set in capture.similarSets {
      let members = Set(set.paths.map(\.value))
      #expect(!members.contains(blockedOne))
      #expect(!members.contains(blockedTwo))
      let keptPath = try #require(set.similarPhotosKeptPath)
      #expect(keptPath.value != blockedOne)
      #expect(keptPath.value != blockedTwo)
    }
  }

  @Test("plan emits no operation for a denylisted member")
  func planEmitsNoOperationForADenylistedMember() async throws {
    let fileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(fileSystem)
    let sessionID = UUID()
    let capture = try await similarPhotosRunScan(
      fileSystem: fileSystem,
      sessionID: sessionID
    )
    let sets = capture.similarSets
    try #require(!sets.isEmpty)
    let firstSet = try #require(sets.first)
    let keptPath = try #require(firstSet.similarPhotosKeptPath)
    let denied = try #require(firstSet.paths.first { $0 != keptPath })

    let plan = try SimilarPhotosFixtures.engine().plan(
      selection: sets,
      context: SimilarPhotosFixtures.planContext(
        sessionID: sessionID,
        denylistPatterns: [denied.value]
      )
    )

    var expectedTargets = Set<AbsolutePath>()
    for set in sets {
      let kept = try #require(set.similarPhotosKeptPath)
      expectedTargets.formUnion(set.paths.filter { $0 != kept })
    }
    expectedTargets.remove(denied)
    let plannedTargets = Set(plan.operations.compactMap { $0.kind.similarPhotosTarget })
    #expect(!plannedTargets.contains(denied))
    #expect(plannedTargets == expectedTargets)
  }

  @Test("photos outside the user home never appear in any set")
  func photosOutsideTheUserHomeNeverAppear() async throws {
    let fileSystem = InMemoryFileSystem()
    let home = SimilarPhotosFixtures.home
    await similarPhotosSeed(
      fileSystem,
      files: [
        ("\(home.value)/Pictures/holiday/beach.png", SimilarPhotosImageFactory.beach),
        (
          "\(home.value)/Pictures/holiday/beach-annotated.png",
          SimilarPhotosImageFactory.beachAnnotated
        ),
        // The same scenes planted outside the home: a scope leak would
        // pull them into the in home sets.
        ("/Users/otherperson/Pictures/beach.png", SimilarPhotosImageFactory.beach),
        (
          "/Users/otherperson/Pictures/beach-annotated.png",
          SimilarPhotosImageFactory.beachAnnotated
        ),
        ("/System/Library/DesktopPictures/beach.png", SimilarPhotosImageFactory.beach),
        (
          "/System/Library/DesktopPictures/beach-annotated.png",
          SimilarPhotosImageFactory.beachAnnotated
        ),
      ])

    let capture = try await similarPhotosRunScan(fileSystem: fileSystem)

    try #require(!capture.similarSets.isEmpty)
    for set in capture.similarSets {
      for member in set.paths {
        #expect(
          member == home || member.isDescendant(of: home),
          "\(member.value) is outside the user home"
        )
      }
    }
  }
}
