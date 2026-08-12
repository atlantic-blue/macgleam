import ApplicationsEngine
import Foundation
import GleamCore
import Testing

/// The leftover sweep: files in the recognised support locations that no
/// application on this Mac claims.
///
/// The association rule is the same one the uninstall uses, read from the
/// other end. An uninstall asks "which installed application owns this", and a
/// sweep asks "does any of them". Everything the rule refuses to attribute
/// stays refused here: a name that merely contains an identifier, a directory
/// inside a stranger's folder, a group container. What is added is one further
/// caution, because a sweep acts on files nobody speaks for: an identity that
/// is not shaped like a bundle identifier is not swept, and neither is
/// anything Apple's.
@Suite("Applications orphan sweep")
struct OrphanSweepTests {

  private func orphans(in outcome: ScanOutcome) -> [Finding] {
    outcome.findings.filter { $0.category == .orphanedLeftover }
  }

  private func orphanedPaths(in outcome: ScanOutcome) -> Set<AbsolutePath> {
    Set(orphans(in: outcome).flatMap(\.entries).map(\.path))
  }

  // MARK: - What the sweep finds

  @Test("the files of an application that is gone are swept")
  func theFilesOfAnApplicationThatIsGoneAreSwept() async throws {
    let outcome = try await runApplicationsScan()
    expectCompleteScan(outcome)

    let swept = orphanedPaths(in: outcome)
    let ghostPreference = "\(ApplicationWorld.preferences)/\(ApplicationWorld.ghost).plist"
    let ghostLog = "\(ApplicationWorld.logs)/\(ApplicationWorld.ghost).log"
    #expect(swept.contains(ApplicationsFixture.path(ghostPreference)))
    #expect(swept.contains(ApplicationsFixture.path(ghostLog)))
  }

  @Test("an orphan carries the bytes it occupies, so the review is not a list of zeroes")
  func anOrphanCarriesTheBytesItOccupies() async throws {
    let outcome = try await runApplicationsScan()
    let entries = orphans(in: outcome).flatMap(\.entries)
    #expect(!entries.isEmpty)
    #expect(entries.allSatisfy { $0.allocatedBytes > 0 })
  }

  // MARK: - What the sweep never touches

  @Test("a file belonging to an installed application is never an orphan")
  func aFileBelongingToAnInstalledApplicationIsNeverAnOrphan() async throws {
    let outcome = try await runApplicationsScan()
    expectCompleteScan(outcome)
    let swept = orphanedPaths(in: outcome)

    for leftover in ApplicationWorld.leftovers where leftover.owner != nil {
      #expect(
        !swept.contains(ApplicationsFixture.path(leftover.path)),
        "\(leftover.path) belongs to \(leftover.owner ?? ""), so it is not orphaned")
    }
  }

  @Test("nothing is claimed twice: no path is both a leftover and an orphan")
  func noPathIsBothALeftoverAndAnOrphan() async throws {
    let outcome = try await runApplicationsScan()
    let attributed = Set(outcome.leftoverFindings.flatMap(\.entries).map(\.path))
    #expect(attributed.intersection(orphanedPaths(in: outcome)).isEmpty)
  }

  @Test("MacGleam's own files are never swept, though nothing claims them either")
  func macGleamsOwnFilesAreNeverSwept() async throws {
    let outcome = try await runApplicationsScan()
    expectCompleteScan(outcome)
    let swept = orphanedPaths(in: outcome)

    for leftover in ApplicationWorld.runningApplicationLeftovers {
      #expect(
        !swept.contains(ApplicationsFixture.path(leftover.path)),
        """
        MacGleam is excluded from the inventory, so its own files answer to no \
        installed application. A sweep that read that absence as an orphan \
        would offer to delete the running app's own state
        """)
    }
  }

  @Test("a name that is not shaped like a bundle identifier is not swept")
  func aNameNotShapedLikeABundleIdentifierIsNotSwept() async throws {
    let outcome = try await runApplicationsScan()
    let swept = orphanedPaths(in: outcome).map(\.value)

    for path in swept {
      let name = ApplicationsFixture.path(path).lastComponent
      let isSuffixed = name.hasSuffix(".plist") || name.hasSuffix(".log")
      let identity =
        isSuffixed
        ? String(name.split(separator: ".").dropLast().joined(separator: "."))
        : name
      #expect(
        identity.split(separator: ".").count >= 3,
        """
        "\(identity)" is not the shape of a bundle identifier, and a sweep of \
        files nobody speaks for is the last place to guess
        """)
    }
  }

  @Test("a directory inside a stranger's folder is not swept, because it is not a candidate")
  func aDirectoryInsideAStrangersFolderIsNotSwept() async throws {
    let outcome = try await runApplicationsScan()
    let swept = orphanedPaths(in: outcome)
    #expect(
      !swept.contains(
        ApplicationsFixture.path("\(ApplicationWorld.caches)/Vendor/\(ApplicationWorld.mail)")))
    #expect(!swept.contains(ApplicationsFixture.path("\(ApplicationWorld.caches)/Vendor")))
  }

  @Test("a group container is swept by nothing, because it is shared by design")
  func aGroupContainerIsSweptByNothing() async throws {
    let outcome = try await runApplicationsScan()
    let swept = orphanedPaths(in: outcome)
    #expect(
      !swept.contains(
        ApplicationsFixture.path(
          "\(ApplicationWorld.groupContainers)/\(ApplicationWorld.vendorTeam).com.example")))
  }

  // MARK: - How the sweep offers itself

  @Test("no orphan is ever preselected")
  func noOrphanIsEverPreselected() async throws {
    let outcome = try await runApplicationsScan()
    let found = orphans(in: outcome)
    #expect(!found.isEmpty)
    #expect(found.allSatisfy { !$0.isPreselected })
  }

  @Test("every orphan is offered at review risk, never as safe")
  func everyOrphanIsOfferedAtReviewRisk() async throws {
    let outcome = try await runApplicationsScan()
    #expect(orphans(in: outcome).allSatisfy { $0.risk == .review })
  }

  @Test("an orphan explains itself without naming an application that is not there")
  func anOrphanExplainsItself() async throws {
    let outcome = try await runApplicationsScan()
    for finding in orphans(in: outcome) {
      try expectPlainSentence(finding.explanation)
    }
  }

  // MARK: - What removing one plans

  @Test("an orphan is planned as a trash move under the default deletion mode")
  func anOrphanIsPlannedAsATrashMove() async throws {
    let outcome = try await runApplicationsScan()
    let selection = orphans(in: outcome)
    let plan = try ApplicationsEngine().plan(
      selection: selection,
      context: makeUninstallPlanContext(
        rules: try makeSignedApplicationsCatalog(),
        settings: makeApplicationsSettings(deletionMode: .trash)))

    #expect(!plan.operations.isEmpty)
    for operation in plan.operations {
      guard case .moveToTrash = operation.kind else {
        Issue.record("the Trash default is what an orphan removal follows")
        return
      }
    }
  }

  @Test("an orphan is planned as a permanent deletion when that is the chosen mode")
  func anOrphanFollowsThePermanentMode() async throws {
    let outcome = try await runApplicationsScan()
    let plan = try ApplicationsEngine().plan(
      selection: orphans(in: outcome),
      context: makeUninstallPlanContext(
        rules: try makeSignedApplicationsCatalog(),
        settings: makeApplicationsSettings(deletionMode: .permanent)))

    for operation in plan.operations {
      guard case .deletePermanently = operation.kind else {
        Issue.record("the deletion mode decides, and it decides this one too")
        return
      }
    }
  }

  @Test("an orphan is never archived, because there is no application to restore it to")
  func anOrphanIsNeverArchived() async throws {
    let outcome = try await runApplicationsScan()
    for mode in [Settings.DeletionMode.trash, .permanent] {
      let plan = try ApplicationsEngine().plan(
        selection: orphans(in: outcome),
        context: makeUninstallPlanContext(
          rules: try makeSignedApplicationsCatalog(),
          settings: makeApplicationsSettings(deletionMode: mode)))
      #expect(
        !plan.operations.contains {
          if case .archive = $0.kind { return true }
          return false
        },
        """
        an uninstall archives because it restores an application as a unit. \
        An orphan has no application, so archiving one would fill the store \
        with items nothing can put back
        """)
    }
  }

  @Test("an uninstall selection is still archived, mode or no mode")
  func anUninstallSelectionIsStillArchived() async throws {
    let outcome = try await runApplicationsScan()
    let uninstall = outcome.findings.filter {
      if case .applicationBundle = $0.category { return true }
      if case .applicationLeftover = $0.category { return true }
      return false
    }
    let plan = try ApplicationsEngine().plan(
      selection: uninstall,
      context: makeUninstallPlanContext(
        rules: try makeSignedApplicationsCatalog(),
        settings: makeApplicationsSettings(deletionMode: .permanent)))

    #expect(!plan.operations.isEmpty)
    for operation in plan.operations {
      guard case .archive = operation.kind else {
        Issue.record("an uninstall is reversible for thirty days whatever the deletion mode says")
        return
      }
    }
  }

  @Test("a denylisted orphan is planned by nothing")
  func aDenylistedOrphanIsPlannedByNothing() async throws {
    let outcome = try await runApplicationsScan()
    let selection = orphans(in: outcome)
    let blocked = try #require(selection.first?.entries.first?.path)
    let plan = try ApplicationsEngine().plan(
      selection: selection,
      context: makeUninstallPlanContext(
        rules: try makeSignedApplicationsCatalog(blocking: [blocked.value]),
        settings: makeApplicationsSettings(deletionMode: .trash)))

    #expect(!plan.operations.contains { operationTarget(of: $0) == blocked })
  }
}

func operationTarget(of operation: GleamCore.Operation) -> AbsolutePath? {
  switch operation.kind {
  case .moveToTrash(let target), .deletePermanently(let target), .quarantine(let target),
    .archive(let target, _):
    return target
  case .setLaunchItemEnabled, .runMaintenance:
    return nil
  }
}
