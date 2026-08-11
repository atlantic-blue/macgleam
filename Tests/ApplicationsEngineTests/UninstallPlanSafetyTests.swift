import ApplicationsEngine
import Foundation
import GleamCore
import Testing

/// The safety property of the Applications module, from C26: "Archive first:
/// `plan` for an uninstall emits only `archive` operations. There is no
/// separate delete step, so the whole uninstall is reversible for 30 days as
/// one unit. A test asserts no uninstall plan ever contains `moveToTrash` or
/// `deletePermanently`."
///
/// An uninstall is sold as reversible. A trash operation in the plan is
/// recoverable only until somebody empties the trash, and a permanent one is
/// not recoverable at all, so either would make the uninstall partly
/// irreversible while the interface still promised thirty days. That is a
/// promise broken silently, which is why this is pinned structurally rather
/// than by example: the sweep covers every selection the scan's own findings
/// can make, in both deletion modes, and then tries to coax a removal out of
/// the plan builder with findings that have been tampered with and with
/// findings from other modules.
@Suite("Uninstall plans: archive only, never a trash or a permanent delete")
struct UninstallPlanSafetyTests {

  /// A pool small enough to sweep exhaustively and wide enough to be worth
  /// sweeping: three applications, each contributing its bundle row and one
  /// leftover row. The count is asserted so that a change in how findings are
  /// split fails here loudly rather than quietly turning this sweep into
  /// something that takes an hour.
  private func sweepPool(in outcome: ScanOutcome) throws -> [Finding] {
    var pool: [Finding] = []
    for bundleID in [ApplicationWorld.mail, ApplicationWorld.notes, ApplicationWorld.mailer] {
      let findings = uninstallFindings(of: bundleID, in: outcome)
      let bundle = try #require(
        findings.first { applicationBundleID(of: $0) == bundleID },
        "the scan offered no row at all for \(bundleID)")
      let leftover = try #require(
        findings.first { finding in
          if case .applicationLeftover = finding.category { return true }
          return false
        },
        "the scan offered no leftover row for \(bundleID)")
      pool.append(contentsOf: [bundle, leftover])
    }
    #expect(pool.count == 6)
    return pool
  }

  // MARK: The whole generated plan space

  @Test("every selection of the scan's own rows plans archives and nothing else")
  func everySelectionOfScannedFindingsPlansOnlyArchives() async throws {
    let setup = try await uninstallSetup()
    let pool = try sweepPool(in: setup.outcome)

    for mode in [Settings.DeletionMode.trash, .permanent] {
      let context = makeUninstallPlanContext(
        rules: setup.catalog, settings: makeApplicationsSettings(deletionMode: mode))
      for selection in everySelection(of: pool) {
        let plan = try ApplicationsEngine().plan(selection: selection, context: context)

        expectArchiveOnly(in: plan)
        #expect(
          archiveTargets(in: plan) == uninstallPaths(of: selection),
          "one archive per selected path, in selection order, in \(mode.rawValue)")
      }
    }
  }

  /// The whole review at once, which is the selection a person makes when
  /// they tick everything the scan offered. The sweep above trades breadth
  /// for depth; this one takes the widest single selection there is.
  @Test("selecting every application the scan offered still plans archives and nothing else")
  func selectingEverythingPlansOnlyArchives() async throws {
    let setup = try await uninstallSetup()

    for mode in [Settings.DeletionMode.trash, .permanent] {
      let plan = try ApplicationsEngine().plan(
        selection: setup.outcome.findings,
        context: makeUninstallPlanContext(
          rules: setup.catalog, settings: makeApplicationsSettings(deletionMode: mode))
      )

      expectArchiveOnly(in: plan)
      #expect(plan.operations.isEmpty == false)
    }
  }

  /// Permanent deletion is a setting somebody turns on to stop junk piling up
  /// in the trash. It must not reach across and make an uninstall
  /// irreversible, because nobody choosing it was told it would.
  @Test("permanent deletion mode plans exactly the same archives as trash mode")
  func permanentDeletionModeChangesNothingAboutAnUninstall() async throws {
    let setup = try await uninstallSetup()
    let selection = uninstallSelection(of: [ApplicationWorld.mail], in: setup.outcome)

    let trashed = try ApplicationsEngine().plan(
      selection: selection,
      context: makeUninstallPlanContext(
        rules: setup.catalog, settings: makeApplicationsSettings(deletionMode: .trash)))
    let permanent = try ApplicationsEngine().plan(
      selection: selection,
      context: makeUninstallPlanContext(
        rules: setup.catalog, settings: makeApplicationsSettings(deletionMode: .permanent)))

    expectArchiveOnly(in: permanent)
    #expect(archiveTargets(in: trashed).isEmpty == false)
    #expect(archiveTargets(in: permanent) == archiveTargets(in: trashed))
    #expect(permanent.totalBytes == trashed.totalBytes)
  }

  @Test("no permanent deletion confirmation is ever attached to an uninstall plan")
  func anUninstallPlanCarriesNoPermanentDeletionConfirmation() async throws {
    let setup = try await uninstallSetup()

    let plan = try ApplicationsEngine().plan(
      selection: uninstallSelection(
        of: [ApplicationWorld.mail, ApplicationWorld.notes], in: setup.outcome),
      context: makeUninstallPlanContext(
        rules: setup.catalog, settings: makeApplicationsSettings(deletionMode: .permanent))
    )

    #expect(plan.operations.isEmpty == false)
    #expect(plan.permanentDeletionConfirmation == nil)
  }

  // MARK: Selections drawn from other modules

  @Test("no selection drawn from a pool that mixes in other modules' rows yields a removal")
  func noSelectionFromAMixedPoolYieldsARemoval() async throws {
    let setup = try await uninstallSetup()
    let mail = uninstallFindings(of: ApplicationWorld.mail, in: setup.outcome)
    let pool =
      Array(mail.prefix(2)) + [
        makeForeignFinding(
          id: ApplicationsFixture.uuid(0x51),
          category: .userCache,
          paths: ["\(ApplicationWorld.caches)/\(ApplicationWorld.mail)"]),
        makeForeignFinding(
          id: ApplicationsFixture.uuid(0x52),
          category: .largeFile,
          paths: ["\(ApplicationWorld.logs)/\(ApplicationWorld.mail).log"]),
        makeForeignFinding(
          id: ApplicationsFixture.uuid(0x53),
          category: .maintenanceTask(task: .flushDomainNameSystemCache),
          paths: ["\(ApplicationWorld.preferences)/\(ApplicationWorld.mail).plist"]),
      ]
    #expect(pool.count == 5)

    let scannedRows = Set(mail.prefix(2).map(\.id))
    for mode in [Settings.DeletionMode.trash, .permanent] {
      let context = makeUninstallPlanContext(
        rules: setup.catalog, settings: makeApplicationsSettings(deletionMode: mode))
      for selection in everySelection(of: pool) {
        let plan = planExpectingArchiveOnly(selection, context: context)

        // Without this the whole sweep would pass against a plan builder that
        // produced nothing at all, which is not what "never a removal" means.
        if let plan, selection.contains(where: { scannedRows.contains($0.id) }) {
          #expect(
            plan.operations.isEmpty == false,
            "a selection carrying a real application row planned nothing in \(mode.rawValue)")
        }
      }
    }
  }

  @Test(
    "a browser history row, which plans as a permanent delete in its own module, plans no delete here"
  )
  func aPrivacyRowPlansNoPermanentDeleteHere() async throws {
    let setup = try await uninstallSetup()
    let privacy = makeForeignFinding(
      id: ApplicationsFixture.uuid(0x54),
      category: .browserHistory(browser: "Safari"),
      paths: ["\(ApplicationWorld.applicationSupport)/\(ApplicationWorld.mail)"],
      isPreselected: false
    )

    planExpectingArchiveOnly(
      [privacy],
      context: makeUninstallPlanContext(
        rules: setup.catalog, settings: makeApplicationsSettings(deletionMode: .permanent)))
  }

  // MARK: Rows tampered with to look like something else

  @Test(
    "a bundle row tampered with to name a stranger's file still plans an archive, never a delete")
  func aTamperedBundleRowPlansAnArchive() async throws {
    let setup = try await uninstallSetup()
    let tampered = makeApplicationFinding(
      category: .applicationBundle(bundleID: ApplicationWorld.mail),
      paths: [
        "/Applications/ExampleMail.app",
        "\(ApplicationWorld.preferences)/\(ApplicationWorld.mail)_backup.plist",
      ]
    )

    let plan = planExpectingArchiveOnly(
      [tampered], context: makeUninstallPlanContext(rules: setup.catalog))

    if let plan {
      #expect(
        plan.operations.isEmpty == false,
        "the row named a real bundle, so a plan that names nothing proves nothing")
      #expect(
        plan.operations.allSatisfy { isArchive($0.kind) },
        "a path smuggled into a bundle row is still archived, so it is still reversible")
    }
  }

  @Test("a leftover row tampered with to carry an application bundle path plans an archive")
  func aTamperedLeftoverRowPlansAnArchive() async throws {
    let setup = try await uninstallSetup()
    let tampered = makeApplicationFinding(
      category: .applicationLeftover(bundleID: ApplicationWorld.notes),
      paths: ["/Applications/ExampleSolo.app"]
    )

    let plan = planExpectingArchiveOnly(
      [tampered], context: makeUninstallPlanContext(rules: setup.catalog))

    if let plan {
      #expect(plan.operations.isEmpty == false)
      #expect(
        archiveTargets(in: plan) == [ApplicationsFixture.path("/Applications/ExampleSolo.app")])
    }
  }

  @Test("a row claiming an orphaned leftover plans no trash operation in this module's plan")
  func anOrphanRowPlansNoTrashHere() async throws {
    let setup = try await uninstallSetup()
    // The leftover sweep (s4d) removes orphans with the Trash default. That
    // is a different plan for a different review; smuggling an orphan row
    // into an uninstall must not import its removal.
    let orphan = makeApplicationFinding(
      category: .orphanedLeftover,
      paths: ["\(ApplicationWorld.preferences)/\(ApplicationWorld.ghost).plist"]
    )

    planExpectingArchiveOnly(
      [orphan],
      context: makeUninstallPlanContext(
        rules: setup.catalog, settings: makeApplicationsSettings(deletionMode: .permanent)))
  }

  // MARK: The running application

  /// The forged row is selected alongside a real application, so a plan
  /// builder that answered by producing nothing would fail the first
  /// expectation rather than pass the second for free.
  @Test("a forged row naming MacGleam's own bundle plans nothing against it")
  func aForgedRowNamingMacGleamPlansNothingAgainstIt() async throws {
    let setup = try await uninstallSetup()
    let macGleamBundle = ApplicationsFixture.path("/Applications/MacGleam.app")
    let forged = makeApplicationFinding(
      category: .applicationBundle(bundleID: ApplicationsEngine.macGleamBundleID),
      paths: [
        "/Applications/MacGleam.app",
        "\(ApplicationWorld.preferences)/\(ApplicationsEngine.macGleamBundleID).plist",
      ]
    )
    let real = uninstallSelection(of: [ApplicationWorld.solo], in: setup.outcome)

    let plan = planExpectingArchiveOnly(
      real + [forged], context: makeUninstallPlanContext(rules: setup.catalog))

    if let plan {
      #expect(
        archiveTargets(in: plan).contains(
          ApplicationsFixture.path("/Applications/ExampleSolo.app")),
        "the real application in the selection was planned")
    }
    #expect(
      plan?.operations.contains { archiveTarget(of: $0) == macGleamBundle } != true,
      "C26: MacGleam is never offered for uninstall, so no plan may target its own bundle")
  }
}
