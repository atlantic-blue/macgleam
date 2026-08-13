import CryptoKit
import Foundation
import GleamCore

/// Storage declutter: large files, old files, downloads triage, duplicate
/// sets and similar photo sets.
///
/// Large files are files at or above the Settings threshold, strictly inside
/// the user home. Old files are files last opened at or beyond the Settings
/// day threshold relative to the injected reference date, falling back to the
/// modification date when the volume records no last opened date. Downloads
/// triage partitions the files directly inside the Downloads folder into age
/// bands so each file appears in exactly one triage finding. Duplicate sets
/// group byte identical files by full content hash, with size as a prefilter
/// so unique sizes never read content; the lexicographically smallest member
/// is the kept copy and no plan ever targets it. Similar photo sets group
/// near identical photos by a downsampled grayscale fingerprint with the
/// same kept copy mechanics, and never claim a photo that another photo
/// duplicates byte for byte. A denylisted path is never a finding and never
/// an operation.
public struct LeftoversEngine: GleamEngine {
  public var module: GleamModule { .leftovers }

  let userHome: AbsolutePath
  let referenceDate: Date

  public init(userHome: AbsolutePath, referenceDate: Date) {
    self.userHome = userHome
    self.referenceDate = referenceDate
  }

  public func scan(_ context: ScanContext) -> AsyncThrowingStream<ScanEvent, Error> {
    AsyncThrowingStream { continuation in
      // A walk runs below whatever asked for it. Reading a few hundred
      // thousand files at the interface's own priority makes the whole machine
      // feel slow while a scan is on, and nobody is waiting on any single file
      // of it.
      let scanTask = Task(priority: .utility) {
        do {
          try await runScan(context) { continuation.yield($0) }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in scanTask.cancel() }
    }
  }

  public func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan {
    guard !selection.isEmpty else { throw PlanningError.emptySelection }
    for finding in selection where finding.sessionID != context.sessionID {
      throw PlanningError.findingFromDifferentSession(finding.id)
    }
    var builder = PlanBuilder(context: context, userHome: userHome)
    for finding in selection {
      try builder.add(finding)
    }
    return builder.build(sessionID: context.sessionID)
  }
}

// MARK: - Scanning

extension LeftoversEngine {
  fileprivate func runScan(
    _ context: ScanContext,
    yield: @Sendable (ScanEvent) -> Void
  ) async throws {
    yield(.phase(.indeterminate))
    var counters = ScanCounters.zero
    let files = try await collectFileRecords(context, counters: &counters, yield: yield)
    yield(.phase(.determinate(estimatedTotalFiles: counters.filesSeen)))
    for finding in try await buildFindings(files: files, context: context) {
      try Task.checkCancellation()
      counters.itemCount += finding.itemCount
      counters.bytesReclaimable += finding.byteSize
      yield(.finding(finding))
      yield(.progress(counters))
    }
    yield(.phase(.settling))
  }

  private func collectFileRecords(
    _ context: ScanContext,
    counters: inout ScanCounters,
    yield: (ScanEvent) -> Void
  ) async throws -> [FileRecord] {
    let options = EnumerationOptions(
      includesHiddenFiles: true,
      descendsIntoPackages: true,
      skipSubtrees: [])
    var files: [FileRecord] = []
    for try await event in context.fileSystem.enumerate(root: userHome, options: options) {
      try Task.checkCancellation()
      guard case .record(let record) = event, !record.isDirectory else { continue }
      guard record.path.isDescendant(of: userHome) else { continue }
      files.append(record)
      counters.filesSeen += 1
      if ProgressCadence.reports(filesSeen: counters.filesSeen) {
        yield(.progress(counters))
      }
    }
    // The last report is the one somebody is left looking at, so it is made
    // whatever the cadence did.
    yield(.progress(counters))
    return files
  }

  private func buildFindings(
    files: [FileRecord],
    context: ScanContext
  ) async throws -> [Finding] {
    let permitted =
      files
      .filter { !context.rules.denylist.blocks($0.path) }
      .sorted { $0.path < $1.path }
    var findings: [Finding] = []
    findings.append(contentsOf: largeFileFindings(permitted, context: context))
    findings.append(contentsOf: oldFileFindings(permitted, context: context))
    findings.append(contentsOf: downloadsTriageFindings(permitted, context: context))
    let duplicates = try await duplicateSetFindings(permitted, context: context)
    findings.append(contentsOf: duplicates)
    findings.append(
      contentsOf: try await similarPhotoSetFindings(
        permitted, duplicates: duplicates, context: context))
    return findings
  }
}

// MARK: - Large files

extension LeftoversEngine {
  fileprivate func largeFileFindings(_ files: [FileRecord], context: ScanContext) -> [Finding] {
    files
      .filter { $0.allocatedBytes >= context.settings.largeFileThresholdBytes }
      .map { record in
        Finding(
          id: UUID(),
          sessionID: context.sessionID,
          category: .largeFile,
          entries: [PathEntry(path: record.path, allocatedBytes: record.allocatedBytes)],
          risk: .review,
          explanation:
            "This file takes \(record.allocatedBytes) bytes on disk, "
            + "at or above your large file threshold, so it is worth a review.",
          isPreselected: false)
      }
  }
}

// MARK: - Old files

extension LeftoversEngine {
  private static let secondsPerDay: TimeInterval = 86_400

  fileprivate func oldFileFindings(_ files: [FileRecord], context: ScanContext) -> [Finding] {
    files.compactMap { record in
      guard let age = oldFileAge(of: record, context: context) else { return nil }
      return Finding(
        id: UUID(),
        sessionID: context.sessionID,
        category: .oldFile,
        entries: [PathEntry(path: record.path, allocatedBytes: record.allocatedBytes)],
        risk: .review,
        explanation: oldFileExplanation(for: age),
        isPreselected: false)
    }
  }

  private struct OldFileAge {
    let days: UInt64
    let usesModificationFallback: Bool
  }

  /// The age that qualifies a file as old, or nil when it is not old enough.
  /// A file with no last opened date is judged by its modification date and
  /// the explanation says so.
  private func oldFileAge(of record: FileRecord, context: ScanContext) -> OldFileAge? {
    let usesFallback = record.lastOpened == nil
    guard let date = record.lastOpened ?? record.modified else { return nil }
    let elapsed = referenceDate.timeIntervalSince(date)
    let threshold = TimeInterval(context.settings.oldFileThresholdDays) * Self.secondsPerDay
    guard elapsed >= threshold else { return nil }
    return OldFileAge(
      days: UInt64(elapsed / Self.secondsPerDay),
      usesModificationFallback: usesFallback)
  }

  private func oldFileExplanation(for age: OldFileAge) -> String {
    guard age.usesModificationFallback else {
      return "This file was last opened \(age.days) days ago, "
        + "at or beyond your old file threshold, so it is worth a review."
    }
    return "This file has no last opened date on record, "
      + "so its modification date stands in: it was last modified \(age.days) days ago, "
      + "at or beyond your old file threshold, so it is worth a review."
  }
}

// MARK: - Downloads triage

extension LeftoversEngine {
  /// The age bands that partition the Downloads folder. Every file directly
  /// in Downloads lands in exactly one band.
  private enum DownloadsBand: CaseIterable {
    case lastThirtyDays
    case thirtyToOneHundredEightyDays
    case beyondOneHundredEightyDays

    var explanation: String {
      switch self {
      case .lastThirtyDays:
        return "These files arrived in Downloads within the last 30 days, "
          + "so they are likely still in use and worth a quick look."
      case .thirtyToOneHundredEightyDays:
        return "These files have sat in Downloads for between 30 and 180 days "
          + "without attention, so they are worth a review."
      case .beyondOneHundredEightyDays:
        return "These files have sat in Downloads for more than 180 days, "
          + "so they are probably forgotten and worth a review."
      }
    }
  }

  fileprivate func downloadsTriageFindings(
    _ files: [FileRecord],
    context: ScanContext
  ) -> [Finding] {
    let downloads = downloadsFolder
    let direct = files.filter { $0.path.isChild(of: downloads) }
    let byBand = Dictionary(grouping: direct) { band(for: $0) }
    return DownloadsBand.allCases.compactMap { band in
      guard let records = byBand[band], !records.isEmpty else { return nil }
      return Finding(
        id: UUID(),
        sessionID: context.sessionID,
        category: .downloadsTriage,
        entries: records.map { PathEntry(path: $0.path, allocatedBytes: $0.allocatedBytes) },
        risk: .review,
        explanation: band.explanation,
        isPreselected: false)
    }
  }

  private var downloadsFolder: AbsolutePath {
    let home = userHome.value == "/" ? "" : userHome.value
    return AbsolutePath(normalising: home + "/Downloads")
  }

  private func band(for record: FileRecord) -> DownloadsBand {
    let date = record.lastOpened ?? record.modified ?? record.created ?? .distantPast
    let elapsedDays = referenceDate.timeIntervalSince(date) / Self.secondsPerDay
    if elapsedDays < 30 { return .lastThirtyDays }
    if elapsedDays < 180 { return .thirtyToOneHundredEightyDays }
    return .beyondOneHundredEightyDays
  }

}

// MARK: - Duplicate sets

extension LeftoversEngine {
  /// The bounded read that partitions candidates before any full content
  /// read. Allocated bytes cannot serve as the prefilter because allocation
  /// is not the logical length (sparse and cloned files), so a wrong split
  /// there would drop real duplicates.
  private static let prefilterPrefixBytes: UInt64 = 65_536

  /// Groups byte identical files into duplicate set findings. A bounded
  /// prefix hash is the prefilter, so a file with a unique opening never has
  /// its full content read; grouping itself is by SHA256 over the full
  /// content, so equal size with different content never groups and a one
  /// byte difference never groups. Empty files never form a set.
  fileprivate func duplicateSetFindings(
    _ files: [FileRecord],
    context: ScanContext
  ) async throws -> [Finding] {
    let partitions = try await hashGroups(
      files, fileSystem: context.fileSystem, maxBytes: Self.prefilterPrefixBytes)
    var findings: [Finding] = []
    for partition in partitions where partition.count >= 2 {
      let groups = try await hashGroups(
        partition, fileSystem: context.fileSystem, maxBytes: .max)
      for group in groups where group.count >= 2 {
        findings.append(duplicateSetFinding(for: group, context: context))
      }
    }
    return findings.sorted { $0.paths[0] < $1.paths[0] }
  }

  /// Partitions the candidates by the SHA256 digest of up to maxBytes of
  /// content. A file with empty content never joins a partition, and a file
  /// whose content cannot be read is left out of every partition rather than
  /// sinking the scan, mirroring the enumeration contract's skip semantics
  /// for inaccessible entries.
  private func hashGroups(
    _ candidates: [FileRecord],
    fileSystem: any FileSystemReading,
    maxBytes: UInt64
  ) async throws -> [[FileRecord]] {
    var byDigest: [Data: [FileRecord]] = [:]
    for record in candidates {
      try Task.checkCancellation()
      let content: Data
      do {
        content = try await fileSystem.readData(at: record.path, maxBytes: maxBytes)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        continue
      }
      guard !content.isEmpty else { continue }
      byDigest[Data(SHA256.hash(data: content)), default: []].append(record)
    }
    return Array(byDigest.values)
  }

  /// The kept copy is the lexicographically smallest path, so the choice is
  /// deterministic across scans of the same tree.
  private func duplicateSetFinding(for group: [FileRecord], context: ScanContext) -> Finding {
    let members = group.sorted { $0.path < $1.path }
    let keptPath = members[0].path
    return Finding(
      id: UUID(),
      sessionID: context.sessionID,
      category: .duplicateSet(keptPath: keptPath),
      entries: members.map { PathEntry(path: $0.path, allocatedBytes: $0.allocatedBytes) },
      risk: .review,
      explanation:
        "These \(members.count) files are byte for byte identical. "
        + "The copy at \(keptPath.value) is kept, "
        + "and removing the others reclaims the duplicated space.",
      isPreselected: false)
  }
}

// MARK: - Planning

extension LeftoversEngine {
  fileprivate struct PlanBuilder {
    private let context: PlanContext
    private let environment: OwnershipEnvironment
    private var operations: [GleamCore.Operation] = []
    private var totalBytes: UInt64 = 0
    private var permanentFileCount: UInt32 = 0
    private var permanentByteTotal: UInt64 = 0

    init(context: PlanContext, userHome: AbsolutePath) {
      self.context = context
      self.environment = OwnershipEnvironment(currentUserHome: userHome, currentUserID: getuid())
    }

    mutating func add(_ finding: Finding) throws {
      switch finding.category {
      case .duplicateSet(let keptPath), .similarPhotoSet(let keptPath):
        try addKeptPathSet(finding, keeping: keptPath)
      default:
        addUniformFinding(finding)
      }
    }

    /// A finding whose paths all plan for removal. The plan's total is the
    /// exact sum of the allocated bytes of the entries its operations
    /// target: a denylist exclusion removes exactly that entry's bytes.
    private mutating func addUniformFinding(_ finding: Finding) {
      let included = permitted(finding.entries)
      guard !included.isEmpty else { return }
      append(included, of: finding)
    }

    /// The keep one invariant: the kept path must be a member of the set,
    /// however the selection was assembled, and no operation ever targets
    /// it. Members are deduplicated first so a tampered selection listing a
    /// path twice cannot inflate the plan. Each removed member contributes
    /// exactly its own allocated bytes; the kept copy's are never counted.
    private mutating func addKeptPathSet(
      _ finding: Finding,
      keeping keptPath: AbsolutePath
    ) throws {
      var members: [PathEntry] = []
      for entry in finding.entries where !members.contains(where: { $0.path == entry.path }) {
        members.append(entry)
      }
      guard members.contains(where: { $0.path == keptPath }) else {
        throw PlanningError.keptCopyMissing(findingID: finding.id)
      }
      let included = permitted(members.filter { $0.path != keptPath })
      guard !included.isEmpty else { return }
      append(included, of: finding)
    }

    private func permitted(_ entries: [PathEntry]) -> [PathEntry] {
      entries.filter { !context.rules.denylist.blocks($0.path) }
    }

    private mutating func append(_ included: [PathEntry], of finding: Finding) {
      let isPermanent = context.settings.deletionMode == .permanent
      let bytes = included.reduce(UInt64(0)) { $0 + $1.allocatedBytes }
      totalBytes += bytes
      if isPermanent {
        permanentFileCount += UInt32(included.count)
        permanentByteTotal += bytes
      }
      for entry in included {
        operations.append(
          operation(for: entry.path, findingID: finding.id, isPermanent: isPermanent))
      }
    }

    private func operation(
      for path: AbsolutePath,
      findingID: UUID,
      isPermanent: Bool
    ) -> GleamCore.Operation {
      let ownership = context.ownership.ownership(of: path, environment: environment)
      return GleamCore.Operation(
        id: UUID(),
        findingID: findingID,
        kind: isPermanent ? .deletePermanently(target: path) : .moveToTrash(target: path),
        privilege: ownership == .userDomain ? .user : .root)
    }

    func build(sessionID: UUID) -> OperationPlan {
      OperationPlan(
        id: UUID(),
        sessionID: sessionID,
        operations: operations,
        totalBytes: totalBytes,
        permanentDeletionConfirmation: confirmation())
    }

    private func confirmation() -> PermanentDeletionConfirmation? {
      guard permanentFileCount > 0 else { return nil }
      return PermanentDeletionConfirmation(
        fileCount: permanentFileCount,
        byteTotal: permanentByteTotal,
        confirmedAt: Date())
    }
  }
}
