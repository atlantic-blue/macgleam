import Foundation
import GleamCore
import Testing

/// C18 and C8, the size of what the store holds.
///
/// The store strips execute from every payload so a quarantined bundle cannot
/// run, and a directory without execute cannot be traversed (C13). So the
/// store cannot read inside its own directory payloads, and every uninstall
/// archives directories. The size is therefore measured once at the origin,
/// before the move and before the strip, recorded on the item, and never
/// recomputed.
///
/// The two properties pull against each other and both have to hold at once:
/// the payload stays contained, and the figure stays exact.
@Suite("SafetyNet store: sizing what it stored")
struct SafetyNetStoreSizingTests {

  private static let fileOrigin = Fixture.path("/Users/julian/Downloads/agent")
  private static let directoryOrigin = Fixture.path(
    "/Users/julian/Library/Application Support/Example Studio")
  private static let bundleOrigin = Fixture.path("/Applications/Example.app")

  // MARK: - Recorded at store time

  @Test("records the allocated size of a file payload")
  func recordsTheSizeOfAFilePayload() async throws {
    let fileSystem = await safetyNetFileSystem()
    try await safetyNetSeedFile(
      in: fileSystem, at: Self.fileOrigin, seed: 60, isExecutable: true)
    let expected = try await fileSystem.metadata(at: Self.fileOrigin).allocatedBytes
    #expect(expected > 0, "a payload of no bytes cannot prove a size was recorded")
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(Self.fileOrigin, source: .malwareQuarantine, groupID: nil)

    #expect(item.allocatedBytes == expected)
  }

  @Test("records the whole subtree total of a directory payload")
  func recordsTheSubtreeTotalOfADirectoryPayload() async throws {
    let fileSystem = await safetyNetFileSystem()
    let payload = try await safetyNetSeedDirectory(
      in: fileSystem, at: Self.directoryOrigin, seed: 61)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(
      Self.directoryOrigin, source: .uninstallArchive, groupID: Fixture.groupID)

    #expect(item.allocatedBytes == payload.subtreeBytes)
  }

  @Test("counts what sits inside a directory payload, never the directory's own record alone")
  func aDirectoryPayloadIsNeverSizedAsAnEmptyOne() async throws {
    let fileSystem = await safetyNetFileSystem()
    let payload = try await safetyNetSeedDirectory(
      in: fileSystem, at: Self.directoryOrigin, seed: 62)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(
      Self.directoryOrigin, source: .uninstallArchive, groupID: Fixture.groupID)

    // The defect this slice exists for produced the directory's own figure,
    // which for a directory is nothing at all.
    #expect(item.allocatedBytes > payload.ownBytes)
    #expect(item.allocatedBytes > 0)
  }

  @Test("counts the whole of an application bundle, package boundary or not")
  func anApplicationBundleIsCountedWhole() async throws {
    let fileSystem = await safetyNetFileSystem()
    let payload = try await safetyNetSeedDirectory(in: fileSystem, at: Self.bundleOrigin, seed: 63)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(
      Self.bundleOrigin, source: .uninstallArchive, groupID: Fixture.groupID)

    // An uninstall archives the bundle, so a walk that stopped at the package
    // boundary would record a figure for an application containing nothing.
    #expect(item.allocatedBytes == payload.subtreeBytes)
  }

  @Test("measures at the origin, so the recorded size is one nothing could read afterwards")
  func theRecordedSizeCouldNotHaveBeenReadFromTheStore() async throws {
    let fileSystem = await safetyNetFileSystem()
    let payload = try await safetyNetSeedDirectory(
      in: fileSystem, at: Self.directoryOrigin, seed: 64)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(
      Self.directoryOrigin, source: .uninstallArchive, groupID: Fixture.groupID)

    // Anything re-deriving the size from the stored payload gets this, which
    // is the whole reason the figure is recorded once and never recomputed.
    let rereadable = try await safetyNetNaiveSubtreeBytes(of: item.storedPath, in: fileSystem)
    #expect(rereadable < item.allocatedBytes)
    #expect(item.allocatedBytes == payload.subtreeBytes)
  }

  @Test("keeps the recorded size in the listing")
  func theListedItemCarriesTheRecordedSize() async throws {
    let fileSystem = await safetyNetFileSystem()
    try await safetyNetSeedDirectory(in: fileSystem, at: Self.directoryOrigin, seed: 65)
    let store = safetyNetMake(fileSystem: fileSystem)
    let item = try await store.store(
      Self.directoryOrigin, source: .uninstallArchive, groupID: Fixture.groupID)

    let listed = try await store.items(includingRestored: false)

    #expect(safetyNetItem(item.id, in: listed)?.allocatedBytes == item.allocatedBytes)
  }

  @Test("keeps the recorded size in the manifest, so a second store reads the same figure")
  func theRecordedSizeSurvivesInTheManifest() async throws {
    let fileSystem = await safetyNetFileSystem()
    try await safetyNetSeedDirectory(in: fileSystem, at: Self.directoryOrigin, seed: 66)
    let first = safetyNetMake(fileSystem: fileSystem)
    let item = try await first.store(
      Self.directoryOrigin, source: .uninstallArchive, groupID: Fixture.groupID)

    let second = safetyNetMake(fileSystem: fileSystem)
    let listed = try await second.items(includingRestored: false)

    #expect(safetyNetItem(item.id, in: listed)?.allocatedBytes == item.allocatedBytes)
  }

  // MARK: - Exact or refuse

  /// Seeds a directory payload one of whose inner directories cannot be
  /// entered, so measuring the payload whole is impossible.
  private func seedUnmeasurablePayload(
    in fileSystem: InMemoryFileSystem,
    seed: UInt8
  ) async throws -> SafetyNetDirectoryPayload {
    let payload = try await safetyNetSeedDirectory(
      in: fileSystem, at: Self.directoryOrigin, seed: seed)
    try await fileSystem.setPosixPermissions(
      SafetyNetFixture.strippedDirectoryMode, at: payload.innerDirectory)
    await #expect(throws: SafetyNetMeasurementRefused(path: payload.innerDirectory)) {
      _ = try await safetyNetSubtreeBytes(of: payload.root, in: fileSystem)
    }
    return payload
  }

  @Test("refuses a payload it cannot measure whole")
  func anUnmeasurablePayloadIsRefused() async throws {
    let fileSystem = await safetyNetFileSystem()
    _ = try await seedUnmeasurablePayload(in: fileSystem, seed: 67)
    let store = safetyNetMake(fileSystem: fileSystem)

    // The contract names no error case for this, so what is pinned is that it
    // throws rather than recording a short figure, and what it left behind.
    await #expect(throws: (any Error).self) {
      _ = try await store.store(
        Self.directoryOrigin, source: .uninstallArchive, groupID: Fixture.groupID)
    }
  }

  @Test("leaves a payload it cannot measure exactly where it was")
  func anUnmeasurablePayloadStaysAtItsOrigin() async throws {
    let fileSystem = await safetyNetFileSystem()
    let payload = try await seedUnmeasurablePayload(in: fileSystem, seed: 68)
    let before = try await safetyNetState(of: payload.shallowFile, in: fileSystem)
    let store = safetyNetMake(fileSystem: fileSystem)

    _ = try? await store.store(
      Self.directoryOrigin, source: .uninstallArchive, groupID: Fixture.groupID)

    #expect(await fileSystem.exists(payload.root))
    let after = try await safetyNetState(of: payload.shallowFile, in: fileSystem)
    expectSameFile(after, before)
    // The unreadable part is left as it was too: the store does not repair
    // permissions on its way past.
    let innerMode = try await fileSystem.posixPermissions(at: payload.innerDirectory)
    #expect(innerMode == SafetyNetFixture.strippedDirectoryMode)
  }

  @Test("holds nothing after refusing a payload it could not measure")
  func nothingIsHeldAfterARefusedMeasurement() async throws {
    let fileSystem = await safetyNetFileSystem()
    _ = try await seedUnmeasurablePayload(in: fileSystem, seed: 69)
    let store = safetyNetMake(fileSystem: fileSystem)

    _ = try? await store.store(
      Self.directoryOrigin, source: .uninstallArchive, groupID: Fixture.groupID)

    let history = try await store.items(includingRestored: true)
    #expect(history.isEmpty)
  }

  // MARK: - Purge sums what was recorded

  @Test("purges a directory archive against the sum of the recorded sizes")
  func aDirectoryArchivePurgesAgainstTheRecordedSizes() async throws {
    let fileSystem = await safetyNetFileSystem()
    try await safetyNetSeedDirectory(in: fileSystem, at: Self.directoryOrigin, seed: 70)
    let store = safetyNetMake(fileSystem: fileSystem)
    let item = try await store.store(
      Self.directoryOrigin, source: .uninstallArchive, groupID: Fixture.groupID)

    try await store.purge(itemIDs: [item.id], confirmation: safetyNetConfirmation(for: [item]))

    #expect(!(await fileSystem.exists(item.storedPath)))
    let history = try await store.items(includingRestored: true)
    #expect(history.isEmpty)
  }

  @Test("names the true byte total of a directory archive rather than nothing")
  func theByteTotalOfADirectoryArchiveIsTheTrueTotal() async throws {
    let fileSystem = await safetyNetFileSystem()
    let payload = try await safetyNetSeedDirectory(
      in: fileSystem, at: Self.directoryOrigin, seed: 71)
    let store = safetyNetMake(fileSystem: fileSystem)
    let item = try await store.store(
      Self.directoryOrigin, source: .uninstallArchive, groupID: Fixture.groupID)

    let confirmation = safetyNetConfirmation(for: [item])

    #expect(confirmation.byteTotal == payload.subtreeBytes)
    #expect(confirmation.byteTotal > 0)
    try await store.purge(itemIDs: [item.id], confirmation: confirmation)
  }

  @Test("refuses a purge of a directory archive confirmed against nothing reclaimed")
  func aZeroConfirmationForADirectoryArchiveIsRefused() async throws {
    let fileSystem = await safetyNetFileSystem()
    try await safetyNetSeedDirectory(in: fileSystem, at: Self.directoryOrigin, seed: 72)
    let store = safetyNetMake(fileSystem: fileSystem)
    let item = try await store.store(
      Self.directoryOrigin, source: .uninstallArchive, groupID: Fixture.groupID)
    let nothingReclaimed = PurgeConfirmation(
      itemCount: 1,
      byteTotal: 0,
      confirmedAt: SafetyNetFixture.confirmationInstant
    )

    await #expect(throws: SafetyNetError.confirmationMismatch) {
      try await store.purge(itemIDs: [item.id], confirmation: nothingReclaimed)
    }
    #expect(await fileSystem.exists(item.storedPath))
  }

  @Test("sums the recorded sizes across a batch of directory archives")
  func aBatchPurgeSumsTheRecordedSizes() async throws {
    let fileSystem = await safetyNetFileSystem()
    let first = try await safetyNetSeedDirectory(
      in: fileSystem, at: Self.directoryOrigin, seed: 73)
    let second = try await safetyNetSeedDirectory(in: fileSystem, at: Self.bundleOrigin, seed: 74)
    let store = safetyNetMake(fileSystem: fileSystem)
    let firstItem = try await store.store(
      Self.directoryOrigin, source: .uninstallArchive, groupID: Fixture.groupID)
    let secondItem = try await store.store(
      Self.bundleOrigin, source: .uninstallArchive, groupID: Fixture.groupID)

    let confirmation = safetyNetConfirmation(for: [firstItem, secondItem])

    #expect(confirmation.byteTotal == first.subtreeBytes + second.subtreeBytes)
    try await store.purge(
      itemIDs: [firstItem.id, secondItem.id], confirmation: confirmation)
    let history = try await store.items(includingRestored: true)
    #expect(history.isEmpty)
  }

  @Test("reads no payload while purging")
  func purgeReadsNoPayload() async throws {
    let fileSystem = await safetyNetFileSystem()
    try await safetyNetSeedDirectory(in: fileSystem, at: Self.directoryOrigin, seed: 75)
    let log = FileSystemReadLog()
    let store = safetyNetMake(
      fileSystem: ReadRecordingFileSystem(backing: fileSystem, log: log))
    let item = try await store.store(
      Self.directoryOrigin, source: .uninstallArchive, groupID: Fixture.groupID)
    let confirmation = safetyNetConfirmation(for: [item])
    // Storing reads the payload, and must. The clause is about purging.
    log.reset()

    try await store.purge(itemIDs: [item.id], confirmation: confirmation)

    #expect(log.callsReading(item.storedPath).isEmpty)
  }

  // MARK: - The containment survives

  @Test("strips every execute bit from a stored directory payload")
  func aStoredDirectoryPayloadLosesItsExecuteBits() async throws {
    let fileSystem = await safetyNetFileSystem()
    try await safetyNetSeedDirectory(in: fileSystem, at: Self.directoryOrigin, seed: 76)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(
      Self.directoryOrigin, source: .uninstallArchive, groupID: Fixture.groupID)

    let mode = try await fileSystem.posixPermissions(at: item.storedPath)
    #expect(mode & 0o111 == 0)
  }

  @Test("holds a directory payload that cannot be traversed while its size stays exact")
  func theStoredDirectoryIsContainedAndItsSizeIsExact() async throws {
    let fileSystem = await safetyNetFileSystem()
    let payload = try await safetyNetSeedDirectory(
      in: fileSystem, at: Self.directoryOrigin, seed: 77)
    let store = safetyNetMake(fileSystem: fileSystem)

    let item = try await store.store(
      Self.directoryOrigin, source: .uninstallArchive, groupID: Fixture.groupID)

    // Contained: nothing inside the stored payload can be reached, so the
    // binary in a quarantined bundle cannot be run out of the store.
    let outcome = try await collectEnumeration(
      fileSystem.enumerate(root: item.storedPath, options: safetyNetWholeSubtreeOptions())
    )
    #expect(outcome.records.isEmpty)
    #expect(outcome.inaccessible.contains { $0.path == item.storedPath })
    // Exact: and the figure survived it, because it was taken beforehand.
    #expect(item.allocatedBytes == payload.subtreeBytes)
    #expect(item.allocatedBytes > 0)
  }
}
