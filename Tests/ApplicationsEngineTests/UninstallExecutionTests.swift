import ApplicationsEngine
import Foundation
import GleamCore
import Testing

/// The uninstall as it actually happens: the engine's plan, the real executor
/// (C17) and the real SafetyNet store (C18) over one in memory disk.
///
/// C26 says the archive move is the removal, so there is no window in which a
/// file is deleted but not archived. That is only observable end to end:
/// after the run, every file the review named is in the store and none of them
/// is where it used to be, and those two halves are asserted separately
/// because a run that lost a file would satisfy the second on its own.
@Suite("Uninstall execution: everything lands in the SafetyNet")
struct UninstallExecutionTests {

  @Test("the plan runs to completion with one result per operation, in plan order")
  func theReportAccountsForEveryOperationInOrder() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])

    let report = try #require(uninstallFinalReport(in: run.events))
    #expect(report.planID == run.plan.id)
    #expect(report.results.map(\.operationID) == run.plan.operations.map(\.id))
    #expect(report.results.allSatisfy { isCompleted($0.result) })
  }

  @Test("the application bundle is gone from where it was installed")
  func theBundleIsGoneFromItsInstallLocation() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])
    let bundle = ApplicationsFixture.path("/Applications/ExampleMail.app")

    #expect(run.targets.contains(bundle), "the uninstall did not even plan the bundle")
    #expect(!(await run.fileSystem.exists(bundle)))
  }

  @Test("every attributed leftover is gone from its original path")
  func everyLeftoverIsGoneFromItsOriginalPath() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])

    let expected = ApplicationWorld.expectedLeftoverPaths(of: ApplicationWorld.mail)
    #expect(expected.isEmpty == false)
    #expect(expected.isSubset(of: Set(run.targets)), "some leftovers were never planned")
    for path in expected {
      #expect(!(await run.fileSystem.exists(path)), "\(path.value) is still where it was")
    }
  }

  @Test("the whole bundle moved, not just its top level directory")
  func theWholeBundleSubtreeMoved() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])

    for path in [UninstallFixture.mailExecutable, "/Applications/ExampleMail.app/Contents"] {
      #expect(!(await run.fileSystem.exists(ApplicationsFixture.path(path))))
    }
  }

  @Test("every file the uninstall named is in the SafetyNet, under an uninstall archive")
  func everyTargetIsInTheSafetyNet() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])

    let items = try await run.store.items(includingRestored: false)

    #expect(storedOriginPaths(items) == Set(run.targets))
    #expect(items.allSatisfy { $0.source == .uninstallArchive })
    for item in items {
      #expect(
        await run.fileSystem.exists(item.storedPath),
        "\(item.originPath.value) is listed but its payload is nowhere")
    }
  }

  @Test("nothing an uninstall touches goes to the trash")
  func nothingGoesToTheTrash() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])

    for name in ["ExampleMail.app", "\(ApplicationWorld.mail).plist", ApplicationWorld.mail] {
      #expect(!(await run.fileSystem.exists(ApplicationsFixture.path("/.Trash/\(name)"))))
    }
  }

  @Test("an item keeps the dates the store's injected clock gave it, never a wall clock")
  func storedItemsCarryTheInjectedInstant() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])

    let items = try await run.store.items(includingRestored: false)

    #expect(items.isEmpty == false)
    for item in items {
      #expect(item.storedAt == UninstallFixture.storeInstant)
      #expect(item.expiresAt == UninstallFixture.storeInstant.addingTimeInterval(30 * 86_400))
      #expect(item.isRestored == false)
    }
  }

  @Test("two applications uninstalled together both leave their original paths empty")
  func twoApplicationsBothLeaveTheirPathsEmpty() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail, ApplicationWorld.notes])

    #expect(run.targets.count > 8)
    for target in run.targets {
      #expect(!(await run.fileSystem.exists(target)), "\(target.value) is still where it was")
    }
    let items = try await run.store.items(includingRestored: false)
    #expect(storedOriginPaths(items) == Set(run.targets))
  }

  @Test("an application nobody selected is untouched by somebody else's uninstall")
  func anUnselectedApplicationIsUntouched() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])

    for path in ApplicationWorld.expectedLeftoverPaths(of: ApplicationWorld.mailer) {
      #expect(await run.fileSystem.exists(path), "\(path.value) belonged to another application")
    }
    #expect(
      await run.fileSystem.exists(ApplicationsFixture.path("/Applications/ExampleMailer.app")))
    #expect(await run.fileSystem.exists(ApplicationsFixture.path("/Applications/MacGleam.app")))
  }

  @Test("a path that belongs to nobody survives an uninstall of every application on the disk")
  func unattributablePathsSurviveAWholesaleUninstall() async throws {
    let setup = try await uninstallSetup()
    // Every uninstall row, and no swept orphan: the sweep is a separate
    // review a person ticks separately, and what this pins is that
    // uninstalling everything installed never reaches a file nobody claimed.
    let selection = setup.outcome.findings.filter { applicationBundleID(of: $0) != nil }
    let plan = try ApplicationsEngine().plan(
      selection: selection, context: makeUninstallPlanContext(rules: setup.catalog))
    #expect(plan.operations.isEmpty == false, "nothing was planned, so nothing was proved")
    let denylist = try await applicationsDenylist()
    let store = makeUninstallSafetyNet(fileSystem: setup.fileSystem, denylist: denylist)
    let executor = makeUninstallExecutor(
      fileSystem: setup.fileSystem, denylist: denylist, safetyNet: store)

    for await _ in executor.execute(plan) {}

    #expect(ApplicationWorld.unattributablePaths.isEmpty == false)
    for path in ApplicationWorld.unattributablePaths {
      #expect(
        await setup.fileSystem.exists(path),
        "\(path.value) belongs to nobody and an uninstall took it anyway")
    }
  }

  @Test("a swept orphan goes to the Trash, and the files an application owns stay put")
  func aSweptOrphanGoesToTheTrash() async throws {
    let setup = try await uninstallSetup()
    let orphans = setup.outcome.findings.filter { $0.category == .orphanedLeftover }
    let plan = try ApplicationsEngine().plan(
      selection: orphans, context: makeUninstallPlanContext(rules: setup.catalog))
    #expect(plan.operations.isEmpty == false, "nothing was planned, so nothing was proved")
    let denylist = try await applicationsDenylist()
    let store = makeUninstallSafetyNet(fileSystem: setup.fileSystem, denylist: denylist)
    let executor = makeUninstallExecutor(
      fileSystem: setup.fileSystem, denylist: denylist, safetyNet: store)

    for await _ in executor.execute(plan) {}

    let swept = Set(orphans.flatMap(\.entries).map(\.path))
    #expect(swept.isEmpty == false)
    for path in swept {
      #expect(
        await !setup.fileSystem.exists(path),
        "\(path.value) was swept, so it is not where it was")
    }
    for path in ApplicationWorld.expectedLeftoverPaths(of: ApplicationWorld.mail) {
      #expect(
        await setup.fileSystem.exists(path),
        "\(path.value) belongs to an installed application and a sweep never touches it")
    }
    #expect(
      await setup.fileSystem.exists(ApplicationsFixture.path("/Applications/ExampleMail.app")))
    #expect(
      try await store.items(includingRestored: true).isEmpty,
      "a sweep is a removal, so nothing about it fills the SafetyNet")
  }
}
