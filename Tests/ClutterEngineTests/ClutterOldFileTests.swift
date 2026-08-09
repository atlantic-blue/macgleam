import ClutterEngine
import Foundation
import GleamCore
import Testing

@Suite("Clutter scan: old files")
struct ClutterOldFileTests {

  @Test(
    "a file last opened exactly threshold days before the reference date is an old file finding naming last opened"
  )
  func fileLastOpenedExactlyAtThresholdIsAFinding() async throws {
    let fileSystem = await ClutterTree.seeded()
    let outcome = try await runClutterScan(rules: ClutterTree.catalog(), over: fileSystem)

    let target = ClutterFixture.path(ClutterTree.oldByLastOpened)
    let finding = try #require(
      outcome.findings(in: .oldFile).first { $0.paths.contains(target) })
    #expect(finding.paths == [target])
    #expect(finding.byteSize == 64)
    #expect(finding.explanation.lowercased().contains("last opened"))
  }

  @Test("a file last opened one day newer than the threshold is not an old file finding")
  func fileOneDayNewerThanThresholdIsNotAFinding() async throws {
    let fileSystem = await ClutterTree.seeded()
    let outcome = try await runClutterScan(rules: ClutterTree.catalog(), over: fileSystem)

    let newer = ClutterFixture.path(ClutterTree.oldOneDayNewer)
    #expect(outcome.findings(in: .oldFile).allSatisfy { !$0.paths.contains(newer) })
  }

  @Test(
    "a file with no last opened date falls back to its modification date and the explanation names it"
  )
  func missingLastOpenedFallsBackToModificationDate() async throws {
    let fileSystem = await ClutterTree.seeded()
    let outcome = try await runClutterScan(rules: ClutterTree.catalog(), over: fileSystem)

    let target = ClutterFixture.path(ClutterTree.oldByModificationFallback)
    let finding = try #require(
      outcome.findings(in: .oldFile).first { $0.paths.contains(target) })
    #expect(finding.explanation.lowercased().contains("modif"))
  }

  @Test("age is reckoned against the injected reference date, not a wall clock")
  func ageIsReckonedAgainstTheInjectedReferenceDate() async throws {
    let fileSystem = await ClutterTree.seeded()
    let exactlyAtThreshold = ClutterFixture.path(ClutterTree.oldByLastOpened)

    let atReference = try await runClutterScan(
      rules: ClutterTree.catalog(), over: fileSystem)
    #expect(
      atReference.findings(in: .oldFile).contains { $0.paths.contains(exactlyAtThreshold) })

    // One day earlier the same file is only 179 days unopened, so shifting
    // the injected date alone must change the verdict.
    let dayEarlier = makeClutterEngine(referenceDate: ClutterFixture.daysBeforeReference(1))
    let shifted = try await runClutterScan(
      rules: ClutterTree.catalog(), over: fileSystem, engine: dayEarlier)
    #expect(
      shifted.findings(in: .oldFile).allSatisfy { !$0.paths.contains(exactlyAtThreshold) })
  }

  @Test("a recently opened small file is neither a large nor an old file finding")
  func recentSmallFileIsNoFinding() async throws {
    let fileSystem = await ClutterTree.seeded()
    let outcome = try await runClutterScan(rules: ClutterTree.catalog(), over: fileSystem)

    let fresh = ClutterFixture.path(ClutterTree.freshDocument)
    #expect(!outcome.itemisedPaths.contains(fresh))
  }
}
