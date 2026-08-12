import Foundation
import GleamCore

/// One read only pass over the disk, gathering exactly two things: the
/// allocated subtree total of every application bundle sitting in an install
/// location, and the allocated subtree total of every candidate leftover
/// sitting in a recognised location.
///
/// Nothing proportional to files seen is retained. A record adds its bytes to
/// at most one running total and is then dropped, so live memory is one number
/// per bundle and per candidate however many files the disk holds.
struct ApplicationSurvey {
  private(set) var bundleBytes: [AbsolutePath: UInt64] = [:]
  private(set) var candidateBytes: [LeftoverAssociation.Candidate: UInt64] = [:]
  private(set) var counters = ScanCounters.zero

  /// Walks the whole disk once. Without Full Disk Access the system domain is
  /// left out of the walk itself rather than filtered afterwards, so the scan
  /// never depends on reading a location it was refused.
  static func survey(
    _ context: ScanContext,
    yield: (ScanEvent) -> Void
  ) async throws -> ApplicationSurvey {
    var survey = ApplicationSurvey()
    let options = EnumerationOptions(
      includesHiddenFiles: true,
      descendsIntoPackages: true,
      skipSubtrees: skippedSubtrees(context))
    let root = AbsolutePath(normalising: "/")
    for try await event in context.fileSystem.enumerate(root: root, options: options) {
      try Task.checkCancellation()
      guard case .record(let record) = event else { continue }
      survey.take(record)
      guard !record.isDirectory else { continue }
      survey.counters.filesSeen += 1
      yield(.progress(survey.counters))
    }
    return survey
  }

  /// The sentences naming what this scan could not look at.
  static func degradedNotices(_ context: ScanContext) -> [String] {
    guard !context.hasFullDiskAccess else { return [] }
    return [
      "Launch daemons in \(LeftoverAssociation.systemDomainLocation) were skipped "
        + "because Full Disk Access is off."
    ]
  }

  private static func skippedSubtrees(_ context: ScanContext) -> [AbsolutePath] {
    guard !context.hasFullDiskAccess else { return [] }
    return [AbsolutePath(normalising: LeftoverAssociation.systemDomainLocation)]
  }

  /// Files one record's bytes against the bundle or the candidate leftover it
  /// belongs to. A record belongs to at most one of the two: install locations
  /// and leftover locations do not overlap.
  private mutating func take(_ record: FileRecord) {
    let components = record.path.components
    if let bundleRoot = ApplicationBundle.root(containing: components) {
      bundleBytes[bundleRoot, default: 0] += record.allocatedBytes
      return
    }
    guard let candidate = LeftoverAssociation.candidate(containing: components) else { return }
    candidateBytes[candidate, default: 0] += record.allocatedBytes
  }
}

// MARK: - The inventory the survey supports

extension ApplicationSurvey {
  /// Every installed application whose identity can be read, with the files
  /// attributed to it, ordered by bundle identifier and each application's
  /// leftovers ordered by path.
  func applications(
    fileSystem: any FileSystemReading,
    excluding runningApplicationBundleID: String
  ) async throws -> [AppInventoryEntry] {
    let installed = try await installedApplications(
      fileSystem: fileSystem, excluding: runningApplicationBundleID)
    let leftovers = attributedLeftovers(installedBundleIDs: Set(installed.keys))
    return
      installed
      .map { bundleID, application in
        AppInventoryEntry(
          bundleID: bundleID,
          name: application.identity.name,
          version: application.identity.version,
          installLocation: application.root,
          leftoverPaths: (leftovers[bundleID] ?? []).sorted { $0.path < $1.path })
      }
      .sorted { $0.bundleID < $1.bundleID }
  }

  private struct InstalledApplication {
    let root: AbsolutePath
    let identity: ApplicationBundle.Identity
  }

  /// The applications this inventory offers, by bundle identifier. A bundle
  /// whose identity cannot be read is not offered, and neither is the running
  /// application: the exclusion is decided on the identity a bundle claims,
  /// never on its name on disk, so a copy renamed to something else is still
  /// excluded and an application whose identifier merely begins with the
  /// running one's is still offered.
  private func installedApplications(
    fileSystem: any FileSystemReading,
    excluding runningApplicationBundleID: String
  ) async throws -> [String: InstalledApplication] {
    var installed: [String: InstalledApplication] = [:]
    for root in bundleBytes.keys.sorted() {
      try Task.checkCancellation()
      guard let identity = await ApplicationBundle.identity(atRoot: root, fileSystem: fileSystem),
        identity.bundleID != runningApplicationBundleID,
        installed[identity.bundleID] == nil
      else { continue }
      installed[identity.bundleID] = InstalledApplication(root: root, identity: identity)
    }
    return installed
  }

  /// The candidates the sweep may offer, with the bytes each occupies, in
  /// path order.
  ///
  /// `claimedBundleIDs` is every identifier anything on this Mac answers to,
  /// which is wider than the inventory the uninstall offers: the running
  /// application is excluded from that inventory and its own files are still
  /// nobody's to sweep.
  func orphanedCandidates(claimedBundleIDs: Set<String>) -> [(path: AbsolutePath, bytes: UInt64)] {
    candidateBytes
      .filter { LeftoverAssociation.isSweepable($0.key, claimedBundleIDs: claimedBundleIDs) }
      .map { (path: $0.key.root, bytes: $0.value) }
      .sorted { $0.path < $1.path }
  }

  /// Every identifier a bundle on this disk claims, whether or not the
  /// inventory offers it. Read from the bundles themselves rather than from
  /// the offered list, because the difference between the two is exactly the
  /// running application, whose files would otherwise look orphaned.
  func claimedBundleIDs(fileSystem: any FileSystemReading) async throws -> Set<String> {
    var claimed: Set<String> = []
    for root in bundleBytes.keys.sorted() {
      try Task.checkCancellation()
      guard let identity = await ApplicationBundle.identity(atRoot: root, fileSystem: fileSystem)
      else { continue }
      claimed.insert(identity.bundleID)
    }
    return claimed
  }

  /// Every candidate that an installed application owns outright, by bundle
  /// identifier. A candidate nobody owns is in no list at all, which is what
  /// keeps an unattributed file out of every uninstall.
  private func attributedLeftovers(installedBundleIDs: Set<String>) -> [String: [LeftoverPath]] {
    var attributed: [String: [LeftoverPath]] = [:]
    for (candidate, byteSize) in candidateBytes {
      guard
        let owner = LeftoverAssociation.owner(
          of: candidate, installedBundleIDs: installedBundleIDs)
      else { continue }
      attributed[owner, default: []].append(
        LeftoverPath(path: candidate.root, kind: candidate.kind, byteSize: byteSize))
    }
    return attributed
  }
}
