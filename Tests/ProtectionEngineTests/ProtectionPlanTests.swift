import Foundation
import GleamCore
import ProtectionEngine
import Testing

/// What a Protection plan can contain, over the whole space of plans this
/// module can produce rather than over the ones a test happened to name.
///
/// Quarantine only, never a silent delete, is the promise the module is sold
/// on. It is a property of the builder rather than a branch inside it, so
/// these are written to fail against any implementation that could reach a
/// removal at all: through the deletion mode, through a category added later,
/// through a forged row.
@Suite("Protection plan")
struct ProtectionPlanTests {

  private static let everyDetectionCategory: [FindingCategory] = [
    .malware(signatureIdentifier: ProtectionFixture.trojanSignature),
    .adwareLaunchItem,
    .suspiciousBrowserExtension,
    .unwantedAppPath,
  ]

  /// Categories from other modules, which this builder must ignore rather
  /// than quarantine: a Protection plan holding somebody else's row would
  /// quarantine a cache.
  private static let foreignCategories: [FindingCategory] = [
    .userCache,
    .log,
    .largeFile,
    .orphanedLeftover,
    .browserHistory(browser: "Safari"),
    .applicationBundle(bundleID: "com.example.mail"),
  ]

  private func finding(
    _ category: FindingCategory,
    paths: [String] = [ProtectionFixture.trojan],
    sessionID: UUID = ProtectionFixture.sessionID
  ) -> Finding {
    Finding(
      id: UUID(),
      sessionID: sessionID,
      category: category,
      entries: paths.map { PathEntry(path: ProtectionFixture.path($0), allocatedBytes: 128) },
      risk: .dangerous,
      explanation: "A fixture row.",
      isPreselected: true)
  }

  @Test(
    "every detection category plans a quarantine and nothing else",
    arguments: everyDetectionCategory)
  func everyDetectionCategoryPlansAQuarantine(category: FindingCategory) throws {
    for mode in [Settings.DeletionMode.trash, .permanent] {
      let plan = try ProtectionEngine().plan(
        selection: [finding(category)],
        context: makeProtectionPlanContext(
          rules: try makeSignedProtectionCatalog(), deletionMode: mode))

      #expect(plan.operations.count == 1)
      guard case .quarantine(let target) = plan.operations.first?.kind else {
        Issue.record("a detection is contained, never deleted, whatever the deletion mode says")
        return
      }
      #expect(target == ProtectionFixture.path(ProtectionFixture.trojan))
    }
  }

  @Test("no plan over any selection this module can make contains a removal")
  func noPlanContainsARemoval() throws {
    let selection = Self.everyDetectionCategory.map { finding($0) }
    for mode in [Settings.DeletionMode.trash, .permanent] {
      let plan = try ProtectionEngine().plan(
        selection: selection,
        context: makeProtectionPlanContext(
          rules: try makeSignedProtectionCatalog(), deletionMode: mode))

      #expect(plan.operations.count == selection.count)
      #expect(
        plan.operations.allSatisfy {
          if case .quarantine = $0.kind { return true }
          return false
        },
        "quarantine only, and the deletion mode has no say in it")
    }
  }

  @Test("a permanent deletion confirmation is never attached, because nothing needs one")
  func noPermanentDeletionConfirmationIsAttached() throws {
    let plan = try ProtectionEngine().plan(
      selection: [finding(.adwareLaunchItem)],
      context: makeProtectionPlanContext(
        rules: try makeSignedProtectionCatalog(), deletionMode: .permanent))
    #expect(plan.permanentDeletionConfirmation == nil)
  }

  @Test("a row from another module contributes nothing", arguments: foreignCategories)
  func aRowFromAnotherModuleContributesNothing(category: FindingCategory) throws {
    let plan = try ProtectionEngine().plan(
      selection: [finding(category)],
      context: makeProtectionPlanContext(rules: try makeSignedProtectionCatalog()))
    #expect(plan.operations.isEmpty)
  }

  @Test("a foreign row beside a detection plans the detection and nothing else")
  func aForeignRowBesideADetectionPlansTheDetection() throws {
    let detection = finding(.adwareLaunchItem, paths: [ProtectionFixture.adwareAgent])
    let foreign = finding(.userCache, paths: [ProtectionFixture.cleanExecutable])

    let plan = try ProtectionEngine().plan(
      selection: [detection, foreign],
      context: makeProtectionPlanContext(rules: try makeSignedProtectionCatalog()))

    #expect(plan.operations.count == 1)
    #expect(plan.operations.first?.findingID == detection.id)
  }

  @Test("a denylisted path is never planned, whatever row names it")
  func aDenylistedPathIsNeverPlanned() throws {
    let detection = finding(
      .adwareLaunchItem, paths: [ProtectionFixture.denylistedAdware, ProtectionFixture.adwareAgent])

    let plan = try ProtectionEngine().plan(
      selection: [detection],
      context: makeProtectionPlanContext(rules: try makeSignedProtectionCatalog()))

    let targets = plan.operations.compactMap { operation -> AbsolutePath? in
      guard case .quarantine(let target) = operation.kind else { return nil }
      return target
    }
    #expect(targets == [ProtectionFixture.path(ProtectionFixture.adwareAgent)])
  }

  @Test("the plan's total is the bytes its operations target")
  func thePlanTotalIsTheBytesItTargets() throws {
    let detection = finding(
      .adwareLaunchItem,
      paths: [ProtectionFixture.adwareAgent, ProtectionFixture.adwareDaemon])

    let plan = try ProtectionEngine().plan(
      selection: [detection],
      context: makeProtectionPlanContext(rules: try makeSignedProtectionCatalog()))

    #expect(plan.totalBytes == 256)
  }

  @Test("a system domain detection is planned at root privilege, a user one at user")
  func privilegeFollowsOwnership() throws {
    let user = finding(.adwareLaunchItem, paths: [ProtectionFixture.adwareAgent])
    let system = finding(.adwareLaunchItem, paths: [ProtectionFixture.adwareDaemon])

    let plan = try ProtectionEngine().plan(
      selection: [user, system],
      context: makeProtectionPlanContext(rules: try makeSignedProtectionCatalog()))

    #expect(plan.operations.map(\.privilege) == [.user, .root])
  }

  @Test("an empty selection is refused rather than planned as nothing")
  func anEmptySelectionIsRefused() throws {
    #expect(throws: PlanningError.emptySelection) {
      _ = try ProtectionEngine().plan(
        selection: [],
        context: makeProtectionPlanContext(rules: try makeSignedProtectionCatalog()))
    }
  }

  @Test("a row from another scan session is refused, so a stale review plans nothing")
  func aRowFromAnotherSessionIsRefused() throws {
    let stale = finding(.adwareLaunchItem, sessionID: ProtectionFixture.otherSessionID)
    #expect(throws: (any Error).self) {
      _ = try ProtectionEngine().plan(
        selection: [stale],
        context: makeProtectionPlanContext(rules: try makeSignedProtectionCatalog()))
    }
  }
}
