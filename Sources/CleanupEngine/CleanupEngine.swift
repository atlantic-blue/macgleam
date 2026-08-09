import Foundation
import GleamCore

/// System junk scanning: caches, logs, broken downloads, Xcode derived data
/// and simulator caches, browser caches, temporary files, local mail
/// attachment copies, and every trash bin including external volume trashes.
///
/// Discovery is rule driven from the catalogue's cleanup rules. Findings are
/// itemised as files, sized by allocated bytes, and grouped by category, with
/// trash bins reported per volume. A denylisted path is never a finding and
/// never an operation. Without Full Disk Access the protected categories are
/// skipped and reported by name; user domain categories still scan.
public struct CleanupEngine: GleamEngine {
  public var module: GleamModule { .cleanup }

  public init() {}

  public func scan(_ context: ScanContext) -> AsyncThrowingStream<ScanEvent, Error> {
    AsyncThrowingStream { continuation in
      let scanTask = Task {
        do {
          try await Self.runScan(context) { continuation.yield($0) }
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
    var builder = PlanBuilder(context: context)
    for finding in selection {
      builder.add(finding)
    }
    return builder.build(sessionID: context.sessionID)
  }
}

// MARK: - Scanning

extension CleanupEngine {
  fileprivate static func runScan(
    _ context: ScanContext,
    yield: @Sendable (ScanEvent) -> Void
  ) async throws {
    yield(.phase(.indeterminate))
    let partition = partitionRules(context)
    for sentence in partition.unavailable {
      yield(.degraded(unavailable: sentence))
    }
    var counters = ScanCounters.zero
    let files = try await collectFileRecords(context, counters: &counters, yield: yield)
    yield(.phase(.determinate(estimatedTotalFiles: counters.filesSeen)))
    for finding in buildFindings(rules: partition.active, files: files, context: context) {
      try Task.checkCancellation()
      counters.findingCount += 1
      counters.bytesReclaimable += finding.byteSize
      yield(.finding(finding))
      yield(.progress(counters))
    }
    yield(.phase(.settling))
  }

  private struct RulePartition {
    let active: [CleanupRule]
    let unavailable: [String]
  }

  /// Splits the catalogue's cleanup rules into the ones this scan may run
  /// and plain sentences naming the protected categories it must skip.
  private static func partitionRules(_ context: ScanContext) -> RulePartition {
    let cleanupRules = context.rules.cleanupRules.filter { isCleanupCategory($0.category) }
    guard !context.hasFullDiskAccess else {
      return RulePartition(active: cleanupRules, unavailable: [])
    }
    var unavailable: [String] = []
    if cleanupRules.contains(where: { isMailAttachmentCategory($0.category) }) {
      unavailable.append(
        "Mail attachment local copies were skipped because Full Disk Access is off.")
    }
    if cleanupRules.contains(where: { isTrashBinCategory($0.category) }) {
      unavailable.append("Trash bins were skipped because Full Disk Access is off.")
    }
    let active = cleanupRules.filter { !isProtectedCategory($0.category) }
    return RulePartition(active: active, unavailable: unavailable)
  }

  private static func collectFileRecords(
    _ context: ScanContext,
    counters: inout ScanCounters,
    yield: (ScanEvent) -> Void
  ) async throws -> [FileRecord] {
    let options = EnumerationOptions(
      includesHiddenFiles: true,
      descendsIntoPackages: true,
      skipSubtrees: [])
    var files: [FileRecord] = []
    let root = AbsolutePath(normalising: "/")
    for try await event in context.fileSystem.enumerate(root: root, options: options) {
      try Task.checkCancellation()
      guard case .record(let record) = event, !record.isDirectory else { continue }
      files.append(record)
      counters.filesSeen += 1
      yield(.progress(counters))
    }
    return files
  }

  private static func buildFindings(
    rules: [CleanupRule],
    files: [FileRecord],
    context: ScanContext
  ) -> [Finding] {
    var findings: [Finding] = []
    for rule in rules {
      let matched =
        files
        .filter { !context.rules.denylist.blocks($0.path) && matches(rule: rule, path: $0.path) }
        .sorted { $0.path < $1.path }
      guard !matched.isEmpty else { continue }
      if isTrashBinCategory(rule.category) {
        findings.append(
          contentsOf: trashBinFindings(rule: rule, records: matched, sessionID: context.sessionID))
      } else {
        findings.append(
          makeFinding(
            FindingSeed(
              sessionID: context.sessionID, rule: rule, category: rule.category, records: matched)))
      }
    }
    return findings
  }

  /// One finding per volume, so the review shows where each bin lives.
  private static func trashBinFindings(
    rule: CleanupRule,
    records: [FileRecord],
    sessionID: UUID
  ) -> [Finding] {
    let byVolume = Dictionary(grouping: records) { volume(containing: $0.path) }
    return byVolume.keys.sorted().map { volume in
      makeFinding(
        FindingSeed(
          sessionID: sessionID,
          rule: rule,
          category: .trashBin(volume: volume),
          records: byVolume[volume] ?? []))
    }
  }

  private struct FindingSeed {
    let sessionID: UUID
    let rule: CleanupRule
    let category: FindingCategory
    let records: [FileRecord]
  }

  private static func makeFinding(_ seed: FindingSeed) -> Finding {
    Finding(
      id: UUID(),
      sessionID: seed.sessionID,
      category: seed.category,
      paths: seed.records.map(\.path),
      byteSize: seed.records.reduce(0) { $0 + $1.allocatedBytes },
      risk: seed.rule.risk,
      explanation: explanation(for: seed.rule),
      isPreselected: seed.rule.preselectable && seed.rule.risk == .safe)
  }

  /// A mail attachment finding must say that server state is never touched,
  /// whatever the catalogue's explanation says.
  private static func explanation(for rule: CleanupRule) -> String {
    guard isMailAttachmentCategory(rule.category) else { return rule.explanation }
    guard !rule.explanation.localizedCaseInsensitiveContains("server") else {
      return rule.explanation
    }
    let guarantee =
      "Only the local copy is removed; the message and its attachment on the server "
      + "are never touched."
    guard !rule.explanation.isEmpty else { return guarantee }
    return rule.explanation + " " + guarantee
  }

  /// A file matches a rule when the file's path, or any ancestor directory of
  /// it, matches one of the rule's patterns. A rule naming a directory
  /// therefore itemises the files beneath it, never the directory.
  private static func matches(rule: CleanupRule, path: AbsolutePath) -> Bool {
    ancestorsIncludingSelf(of: path).contains { candidate in
      rule.pathPatterns.contains { $0.matches(candidate) }
    }
  }

  private static func ancestorsIncludingSelf(of path: AbsolutePath) -> [AbsolutePath] {
    var components = path.value.split(separator: "/").map(String.init)
    var result = [path]
    while !components.isEmpty {
      components.removeLast()
      result.append(AbsolutePath(normalising: "/" + components.joined(separator: "/")))
    }
    return result
  }

  /// The volume a trash bin lives on: /Volumes/Name for an external bin,
  /// the root volume for everything else.
  private static func volume(containing path: AbsolutePath) -> AbsolutePath {
    let components = path.value.split(separator: "/").map(String.init)
    guard components.count >= 2, components[0] == "Volumes" else {
      return AbsolutePath(normalising: "/")
    }
    return AbsolutePath(normalising: "/Volumes/\(components[1])")
  }

  private static func isCleanupCategory(_ category: FindingCategory) -> Bool {
    switch category {
    case .userCache, .applicationCache, .log, .brokenDownload, .xcodeDerivedData,
      .simulatorCache, .browserCache, .temporaryFile, .mailAttachmentLocalCopy, .trashBin:
      return true
    default:
      return false
    }
  }

  /// The categories that need Full Disk Access.
  private static func isProtectedCategory(_ category: FindingCategory) -> Bool {
    isMailAttachmentCategory(category) || isTrashBinCategory(category)
  }

  private static func isMailAttachmentCategory(_ category: FindingCategory) -> Bool {
    category == .mailAttachmentLocalCopy
  }

  private static func isTrashBinCategory(_ category: FindingCategory) -> Bool {
    if case .trashBin = category { return true }
    return false
  }
}

// MARK: - Planning

extension CleanupEngine {
  /// Trash bin contents always plan as permanent deletion (moving trash to
  /// trash is meaningless); everything else follows the deletion mode.
  fileprivate static func plansPermanently(
    _ category: FindingCategory,
    mode: Settings.DeletionMode
  ) -> Bool {
    if case .trashBin = category { return true }
    return mode == .permanent
  }

  /// The bytes a finding contributes to the plan. When the denylist excludes
  /// some of its paths the finding's bytes are apportioned by path count.
  fileprivate static func attributedBytes(of finding: Finding, includedCount: Int) -> UInt64 {
    guard includedCount < finding.paths.count else { return finding.byteSize }
    return finding.byteSize * UInt64(includedCount) / UInt64(finding.paths.count)
  }

  fileprivate struct PlanBuilder {
    private let context: PlanContext
    private let environment = OwnershipEnvironment.current
    private var operations: [GleamCore.Operation] = []
    private var totalBytes: UInt64 = 0
    private var permanentFileCount: UInt32 = 0
    private var permanentByteTotal: UInt64 = 0

    init(context: PlanContext) {
      self.context = context
    }

    mutating func add(_ finding: Finding) {
      let included = finding.paths.filter { !context.rules.denylist.blocks($0) }
      guard !included.isEmpty else { return }
      let isPermanent = plansPermanently(finding.category, mode: context.settings.deletionMode)
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
