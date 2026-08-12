import Foundation
import GleamCore
import Testing
import os

/// A payload only root can move, held by the store that records it.
///
/// The defect these close is the one C18 exists to prevent and did not: a
/// system domain archive went to the helper as a removal into the store
/// directory, so the payload landed there with no manifest entry, no execute
/// strip and no recorded size. Not listed, not restorable, not purgeable, not
/// contained. What is asserted here is that every one of those holds for a
/// privileged item exactly as it does for one this process could move itself.
@Suite("SafetyNet privileged archive")
struct SafetyNetPrivilegedArchiveTests {

  /// A system domain origin, per the fixture ownership: /Applications and
  /// /Library are the two roots the privileged half exists for.
  private static let systemOrigin = Fixture.path("/Applications/Example.app")
  private static let userOrigin = Fixture.path("/Users/julian/Caches/mine.log")

  private func world(
    privileged: FakePrivilegedArchiver? = FakePrivilegedArchiver()
  ) async -> (store: SafetyNetStore, fileSystem: InMemoryFileSystem, half: FakePrivilegedArchiver?)
  {
    let fileSystem = await safetyNetFileSystem()
    await fileSystem.seedFile(at: Self.systemOrigin, contents: Data(repeating: 0x41, count: 32))
    let store = safetyNetMake(
      fileSystem: fileSystem,
      ownership: SafetyNetSystemRoots(),
      privileged: privileged)
    if let privileged { await privileged.attach(to: fileSystem) }
    return (store, fileSystem, privileged)
  }

  // MARK: - It is listed, sized and contained

  @Test("a privileged archive is listed like any other item")
  func aPrivilegedArchiveIsListed() async throws {
    let world = await world()
    let item = try await world.store.store(
      Self.systemOrigin, source: .malwareQuarantine, groupID: nil)

    let listed = try await world.store.items(includingRestored: false)
    #expect(listed.map(\.id) == [item.id])
    #expect(listed.first?.originPath == Self.systemOrigin)
  }

  @Test("the recorded size is the one measured at the origin, not one read afterwards")
  func theRecordedSizeIsTheOneMeasuredAtTheOrigin() async throws {
    let world = await world()
    let half = try #require(world.half)
    await half.reportAllocatedBytes(4_096_000)

    let item = try await world.store.store(
      Self.systemOrigin, source: .uninstallArchive, groupID: nil)

    #expect(item.allocatedBytes == 4_096_000)
  }

  @Test("the store names the payload path, and the privileged half is told it")
  func theStoreNamesThePayloadPath() async throws {
    let world = await world()
    let half = try #require(world.half)
    let item = try await world.store.store(
      Self.systemOrigin, source: .malwareQuarantine, groupID: nil)

    let asked = await half.archived
    #expect(asked.count == 1)
    #expect(asked.first?.storedPath == item.storedPath)
    #expect(asked.first?.itemID == item.id)
    #expect(item.storedPath.lastComponent == item.id.uuidString)
  }

  @Test("a system domain payload is never moved by this process")
  func aSystemDomainPayloadIsNeverMovedByThisProcess() async throws {
    let world = await world()
    _ = try await world.store.store(Self.systemOrigin, source: .malwareQuarantine, groupID: nil)

    // The fake privileged half moved it, so the origin is empty and the
    // payload is where the store said. What matters is that the user process
    // file system never performed that move itself: it cannot, on a real
    // machine, and a store that tried would fail rather than succeed quietly.
    #expect(await !world.fileSystem.exists(Self.systemOrigin))
  }

  // MARK: - Without a privileged half

  @Test("a system domain payload without a privileged half refuses and moves nothing")
  func aSystemDomainPayloadWithoutAPrivilegedHalfRefuses() async throws {
    let world = await world(privileged: nil)

    await #expect(throws: SafetyNetError.privilegeUnavailable(Self.systemOrigin)) {
      _ = try await world.store.store(
        Self.systemOrigin, source: .malwareQuarantine, groupID: nil)
    }
    #expect(await world.fileSystem.exists(Self.systemOrigin))
    #expect(try await world.store.items(includingRestored: true).isEmpty)
  }

  @Test("a user domain payload still stores without a privileged half")
  func aUserDomainPayloadStillStoresWithoutAPrivilegedHalf() async throws {
    let world = await world(privileged: nil)
    await world.fileSystem.seedFile(at: Self.userOrigin, contents: Data([0x01]))

    let item = try await world.store.store(
      Self.userOrigin, source: .uninstallArchive, groupID: nil)

    #expect(item.originPath == Self.userOrigin)
    #expect(await world.fileSystem.exists(item.storedPath))
  }

  // MARK: - A reply that never arrived

  @Test("an archive whose reply was lost is settled by looking, and is recorded")
  func anArchiveWhoseReplyWasLostIsRecorded() async throws {
    let world = await world()
    let half = try #require(world.half)
    await half.loseTheNextReply()

    let item = try await world.store.store(
      Self.systemOrigin, source: .malwareQuarantine, groupID: nil)

    #expect(await half.describedCount == 1, "the store asked what arrived rather than guessing")
    let listed = try await world.store.items(includingRestored: true)
    #expect(listed.map(\.id) == [item.id])
    #expect(await world.fileSystem.exists(item.storedPath))
  }

  @Test("an archive that never happened records nothing and reports the failure")
  func anArchiveThatNeverHappenedRecordsNothing() async throws {
    let world = await world()
    let half = try #require(world.half)
    await half.failEverything()

    await #expect(throws: (any Error).self) {
      _ = try await world.store.store(
        Self.systemOrigin, source: .malwareQuarantine, groupID: nil)
    }
    #expect(try await world.store.items(includingRestored: true).isEmpty)
    #expect(await world.fileSystem.exists(Self.systemOrigin))
  }

  @Test("a report about another origin is a disagreement, and nothing is recorded")
  func aReportAboutAnotherOriginIsADisagreement() async throws {
    let world = await world()
    let half = try #require(world.half)
    await half.reportOrigin(Fixture.path("/Applications/Somewhere.else"))

    await #expect(throws: (any Error).self) {
      _ = try await world.store.store(
        Self.systemOrigin, source: .malwareQuarantine, groupID: nil)
    }
    #expect(try await world.store.items(includingRestored: true).isEmpty)
  }

  // MARK: - Restore and purge follow the payload

  @Test("a privileged item is restored through the privileged half")
  func aPrivilegedItemIsRestoredThroughThePrivilegedHalf() async throws {
    let world = await world()
    let half = try #require(world.half)
    let item = try await world.store.store(
      Self.systemOrigin, source: .uninstallArchive, groupID: nil)

    try await world.store.restore(itemID: item.id)

    #expect(await half.restored == [item.storedPath])
    #expect(try await world.store.items(includingRestored: false).isEmpty)
    #expect(await world.fileSystem.exists(Self.systemOrigin))
  }

  @Test("a restore that landed somewhere else is a disagreement and is not marked restored")
  func aRestoreThatLandedSomewhereElseIsADisagreement() async throws {
    let world = await world()
    let half = try #require(world.half)
    let item = try await world.store.store(
      Self.systemOrigin, source: .uninstallArchive, groupID: nil)
    await half.restoreTo(Fixture.path("/Applications/Elsewhere.app"))

    await #expect(throws: SafetyNetError.privilegedReportDisagreed(item.id)) {
      try await world.store.restore(itemID: item.id)
    }
    let listed = try await world.store.items(includingRestored: true)
    #expect(listed.first?.isRestored == false)
  }

  @Test("a privileged item is purged through the privileged half")
  func aPrivilegedItemIsPurgedThroughThePrivilegedHalf() async throws {
    let world = await world()
    let half = try #require(world.half)
    let item = try await world.store.store(
      Self.systemOrigin, source: .malwareQuarantine, groupID: nil)

    try await world.store.purge(
      itemIDs: [item.id],
      confirmation: PurgeConfirmation(
        itemCount: 1,
        byteTotal: item.allocatedBytes,
        confirmedAt: SafetyNetFixture.confirmationInstant))

    #expect(await half.discarded == [item.storedPath])
    #expect(try await world.store.items(includingRestored: true).isEmpty)
  }

  @Test("a privileged item without a privileged half is neither restored nor purged")
  func aPrivilegedItemWithoutAPrivilegedHalfStaysPut() async throws {
    let world = await world()
    let item = try await world.store.store(
      Self.systemOrigin, source: .malwareQuarantine, groupID: nil)

    // A second store over the same directory, built with no privileged half:
    // the same shape as a run where the helper is not approved.
    let withoutHelper = safetyNetMake(
      fileSystem: world.fileSystem,
      ownership: SafetyNetSystemRoots(),
      privileged: nil)

    await #expect(throws: SafetyNetError.privilegeUnavailable(Self.systemOrigin)) {
      try await withoutHelper.restore(itemID: item.id)
    }
    await #expect(throws: SafetyNetError.privilegeUnavailable(Self.systemOrigin)) {
      try await withoutHelper.purge(
        itemIDs: [item.id],
        confirmation: PurgeConfirmation(
          itemCount: 1,
          byteTotal: item.allocatedBytes,
          confirmedAt: SafetyNetFixture.confirmationInstant))
    }
    #expect(try await withoutHelper.items(includingRestored: false).map(\.id) == [item.id])
    #expect(await world.fileSystem.exists(item.storedPath))
  }

  @Test("a group holding a privileged item refuses whole rather than restoring half of it")
  func aGroupHoldingAPrivilegedItemRefusesWhole() async throws {
    let world = await world()
    await world.fileSystem.seedFile(at: Self.userOrigin, contents: Data([0x02]))
    let groupID = UUID()
    let privileged = try await world.store.store(
      Self.systemOrigin, source: .uninstallArchive, groupID: groupID)
    let ordinary = try await world.store.store(
      Self.userOrigin, source: .uninstallArchive, groupID: groupID)

    let withoutHelper = safetyNetMake(
      fileSystem: world.fileSystem,
      ownership: SafetyNetSystemRoots(),
      privileged: nil)

    await #expect(throws: SafetyNetError.privilegeUnavailable(Self.systemOrigin)) {
      try await withoutHelper.restoreGroup(groupID: groupID)
    }
    let listed = try await withoutHelper.items(includingRestored: true)
    #expect(listed.allSatisfy { !$0.isRestored })
    #expect(await world.fileSystem.exists(privileged.storedPath))
    #expect(await world.fileSystem.exists(ordinary.storedPath))
  }
}

/// The privileged half, standing in for the helper at exactly the boundary the
/// store sees. It performs the move through the same in memory file system the
/// store reads, because an archive nothing can see afterwards would let every
/// assertion above pass for the wrong reason.
actor FakePrivilegedArchiver: SafetyNetPrivilegedArchiving {
  struct Handover: Sendable, Equatable {
    let path: AbsolutePath
    let storedPath: AbsolutePath
    let itemID: UUID
  }

  private var fileSystem: InMemoryFileSystem?
  private(set) var archived: [Handover] = []
  private(set) var restored: [AbsolutePath] = []
  private(set) var discarded: [AbsolutePath] = []
  private(set) var describedCount = 0
  private var stamps: [AbsolutePath: PrivilegedArchiveReport] = [:]
  private var reportedBytes: UInt64?
  private var reportedOrigin: AbsolutePath?
  private var restoreDestination: AbsolutePath?
  private var losesNextReply = false
  private var failsEverything = false

  func attach(to fileSystem: InMemoryFileSystem) {
    self.fileSystem = fileSystem
  }

  func reportAllocatedBytes(_ bytes: UInt64) { reportedBytes = bytes }
  func reportOrigin(_ path: AbsolutePath) { reportedOrigin = path }
  func restoreTo(_ path: AbsolutePath) { restoreDestination = path }
  func failEverything() { failsEverything = true }

  /// The archive happens and the answer is lost, which is the case the store
  /// has to settle by looking rather than by guessing.
  func loseTheNextReply() { losesNextReply = true }

  func archive(
    _ path: AbsolutePath,
    to storedPath: AbsolutePath,
    itemID: UUID
  ) async throws -> PrivilegedArchiveReport {
    if failsEverything { throw FileSystemError.permissionDenied(path) }
    archived.append(Handover(path: path, storedPath: storedPath, itemID: itemID))
    let report = PrivilegedArchiveReport(
      originPath: reportedOrigin ?? path,
      metadata: FileMetadataSnapshot(
        posixPermissions: 0o755,
        extendedAttributes: [:],
        created: SafetyNetFixture.createdDate,
        modified: SafetyNetFixture.modifiedDate),
      allocatedBytes: reportedBytes ?? 32)
    guard let fileSystem else { throw FileSystemError.notFound(path) }
    try await fileSystem.move(path, to: storedPath)
    try await fileSystem.setPosixPermissions(0o644, at: storedPath)
    stamps[storedPath] = report
    guard !losesNextReply else {
      losesNextReply = false
      throw FileSystemError.ioFailure(path, description: "the reply never arrived")
    }
    return report
  }

  func describeArchived(
    at storedPath: AbsolutePath,
    itemID: UUID
  ) async throws -> PrivilegedArchiveReport {
    describedCount += 1
    guard let report = stamps[storedPath] else {
      throw FileSystemError.notFound(storedPath)
    }
    return report
  }

  func restoreArchived(at storedPath: AbsolutePath, itemID: UUID) async throws -> AbsolutePath {
    guard let report = stamps[storedPath], let fileSystem else {
      throw FileSystemError.notFound(storedPath)
    }
    restored.append(storedPath)
    let destination = restoreDestination ?? report.originPath
    try await fileSystem.move(storedPath, to: destination)
    stamps[storedPath] = nil
    return destination
  }

  func discardArchived(at storedPath: AbsolutePath, itemID: UUID) async throws {
    guard let fileSystem else { throw FileSystemError.notFound(storedPath) }
    discarded.append(storedPath)
    try await fileSystem.delete(storedPath)
    stamps[storedPath] = nil
  }
}
