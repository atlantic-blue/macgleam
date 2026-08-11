import ApplicationsEngine
import Foundation
import GleamCore
import Testing

/// The other half of C26's promise. An uninstall is only reversible if the
/// restore puts the application back in a state somebody can launch, so these
/// tests compare the disk before the uninstall with the disk after the
/// restore attribute by attribute, through C13 alone.
///
/// The guarantee being leant on is C18's: `restoreGroup` restores every
/// unrestored item of the group, or throws before moving anything if any
/// origin is occupied. This suite drives it through a real store rather than
/// a double, because the all or nothing property is the store's and a double
/// would only ever agree with whatever the uninstall did.
@Suite("Uninstall restore: the application comes back whole or not at all")
struct UninstallRestoreTests {

  private func group(of run: UninstallRun, bundleID: String) throws -> UUID {
    try #require(
      archiveGroupIDs(ofBundle: bundleID, in: run.plan, selection: run.selection).first,
      "\(bundleID) was never planned, so there is no group to restore")
  }

  @Test("restoring the group puts every file back at its original path")
  func groupRestorePutsEveryFileBack() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])

    try await run.store.restoreGroup(groupID: try group(of: run, bundleID: ApplicationWorld.mail))

    for target in run.targets {
      #expect(await run.fileSystem.exists(target), "\(target.value) did not come back")
    }
  }

  @Test("restoring the group puts every file back attribute for attribute, subtrees included")
  func groupRestoreIsFaithful() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])

    try await run.store.restoreGroup(groupID: try group(of: run, bundleID: ApplicationWorld.mail))

    try await expectSameTree(run.before, in: run.fileSystem)
  }

  /// The human check for this slice ends with "launch it". A binary that
  /// comes back without its execute bit is an application that will not
  /// start, and the store strips execute from the payload while it is in
  /// custody, so this is the case that says the stripping is undone.
  @Test("the application's binary is executable again after the restore")
  func theBinaryIsExecutableAgain() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])
    let binary = ApplicationsFixture.path(UninstallFixture.mailExecutable)
    let before = try #require(run.before[binary])
    #expect(before.posixPermissions & 0o111 != 0, "the fixture binary was never executable")

    try await run.store.restoreGroup(groupID: try group(of: run, bundleID: ApplicationWorld.mail))

    let after = try await uninstallState(of: binary, in: run.fileSystem)
    #expect(after.posixPermissions & 0o111 != 0)
    expectSamePath(after, before, at: binary)
  }

  @Test("restoring the group empties the store of that uninstall")
  func groupRestoreEmptiesTheStoreOfThatUninstall() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])
    let groupID = try group(of: run, bundleID: ApplicationWorld.mail)

    try await run.store.restoreGroup(groupID: groupID)

    let listed = try await run.store.items(includingRestored: false)
    #expect(listed.isEmpty)
    let history = try await run.store.items(includingRestored: true)
    #expect(history.isEmpty == false)
    #expect(history.allSatisfy { $0.isRestored })
  }

  // MARK: One occupied origin sinks the whole restore

  @Test("nothing moves when one origin is occupied at restore time")
  func oneOccupiedOriginLeavesEveryFileInTheStore() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])
    let occupied = ApplicationsFixture.path(
      "\(ApplicationWorld.preferences)/\(ApplicationWorld.mail).plist")
    let groupID = try group(of: run, bundleID: ApplicationWorld.mail)
    await run.fileSystem.seedFile(
      at: occupied,
      contents: UninstallFixture.occupierContents,
      isExecutable: false,
      created: ApplicationsFixture.createdDate,
      modified: ApplicationsFixture.modifiedDate,
      lastOpened: nil,
      extendedAttributes: [:]
    )

    await #expect(throws: SafetyNetError.originOccupied(occupied)) {
      try await run.store.restoreGroup(groupID: groupID)
    }

    for target in run.targets where target != occupied {
      #expect(
        !(await run.fileSystem.exists(target)),
        "\(target.value) moved back even though the restore refused")
    }
    let listed = try await run.store.items(includingRestored: false)
    #expect(storedOriginPaths(listed) == Set(run.targets))
  }

  @Test("the file occupying the origin is left exactly as it was")
  func theOccupyingFileSurvivesARefusedRestore() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])
    let occupied = ApplicationsFixture.path(
      "\(ApplicationWorld.preferences)/\(ApplicationWorld.mail).plist")
    await run.fileSystem.seedFile(
      at: occupied,
      contents: UninstallFixture.occupierContents,
      isExecutable: false,
      created: ApplicationsFixture.createdDate,
      modified: ApplicationsFixture.modifiedDate,
      lastOpened: nil,
      extendedAttributes: [:]
    )
    let occupier = try await uninstallState(of: occupied, in: run.fileSystem)

    try? await run.store.restoreGroup(
      groupID: try group(of: run, bundleID: ApplicationWorld.mail))

    let after = try await uninstallState(of: occupied, in: run.fileSystem)
    expectSamePath(after, occupier, at: occupied)
  }

  @Test("the whole application comes back once the occupying file is out of the way")
  func theRestoreSucceedsAfterTheOccupierIsRemoved() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])
    let occupied = ApplicationsFixture.path(
      "\(ApplicationWorld.preferences)/\(ApplicationWorld.mail).plist")
    let groupID = try group(of: run, bundleID: ApplicationWorld.mail)
    await run.fileSystem.seedFile(
      at: occupied,
      contents: UninstallFixture.occupierContents,
      isExecutable: false,
      created: ApplicationsFixture.createdDate,
      modified: ApplicationsFixture.modifiedDate,
      lastOpened: nil,
      extendedAttributes: [:]
    )
    try? await run.store.restoreGroup(groupID: groupID)

    try await run.fileSystem.delete(occupied)
    try await run.store.restoreGroup(groupID: groupID)

    try await expectSameTree(run.before, in: run.fileSystem)
  }

  // MARK: One group at a time

  @Test("restoring one application does not drag the other one back with it")
  func restoringOneApplicationLeavesTheOtherInTheStore() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail, ApplicationWorld.notes])
    let mailGroup = try group(of: run, bundleID: ApplicationWorld.mail)
    let notesPaths = Set(
      run.selection
        .filter { applicationBundleID(of: $0) == ApplicationWorld.notes }
        .flatMap(\.paths))

    try await run.store.restoreGroup(groupID: mailGroup)

    #expect(notesPaths.isEmpty == false)
    for path in notesPaths {
      #expect(!(await run.fileSystem.exists(path)), "\(path.value) came back uninvited")
    }
    let listed = try await run.store.items(includingRestored: false)
    #expect(storedOriginPaths(listed) == notesPaths)
  }

  @Test("the second application can still be restored afterwards, on its own")
  func theSecondApplicationRestoresAfterwards() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail, ApplicationWorld.notes])

    try await run.store.restoreGroup(groupID: try group(of: run, bundleID: ApplicationWorld.mail))
    try await run.store.restoreGroup(groupID: try group(of: run, bundleID: ApplicationWorld.notes))

    try await expectSameTree(run.before, in: run.fileSystem)
  }

  /// C18's reinstall survival clause, said in the terms this slice cares
  /// about: the uninstall outlives the application that performed it, because
  /// the manifest is written through the same file system into the store
  /// directory. A second store is what a reinstalled application is.
  @Test("an uninstall is still restorable through a store rebuilt over the same directory")
  func anUninstallSurvivesTheApplicationBeingReinstalled() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])
    let groupID = try group(of: run, bundleID: ApplicationWorld.mail)
    let rebuilt = makeUninstallSafetyNet(
      fileSystem: run.fileSystem, denylist: try await applicationsDenylist())

    let items = try await rebuilt.items(includingRestored: false)
    #expect(storedOriginPaths(items) == Set(run.targets))

    try await rebuilt.restoreGroup(groupID: groupID)

    try await expectSameTree(run.before, in: run.fileSystem)
  }

  @Test("restoring a group nothing was archived under is an error, never a quiet success")
  func restoringAnUnknownGroupIsAnError() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])
    let stranger = ApplicationsFixture.uuid(0xB9)

    await #expect(throws: SafetyNetError.groupNotFound(stranger)) {
      try await run.store.restoreGroup(groupID: stranger)
    }

    for target in run.targets {
      #expect(!(await run.fileSystem.exists(target)))
    }
  }
}
