import Foundation
import GleamCore

/// Storage declutter: large files, old files and downloads triage.
///
/// Large files are files at or above the Settings threshold, strictly inside
/// the user home. Old files are files last opened at or beyond the Settings
/// day threshold relative to the injected reference date, falling back to the
/// modification date when the volume records no last opened date. Downloads
/// triage partitions the files directly inside the Downloads folder into age
/// bands so each file appears in exactly one triage finding. A denylisted
/// path is never a finding and never an operation.
public struct ClutterEngine: GleamEngine {
  public var module: GleamModule { .clutter }

  let userHome: AbsolutePath
  let referenceDate: Date

  public init(userHome: AbsolutePath, referenceDate: Date) {
    self.userHome = userHome
    self.referenceDate = referenceDate
  }

  public func scan(_ context: ScanContext) -> AsyncThrowingStream<ScanEvent, Error> {
    AsyncThrowingStream { continuation in
      let scanTask = Task {
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
      builder.add(finding)
    }
    return builder.build(sessionID: context.sessionID)
  }
}

// MARK: - Scanning

extension ClutterEngine {
  fileprivate func runScan(
    _ context: ScanContext,
    yield: @Sendable (ScanEvent) -> Void
  ) async throws {
    yield(.phase(.indeterminate))
    var counters = ScanCounters.zero
    let files = try await collectFileRecords(context, counters: &counters, yield: yield)
    yield(.phase(.determinate(estimatedTotalFiles: counters.filesSeen)))
    for finding in buildFindings(files: files, context: context) {
      try Task.checkCancellation()
      counters.findingCount += 1
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
      yield(.progress(counters))
    }
    return files
  }

  private func buildFindings(files: [FileRecord], context: ScanContext) -> [Finding] {
    let permitted =
      files
      .filter { !context.rules.denylist.blocks($0.path) }
      .sorted { $0.path < $1.path }
    var findings: [Finding] = []
    findings.append(contentsOf: largeFileFindings(permitted, context: context))
    findings.append(contentsOf: oldFileFindings(permitted, context: context))
    findings.append(contentsOf: downloadsTriageFindings(permitted, context: context))
    return findings
  }
}

// MARK: - Large files

extension ClutterEngine {
  fileprivate func largeFileFindings(_ files: [FileRecord], context: ScanContext) -> [Finding] {
    files
      .filter { $0.allocatedBytes >= context.settings.largeFileThresholdBytes }
      .map { record in
        Finding(
          id: UUID(),
          sessionID: context.sessionID,
          category: .largeFile,
          paths: [record.path],
          byteSize: record.allocatedBytes,
          risk: .review,
          explanation:
            "This file takes \(record.allocatedBytes) bytes on disk, "
            + "at or above your large file threshold, so it is worth a review.",
          isPreselected: false)
      }
  }
}

// MARK: - Old files

extension ClutterEngine {
  private static let secondsPerDay: TimeInterval = 86_400

  fileprivate func oldFileFindings(_ files: [FileRecord], context: ScanContext) -> [Finding] {
    files.compactMap { record in
      guard let age = oldFileAge(of: record, context: context) else { return nil }
      return Finding(
        id: UUID(),
        sessionID: context.sessionID,
        category: .oldFile,
        paths: [record.path],
        byteSize: record.allocatedBytes,
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

extension ClutterEngine {
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
    let direct = files.filter { parent(of: $0.path) == downloads }
    let byBand = Dictionary(grouping: direct) { band(for: $0) }
    return DownloadsBand.allCases.compactMap { band in
      guard let records = byBand[band], !records.isEmpty else { return nil }
      return Finding(
        id: UUID(),
        sessionID: context.sessionID,
        category: .downloadsTriage,
        paths: records.map(\.path),
        byteSize: records.reduce(0) { $0 + $1.allocatedBytes },
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

  private func parent(of path: AbsolutePath) -> AbsolutePath {
    var components = path.value.split(separator: "/").map(String.init)
    guard !components.isEmpty else { return path }
    components.removeLast()
    return AbsolutePath(normalising: "/" + components.joined(separator: "/"))
  }
}

// MARK: - Planning

extension ClutterEngine {
  /// The bytes a finding contributes to the plan. When the denylist excludes
  /// some of its paths the finding's bytes are apportioned by path count.
  fileprivate static func attributedBytes(of finding: Finding, includedCount: Int) -> UInt64 {
    guard includedCount < finding.paths.count else { return finding.byteSize }
    return finding.byteSize * UInt64(includedCount) / UInt64(finding.paths.count)
  }

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

    mutating func add(_ finding: Finding) {
      let included = finding.paths.filter { !context.rules.denylist.blocks($0) }
      guard !included.isEmpty else { return }
      let isPermanent = context.settings.deletionMode == .permanent
      let bytes = attributedBytes(of: finding, includedCount: included.count)
      totalBytes += bytes
      if isPermanent {
        permanentFileCount += UInt32(included.count)
        permanentByteTotal += bytes
      }
      for path in included {
        operations.append(operation(for: path, findingID: finding.id, isPermanent: isPermanent))
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
