import ApplicationsEngine
import Foundation
import GleamCore
import Testing

/// The plan mechanics every engine shares (C6, C15, C16) as the uninstall
/// meets them, plus C26's itemisation rule: the review names the bundle and
/// every leftover, and nothing is hidden inside a total.
@Suite("Uninstall plans: session, denylist, order and accounting")
struct UninstallPlanMechanicsTests {

  // MARK: Refusals

  @Test("planning nothing throws emptySelection rather than an empty plan")
  func planningNothingThrowsEmptySelection() async throws {
    let setup = try await uninstallSetup()

    #expect(throws: PlanningError.emptySelection) {
      _ = try ApplicationsEngine().plan(
        selection: [], context: makeUninstallPlanContext(rules: setup.catalog))
    }
  }

  /// C15 fixes the payload: the identifier is the offending finding's, never
  /// the session's, because a caller reconciling a refusal needs to know which
  /// row to drop and a session identifier cannot tell them. The row's
  /// identifier, its session and the context's session are three distinct
  /// fixture values, so this equality discriminates between them.
  @Test("a row from another session is refused, naming the row rather than the session")
  func aFindingFromAnotherSessionIsRefused() async throws {
    let setup = try await uninstallSetup()
    let stray = makeApplicationFinding(
      id: ApplicationsFixture.uuid(0xD2),
      sessionID: ApplicationsFixture.otherSessionID,
      category: .applicationBundle(bundleID: ApplicationWorld.solo),
      paths: ["/Applications/ExampleSolo.app"]
    )

    #expect(throws: PlanningError.findingFromDifferentSession(stray.id)) {
      _ = try ApplicationsEngine().plan(
        selection: [stray], context: makeUninstallPlanContext(rules: setup.catalog))
    }
  }

  @Test("a refusal produces no partial plan, so nothing from the good half survives")
  func aRefusalProducesNoPartialPlan() async throws {
    let setup = try await uninstallSetup()
    let selection = uninstallSelection(of: [ApplicationWorld.mail], in: setup.outcome)
    let stray = makeApplicationFinding(
      sessionID: ApplicationsFixture.otherSessionID,
      category: .applicationLeftover(bundleID: ApplicationWorld.solo),
      paths: ["\(ApplicationWorld.preferences)/\(ApplicationWorld.solo).plist"]
    )

    #expect(throws: PlanningError.self) {
      _ = try ApplicationsEngine().plan(
        selection: selection + [stray],
        context: makeUninstallPlanContext(rules: setup.catalog))
    }
  }

  // MARK: The denylist

  /// The selections here are built by hand rather than scanned, because the
  /// question is what the plan builder does with a blocked path in front of
  /// it. A scan that had already dropped the path would answer nothing.
  @Test("a denylisted path is never planned, and the rest of the selection still is")
  func aDenylistedPathIsNeverPlanned() async throws {
    let blocked = "\(ApplicationWorld.preferences)/\(ApplicationWorld.mail).plist"
    let allowed = "\(ApplicationWorld.logs)/\(ApplicationWorld.mail).log"
    let setup = try await uninstallSetup(blocking: [blocked])
    let hostile = makeApplicationFinding(
      category: .applicationLeftover(bundleID: ApplicationWorld.mail),
      paths: [allowed, blocked]
    )

    let plan = try ApplicationsEngine().plan(
      selection: [hostile], context: makeUninstallPlanContext(rules: setup.catalog))

    #expect(archiveTargets(in: plan) == [ApplicationsFixture.path(allowed)])
    #expect(!archiveTargets(in: plan).contains(ApplicationsFixture.path(blocked)))
  }

  @Test("a path inside a denylisted directory is never planned either")
  func aDescendantOfADenylistedDirectoryIsNeverPlanned() async throws {
    let setup = try await uninstallSetup(blocking: [ApplicationWorld.preferences])
    let blocked = "\(ApplicationWorld.preferences)/\(ApplicationWorld.mail).plist"
    let hostile = makeApplicationFinding(
      category: .applicationLeftover(bundleID: ApplicationWorld.mail),
      paths: ["\(ApplicationWorld.logs)/\(ApplicationWorld.mail).log", blocked]
    )

    let plan = try ApplicationsEngine().plan(
      selection: [hostile], context: makeUninstallPlanContext(rules: setup.catalog))

    #expect(!archiveTargets(in: plan).contains(ApplicationsFixture.path(blocked)))
    #expect(archiveTargets(in: plan).isEmpty == false)
  }

  @Test("the bytes of a denylisted path are excluded from the plan's total exactly")
  func denylistedBytesAreExcludedExactly() async throws {
    let blocked = "\(ApplicationWorld.preferences)/\(ApplicationWorld.mail).plist"
    let allowed = "\(ApplicationWorld.logs)/\(ApplicationWorld.mail).log"
    let setup = try await uninstallSetup(blocking: [blocked])
    let hostile = makeApplicationFinding(
      category: .applicationLeftover(bundleID: ApplicationWorld.mail),
      paths: [allowed, blocked],
      bytesEach: 4_096
    )

    let plan = try ApplicationsEngine().plan(
      selection: [hostile], context: makeUninstallPlanContext(rules: setup.catalog))

    #expect(
      plan.totalBytes == 4_096,
      "the blocked entry's bytes are excluded exactly, never apportioned or estimated")
  }

  @Test("a denylist that blocks the whole disk plans no operation at all")
  func aTotalDenylistPlansNothing() async throws {
    let setup = try await uninstallSetup(blocking: ["/**"])
    let hostile = makeApplicationFinding(
      category: .applicationBundle(bundleID: ApplicationWorld.mail),
      paths: ["/Applications/ExampleMail.app"]
    )

    let plan = planExpectingArchiveOnly(
      [hostile], context: makeUninstallPlanContext(rules: setup.catalog))

    if let plan {
      #expect(plan.operations.isEmpty)
      #expect(plan.totalBytes == 0)
    }
  }

  // MARK: Itemisation and accounting

  @Test("every path the review named becomes its own archive, so nothing hides inside a total")
  func everyReviewedPathBecomesItsOwnOperation() async throws {
    let setup = try await uninstallSetup()
    let selection = uninstallSelection(of: [ApplicationWorld.mail], in: setup.outcome)
    let reviewed = uninstallPaths(of: selection)

    let plan = try ApplicationsEngine().plan(
      selection: selection, context: makeUninstallPlanContext(rules: setup.catalog))

    #expect(plan.operations.count == reviewed.count)
    #expect(Set(archiveTargets(in: plan)) == Set(reviewed))
    #expect(
      Set(reviewed).contains(ApplicationsFixture.path("/Applications/ExampleMail.app")),
      "the bundle itself is one of the itemised rows")
  }

  /// C6: the total is the sum, over the operations, of the allocatedBytes of
  /// the finding entry each one targets. Read off the entries rather than off
  /// the disk, because that is what the contract states and what the review
  /// screen showed the person before they agreed to it.
  @Test("the plan's byte total is the sum of its targets' entries")
  func planBytesAreTheSumOfItsTargetsEntries() async throws {
    let setup = try await uninstallSetup()
    let selection = uninstallSelection(of: [ApplicationWorld.mail], in: setup.outcome)

    let plan = try ApplicationsEngine().plan(
      selection: selection, context: makeUninstallPlanContext(rules: setup.catalog))

    let targeted = Set(archiveTargets(in: plan))
    let expected =
      selection
      .flatMap(\.entries)
      .filter { targeted.contains($0.path) }
      .reduce(UInt64(0)) { $0 + $1.allocatedBytes }
    #expect(expected > 0)
    #expect(plan.totalBytes == expected)
  }

  /// And the entries themselves are the disk, so the figure a person is shown
  /// is the figure the volume holds rather than an estimate carried forward.
  @Test("the bundle's entry carries the allocated total of the whole application")
  func theBundleEntryCarriesTheWholeApplicationsBytes() async throws {
    let setup = try await uninstallSetup()
    let selection = uninstallSelection(of: [ApplicationWorld.mail], in: setup.outcome)
    let bundle = ApplicationsFixture.path("/Applications/ExampleMail.app")

    let entry = try #require(
      selection.flatMap(\.entries).first { $0.path == bundle },
      "the review named no entry for the bundle itself")

    let onDisk = try await allocatedTotal(of: bundle, on: setup.fileSystem)
    #expect(onDisk > 0)
    #expect(entry.allocatedBytes == onDisk)
  }

  @Test("every operation carries the identifier of the row it came from")
  func everyOperationCarriesItsFindingIdentifier() async throws {
    let setup = try await uninstallSetup()
    let selection = uninstallSelection(
      of: [ApplicationWorld.mail, ApplicationWorld.notes], in: setup.outcome)

    let plan = try ApplicationsEngine().plan(
      selection: selection, context: makeUninstallPlanContext(rules: setup.catalog))

    #expect(plan.operations.isEmpty == false)
    for operation in plan.operations {
      let target = try #require(archiveTarget(of: operation))
      let owner = try #require(
        selection.first { $0.id == operation.findingID },
        "operation \(operation.id) came from no row in the selection")
      #expect(
        owner.paths.contains(target),
        "\(target.value) was attributed to a row that never named it")
    }
  }

  @Test("the plan rides the session the context named, never the findings'")
  func thePlanRidesTheContextSession() async throws {
    let setup = try await uninstallSetup(sessionID: ApplicationsFixture.otherSessionID)
    let selection = uninstallSelection(of: [ApplicationWorld.mail], in: setup.outcome)

    let plan = try ApplicationsEngine().plan(
      selection: selection,
      context: makeUninstallPlanContext(
        rules: setup.catalog, sessionID: ApplicationsFixture.otherSessionID))

    #expect(plan.sessionID == ApplicationsFixture.otherSessionID)
  }

  // MARK: Order

  @Test("operations follow the selection, row by row and path by path")
  func operationsFollowTheSelectionOrder() async throws {
    let setup = try await uninstallSetup()
    let selection = uninstallSelection(
      of: [ApplicationWorld.mail, ApplicationWorld.notes], in: setup.outcome)

    let plan = try ApplicationsEngine().plan(
      selection: selection, context: makeUninstallPlanContext(rules: setup.catalog))

    #expect(archiveTargets(in: plan) == uninstallPaths(of: selection))
  }

  @Test("a selection given in the other order plans in that other order")
  func aReorderedSelectionPlansInThatOrder() async throws {
    let setup = try await uninstallSetup()
    let forwards = uninstallSelection(
      of: [ApplicationWorld.mail, ApplicationWorld.notes], in: setup.outcome)
    let backwards = uninstallSelection(
      of: [ApplicationWorld.notes, ApplicationWorld.mail], in: setup.outcome)
    let context = makeUninstallPlanContext(rules: setup.catalog)

    let first = try ApplicationsEngine().plan(selection: forwards, context: context)
    let second = try ApplicationsEngine().plan(selection: backwards, context: context)

    #expect(archiveTargets(in: first) == uninstallPaths(of: forwards))
    #expect(archiveTargets(in: second) == uninstallPaths(of: backwards))
    #expect(Set(archiveTargets(in: first)) == Set(archiveTargets(in: second)))
  }

  @Test("planning the same selection twice plans the same operations in the same order")
  func planningTwiceIsDeterministic() async throws {
    let setup = try await uninstallSetup()
    let selection = uninstallSelection(of: [ApplicationWorld.mail], in: setup.outcome)
    let context = makeUninstallPlanContext(rules: setup.catalog)

    let first = try ApplicationsEngine().plan(selection: selection, context: context)
    let second = try ApplicationsEngine().plan(selection: selection, context: context)

    #expect(first.operations.isEmpty == false)
    #expect(archiveTargets(in: first) == archiveTargets(in: second))
    #expect(first.operations.map(\.findingID) == second.operations.map(\.findingID))
    #expect(first.operations.map(\.privilege) == second.operations.map(\.privilege))
    #expect(first.totalBytes == second.totalBytes)
  }

  // MARK: Privilege

  @Test("privilege comes from the path ownership policy, one answer per path")
  func privilegeComesFromTheOwnershipPolicy() async throws {
    let setup = try await uninstallSetup()
    let selection = uninstallSelection(of: [ApplicationWorld.mail], in: setup.outcome)
    let daemon = ApplicationsFixture.path(
      "\(ApplicationWorld.systemLaunchDaemons)/\(ApplicationWorld.mail).plist")
    let preferences = ApplicationsFixture.path(
      "\(ApplicationWorld.preferences)/\(ApplicationWorld.mail).plist")

    let plan = try ApplicationsEngine().plan(
      selection: selection,
      context: makeUninstallPlanContext(
        rules: setup.catalog, ownership: UninstallHomeOwnershipPolicy())
    )

    let daemonOperation = try #require(plan.operations.first { archiveTarget(of: $0) == daemon })
    let preferencesOperation = try #require(
      plan.operations.first { archiveTarget(of: $0) == preferences })
    #expect(daemonOperation.privilege == .root)
    #expect(preferencesOperation.privilege == .user)
  }
}
