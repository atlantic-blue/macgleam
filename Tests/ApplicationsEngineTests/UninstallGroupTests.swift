import ApplicationsEngine
import Foundation
import GleamCore
import Testing

/// C26: "one shared groupID per uninstall", and C8: "`groupID` links the items
/// of one uninstall so they restore as one unit."
///
/// The group is what makes an uninstall one thing rather than a pile of
/// deletions. Get it wrong in one direction and restoring an application
/// brings back only part of it; get it wrong in the other and restoring one
/// application drags a second one back from the store with it.
@Suite("Uninstall groups: one uninstall, one group")
struct UninstallGroupTests {

  @Test("every archive operation of one application's uninstall carries the same group")
  func oneApplicationIsOneGroup() async throws {
    let setup = try await uninstallSetup()
    let selection = uninstallSelection(of: [ApplicationWorld.mail], in: setup.outcome)

    let plan = try ApplicationsEngine().plan(
      selection: selection, context: makeUninstallPlanContext(rules: setup.catalog))

    #expect(plan.operations.count > 1, "the mail fixture covers a bundle and seven leftovers")
    #expect(archiveGroupIDs(in: plan).count == 1)
  }

  @Test("every archive operation carries a group identifier at all")
  func everyArchiveOperationCarriesAGroup() async throws {
    let setup = try await uninstallSetup()
    let selection = uninstallSelection(of: [ApplicationWorld.mail], in: setup.outcome)

    let plan = try ApplicationsEngine().plan(
      selection: selection, context: makeUninstallPlanContext(rules: setup.catalog))

    #expect(plan.operations.isEmpty == false)
    #expect(
      plan.operations.compactMap(archiveGroupID).count == plan.operations.count,
      "an archive with no group is a file that can only be restored on its own")
  }

  @Test("two applications uninstalled together are two groups, never one")
  func twoApplicationsAreTwoGroups() async throws {
    let setup = try await uninstallSetup()
    let selection = uninstallSelection(
      of: [ApplicationWorld.mail, ApplicationWorld.notes], in: setup.outcome)

    let plan = try ApplicationsEngine().plan(
      selection: selection, context: makeUninstallPlanContext(rules: setup.catalog))

    let mailGroups = archiveGroupIDs(
      ofBundle: ApplicationWorld.mail, in: plan, selection: selection)
    let notesGroups = archiveGroupIDs(
      ofBundle: ApplicationWorld.notes, in: plan, selection: selection)
    #expect(mailGroups.count == 1)
    #expect(notesGroups.count == 1)
    #expect(mailGroups.isDisjoint(with: notesGroups))
    #expect(archiveGroupIDs(in: plan).count == 2)
  }

  @Test("three applications uninstalled together are three groups")
  func threeApplicationsAreThreeGroups() async throws {
    let setup = try await uninstallSetup()
    let bundleIDs = [ApplicationWorld.mail, ApplicationWorld.notes, ApplicationWorld.mailer]
    let selection = uninstallSelection(of: bundleIDs, in: setup.outcome)

    let plan = try ApplicationsEngine().plan(
      selection: selection, context: makeUninstallPlanContext(rules: setup.catalog))

    #expect(archiveGroupIDs(in: plan).count == 3)
    for bundleID in bundleIDs {
      #expect(
        archiveGroupIDs(ofBundle: bundleID, in: plan, selection: selection).count == 1,
        "\(bundleID) was spread across more than one group")
    }
  }

  @Test("a bundle row and its leftover rows share one group")
  func theBundleAndItsLeftoversShareOneGroup() async throws {
    let setup = try await uninstallSetup()
    let selection = uninstallSelection(of: [ApplicationWorld.mail], in: setup.outcome)
    let bundlePath = ApplicationsFixture.path("/Applications/ExampleMail.app")
    let preferencesPath = ApplicationsFixture.path(
      "\(ApplicationWorld.preferences)/\(ApplicationWorld.mail).plist")

    let plan = try ApplicationsEngine().plan(
      selection: selection, context: makeUninstallPlanContext(rules: setup.catalog))

    let bundleOperation = try #require(
      plan.operations.first { archiveTarget(of: $0) == bundlePath })
    let preferencesOperation = try #require(
      plan.operations.first { archiveTarget(of: $0) == preferencesPath })
    #expect(archiveGroupID(of: bundleOperation) == archiveGroupID(of: preferencesOperation))
  }

  /// Two uninstalls of the same application are two units. A group derived
  /// from the bundle identifier rather than from this uninstall would let a
  /// restore reach back into an older uninstall's items and bring them along.
  @Test("planning the same application twice produces two different groups")
  func twoPlansOfTheSameApplicationAreTwoGroups() async throws {
    let setup = try await uninstallSetup()
    let selection = uninstallSelection(of: [ApplicationWorld.mail], in: setup.outcome)
    let context = makeUninstallPlanContext(rules: setup.catalog)

    let first = try ApplicationsEngine().plan(selection: selection, context: context)
    let second = try ApplicationsEngine().plan(selection: selection, context: context)

    #expect(archiveGroupIDs(in: first).count == 1)
    #expect(archiveGroupIDs(in: second).count == 1)
    #expect(archiveGroupIDs(in: first).isDisjoint(with: archiveGroupIDs(in: second)))
  }

  @Test("the store records every archived file of one uninstall under that plan's group")
  func theStoreRecordsThePlansGroup() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])
    let plannedGroup = try #require(archiveGroupIDs(in: run.plan).first)

    let items = try await run.store.items(includingRestored: false)

    #expect(items.isEmpty == false)
    for item in items {
      #expect(item.groupID == plannedGroup, "\(item.originPath.value) landed in another group")
      #expect(item.source == .uninstallArchive)
    }
  }

  @Test("two applications uninstalled in one run land in the store as two groups")
  func twoApplicationsLandAsTwoGroupsInTheStore() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail, ApplicationWorld.notes])
    let mailGroup = try #require(
      archiveGroupIDs(ofBundle: ApplicationWorld.mail, in: run.plan, selection: run.selection)
        .first)
    let notesGroup = try #require(
      archiveGroupIDs(ofBundle: ApplicationWorld.notes, in: run.plan, selection: run.selection)
        .first)

    let items = try await run.store.items(includingRestored: false)

    #expect(Set(items.compactMap(\.groupID)) == [mailGroup, notesGroup])
    let notesContainer = ApplicationsFixture.path(
      "\(ApplicationWorld.containers)/\(ApplicationWorld.notes)")
    #expect(storedItem(forOrigin: notesContainer, in: items)?.groupID == notesGroup)
  }
}
