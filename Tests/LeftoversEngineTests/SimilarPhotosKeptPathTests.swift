import Foundation
import GleamCore
import LeftoversEngine
import Testing

@Suite("Similar photos: kept path mechanics")
struct SimilarPhotosKeptPathTests {

  private func scannedSets(
    sessionID: UUID,
    fileSystem: InMemoryFileSystem
  ) async throws -> [Finding] {
    let capture = try await similarPhotosRunScan(
      fileSystem: fileSystem,
      sessionID: sessionID
    )
    return capture.similarSets
  }

  @Test("kept path is a member and every set has at least two paths")
  func keptPathIsAMemberAndSetsHaveAtLeastTwoPaths() async throws {
    let fileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(fileSystem)

    let sets = try await scannedSets(sessionID: UUID(), fileSystem: fileSystem)

    try #require(!sets.isEmpty)
    for set in sets {
      let keptPath = try #require(set.similarPhotosKeptPath)
      #expect(set.paths.contains(keptPath))
      #expect(set.paths.count >= 2)
    }
  }

  @Test("plan never targets the kept path of any selected set")
  func planNeverTargetsTheKeptPath() async throws {
    let fileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(fileSystem)
    let sessionID = UUID()
    let sets = try await scannedSets(sessionID: sessionID, fileSystem: fileSystem)
    try #require(!sets.isEmpty)

    let plan = try SimilarPhotosFixtures.engine().plan(
      selection: sets,
      context: SimilarPhotosFixtures.planContext(sessionID: sessionID)
    )

    let keptPaths = Set(sets.compactMap { $0.similarPhotosKeptPath })
    for operation in plan.operations {
      let target = try #require(operation.kind.similarPhotosTarget)
      #expect(!keptPaths.contains(target), "plan targets kept path \(target.value)")
    }
  }

  @Test("plan maps every non kept member to move to trash under default settings")
  func planMapsNonKeptMembersToMoveToTrash() async throws {
    let fileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(fileSystem)
    let sessionID = UUID()
    let sets = try await scannedSets(sessionID: sessionID, fileSystem: fileSystem)
    try #require(!sets.isEmpty)

    let plan = try SimilarPhotosFixtures.engine().plan(
      selection: sets,
      context: SimilarPhotosFixtures.planContext(sessionID: sessionID)
    )

    var expectedTargets = Set<AbsolutePath>()
    for set in sets {
      let keptPath = try #require(set.similarPhotosKeptPath)
      expectedTargets.formUnion(set.paths.filter { $0 != keptPath })
    }
    var plannedTargets = Set<AbsolutePath>()
    for operation in plan.operations {
      guard case .moveToTrash(let target) = operation.kind else {
        Issue.record("expected moveToTrash, got \(operation.kind)")
        continue
      }
      #expect(operation.privilege == .user)
      plannedTargets.insert(target)
    }
    #expect(plannedTargets == expectedTargets)
    #expect(plan.sessionID == sessionID)
  }

  @Test("selection stripped of its kept path is refused with keptCopyMissing")
  func selectionWithoutKeptPathIsRefused() async throws {
    let fileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(fileSystem)
    let sessionID = UUID()
    let sets = try await scannedSets(sessionID: sessionID, fileSystem: fileSystem)
    let victim = try #require(sets.first)
    let keptPath = try #require(victim.similarPhotosKeptPath)

    let hostile = Finding(
      id: UUID(),
      sessionID: victim.sessionID,
      category: victim.category,
      entries: victim.entries.filter { $0.path != keptPath },
      risk: victim.risk,
      explanation: victim.explanation,
      isPreselected: victim.isPreselected
    )

    #expect(throws: PlanningError.keptCopyMissing(findingID: hostile.id)) {
      _ = try SimilarPhotosFixtures.engine().plan(
        selection: [hostile],
        context: SimilarPhotosFixtures.planContext(sessionID: sessionID)
      )
    }
  }

  @Test("selection whose kept path was swapped for a foreign path is refused")
  func selectionWithForeignPathInsteadOfKeptIsRefused() async throws {
    let fileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(fileSystem)
    let sessionID = UUID()
    let sets = try await scannedSets(sessionID: sessionID, fileSystem: fileSystem)
    let victim = try #require(sets.first)
    let keptPath = try #require(victim.similarPhotosKeptPath)
    let foreign = AbsolutePath(
      normalising: "\(SimilarPhotosFixtures.home.value)/Pictures/uninvolved.png"
    )

    let hostile = Finding(
      id: UUID(),
      sessionID: victim.sessionID,
      category: victim.category,
      entries: victim.entries.filter { $0.path != keptPath }
        + [PathEntry(path: foreign, allocatedBytes: 64)],
      risk: victim.risk,
      explanation: victim.explanation,
      isPreselected: victim.isPreselected
    )

    #expect(throws: PlanningError.keptCopyMissing(findingID: hostile.id)) {
      _ = try SimilarPhotosFixtures.engine().plan(
        selection: [hostile],
        context: SimilarPhotosFixtures.planContext(sessionID: sessionID)
      )
    }
  }

  @Test("one hostile finding poisons the whole plan")
  func oneHostileFindingPoisonsTheWholePlan() async throws {
    let fileSystem = InMemoryFileSystem()
    await similarPhotosSeedStandardTree(fileSystem)
    let sessionID = UUID()
    let sets = try await scannedSets(sessionID: sessionID, fileSystem: fileSystem)
    let victim = try #require(sets.first)
    let keptPath = try #require(victim.similarPhotosKeptPath)

    let hostile = Finding(
      id: UUID(),
      sessionID: victim.sessionID,
      category: victim.category,
      entries: victim.entries.filter { $0.path != keptPath },
      risk: victim.risk,
      explanation: victim.explanation,
      isPreselected: victim.isPreselected
    )

    #expect(throws: PlanningError.keptCopyMissing(findingID: hostile.id)) {
      _ = try SimilarPhotosFixtures.engine().plan(
        selection: sets + [hostile],
        context: SimilarPhotosFixtures.planContext(sessionID: sessionID)
      )
    }
  }
}
