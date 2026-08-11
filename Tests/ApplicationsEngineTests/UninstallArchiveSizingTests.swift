import Foundation
import GleamCore
import Testing

/// C18 and C8 at the level where the defect bit: a whole uninstall.
///
/// Every uninstall archives directories, and the store strips execute from
/// what it holds, so on a real volume it can never read inside its own
/// archive again (C13). The size each item records is therefore taken at the
/// origin before the move, and the purge that reclaims the space adds those
/// recorded figures up rather than going back to look.
///
/// The figure is checked against the one the review showed the person before
/// they agreed to the uninstall, which was measured by the scan from the
/// other direction entirely.
@Suite("Uninstall: the archive knows its own size")
struct UninstallArchiveSizingTests {

  /// Nothing here reads a clock.
  private static let confirmedAt = Date(timeIntervalSince1970: 1_726_100_000)

  private static let bundle = ApplicationsFixture.path("/Applications/ExampleMail.app")

  /// The allocated bytes the review screen showed for a path, straight off
  /// the finding entries the person agreed to.
  private func reviewedBytes(of path: AbsolutePath, in run: UninstallRun) -> UInt64? {
    run.selection.flatMap(\.entries).first { $0.path == path }?.allocatedBytes
  }

  @Test("records the bundle's whole size, the figure the review showed")
  func theBundleArchiveRecordsTheReviewedSize() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])
    let items = try await run.store.items(includingRestored: false)

    let item = try #require(storedItem(forOrigin: Self.bundle, in: items))
    let reviewed = try #require(reviewedBytes(of: Self.bundle, in: run))

    #expect(reviewed > 0, "a bundle of no bytes cannot prove a size was recorded")
    #expect(item.allocatedBytes == reviewed)
  }

  @Test("records a size for every archived path and never nothing")
  func everyArchivedItemRecordsItsReviewedSize() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])
    let items = try await run.store.items(includingRestored: false)

    #expect(items.isEmpty == false, "nothing was archived, so nothing below proves anything")
    for item in items {
      guard let reviewed = reviewedBytes(of: item.originPath, in: run) else {
        Issue.record("\(item.originPath.value) was archived but the review never named it")
        continue
      }
      #expect(item.allocatedBytes == reviewed, "\(item.originPath.value)")
      #expect(item.allocatedBytes > 0, "\(item.originPath.value)")
    }
  }

  @Test("purges the whole archive against the bytes the review showed")
  func purgingTheArchiveNamesTheReviewedTotal() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])
    let items = try await run.store.items(includingRestored: false)
    let reviewedTotal = items.reduce(UInt64(0)) { total, item in
      total + (reviewedBytes(of: item.originPath, in: run) ?? 0)
    }
    let confirmation = PurgeConfirmation(
      itemCount: UInt32(items.count),
      byteTotal: reviewedTotal,
      confirmedAt: Self.confirmedAt
    )

    try await run.store.purge(itemIDs: items.map(\.id), confirmation: confirmation)

    #expect(reviewedTotal > 0)
    let history = try await run.store.items(includingRestored: true)
    #expect(history.isEmpty)
  }

  @Test("refuses to purge the archive against nothing reclaimed")
  func purgingTheArchiveAgainstNothingIsRefused() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])
    let items = try await run.store.items(includingRestored: false)
    let nothingReclaimed = PurgeConfirmation(
      itemCount: UInt32(items.count),
      byteTotal: 0,
      confirmedAt: Self.confirmedAt
    )

    // This is the shape the defect took: an archive whose payload the store
    // could no longer read, sized at nothing, deleted while the person was
    // told nothing came back.
    await #expect(throws: SafetyNetError.confirmationMismatch) {
      try await run.store.purge(itemIDs: items.map(\.id), confirmation: nothingReclaimed)
    }
    let history = try await run.store.items(includingRestored: true)
    #expect(safetyNetIdentifiers(history) == safetyNetIdentifiers(items))
  }

  @Test("holds the archived bundle contained, so nothing inside it can be reached")
  func theArchivedBundleStaysContained() async throws {
    let run = try await runUninstall(of: [ApplicationWorld.mail])
    let items = try await run.store.items(includingRestored: false)
    let item = try #require(storedItem(forOrigin: Self.bundle, in: items))

    let mode = try await run.fileSystem.posixPermissions(at: item.storedPath)
    #expect(mode & 0o111 == 0)

    var options = EnumerationOptions.default
    options.includesHiddenFiles = true
    options.descendsIntoPackages = true
    var records: [AbsolutePath] = []
    var inaccessible: [AbsolutePath] = []
    for try await event in run.fileSystem.enumerate(root: item.storedPath, options: options) {
      switch event {
      case .record(let record): records.append(record.path)
      case .inaccessible(let path, _): inaccessible.append(path)
      }
    }
    // Both at once, which is the whole point: contained and exactly sized.
    #expect(records.isEmpty)
    #expect(inaccessible.contains(item.storedPath))
    #expect(item.allocatedBytes > 0)
  }
}

/// Local to this target: the identifier helpers in the C18 suites live in
/// GleamCoreTests.
private func safetyNetIdentifiers(_ items: [SafetyNetItem]) -> Set<UUID> {
  Set(items.map(\.id))
}
