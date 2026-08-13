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
      // A walk runs below whatever asked for it. Reading a few hundred
      // thousand files at the interface's own priority makes the whole machine
      // feel slow while a scan is on, and nobody is waiting on any single file
      // of it.
      let scanTask = Task(priority: .utility) {
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
    var batches = FindingBatches(rules: partition.active, sessionID: context.sessionID)
    try await walk(context, batches: &batches, yield: yield)
    yield(.phase(.determinate(estimatedTotalFiles: batches.filesSeen)))
    batches.flushRemaining(yield: yield)
    yield(.phase(.settling))
  }

  /// One pass over the tree, testing every rule against each record as it
  /// arrives. Nothing proportional to files seen is retained: a matched record
  /// lands in its rule's open batch and the batch leaves as a finding the
  /// moment it fills, so live memory is the open batches and nothing else.
  private static func walk(
    _ context: ScanContext,
    batches: inout FindingBatches,
    yield: (ScanEvent) -> Void
  ) async throws {
    let options = EnumerationOptions(
      includesHiddenFiles: true,
      descendsIntoPackages: true,
      skipSubtrees: [])
    let root = AbsolutePath(normalising: "/")
    for try await event in context.fileSystem.enumerate(root: root, options: options) {
      try Task.checkCancellation()
      guard case .record(let record) = event, !record.isDirectory else { continue }
      batches.match(record, denylist: context.rules.denylist, yield: yield)
      batches.countFile(at: record.path, yield: yield)
    }
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

  fileprivate struct FindingSeed {
    let sessionID: UUID
    let rule: CleanupRule
    let category: FindingCategory
    let records: [FileRecord]
  }

  fileprivate static func makeFinding(_ seed: FindingSeed) -> Finding {
    Finding(
      id: UUID(),
      sessionID: seed.sessionID,
      category: seed.category,
      entries: seed.records.map { PathEntry(path: $0.path, allocatedBytes: $0.allocatedBytes) },
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
  fileprivate static func matches(rule: CleanupRule, pathComponents: [String]) -> Bool {
    rule.pathPatterns.contains { $0.matchesPathOrAncestor(of: pathComponents) }
  }

  /// The volume a trash bin lives on: /Volumes/Name for an external bin,
  /// the root volume for everything else.
  fileprivate static func volume(containing path: AbsolutePath) -> AbsolutePath {
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

  fileprivate static func isTrashBinCategory(_ category: FindingCategory) -> Bool {
    if case .trashBin = category { return true }
    return false
  }
}

// MARK: - Batching

/// The open batches of one Cleanup scan, one per rule and category, plus the
/// scan's counters. A batch leaves as a finding when it reaches the entry cap,
/// when the walk ends, or, for a rule that has emitted nothing yet, at the
/// first file checkpoint at or after its first match, so a sparse category
/// streams a row early instead of waiting for the end of the walk. Every
/// trigger is a count of files or entries, so where the boundaries fall does
/// not move with how fast the disk answers.
private struct FindingBatches {
  private struct BinKey: Hashable {
    let ruleIndex: Int
    let volume: AbsolutePath
  }

  /// One rule and category's open records. Batches live in an array in order
  /// of first match. Every rule but a trash bin rule has exactly one category,
  /// so its batch is reached by rule index alone and a matched file costs an
  /// array append and nothing else; only a bin, whose category carries its
  /// volume, needs a lookup by volume.
  private struct Batch {
    let ruleIndex: Int
    let category: FindingCategory
    var records: [FileRecord] = []
    var hasEmitted = false
  }

  private let rules: [CleanupRule]
  private let sessionID: UUID
  private var batches: [Batch] = []
  private var slotOfRule: [Int?]
  private var slotOfBin: [BinKey: Int] = [:]
  private var counters = ScanCounters.zero

  var filesSeen: UInt64 { counters.filesSeen }

  init(rules: [CleanupRule], sessionID: UUID) {
    self.rules = rules
    self.sessionID = sessionID
    self.slotOfRule = Array(repeating: nil, count: rules.count)
  }

  /// Files a record into the batch of every rule it matches. The path is split
  /// into components once and both the rule patterns and the denylist read
  /// those components, so the cost per file is a handful of string comparisons
  /// rather than a rebuilt ancestor chain per rule.
  mutating func match(_ record: FileRecord, denylist: Denylist, yield: (ScanEvent) -> Void) {
    let components = record.path.components
    var isBlocked: Bool?
    for index in rules.indices
    where CleanupEngine.matches(rule: rules[index], pathComponents: components) {
      if isBlocked == nil { isBlocked = denylist.blocks(pathComponents: components) }
      guard isBlocked == false else { return }
      let slot = slot(forRule: index, at: record.path)
      batches[slot].records.append(record)
      guard batches[slot].records.count >= ScanStreamPolicy.maximumFindingEntries else { continue }
      flush(slot, yield: yield)
    }
  }

  /// Counts the file and, at each checkpoint boundary, streams the first batch
  /// of every rule that has emitted nothing yet, however few entries it holds.
  mutating func countFile(at path: AbsolutePath, yield: (ScanEvent) -> Void) {
    counters.filesSeen += 1
    if ProgressCadence.reports(filesSeen: counters.filesSeen) {
      yield(.progress(counters))
      yield(.reading(path))
    }
    guard counters.filesSeen.isMultiple(of: ScanStreamPolicy.firstFindingCheckpointFiles) else {
      return
    }
    for slot in batches.indices where !batches[slot].hasEmitted {
      flush(slot, yield: yield)
    }
  }

  mutating func flushRemaining(yield: (ScanEvent) -> Void) {
    for slot in batches.indices {
      flush(slot, yield: yield)
    }
    // The last report is the one somebody is left looking at, so it is made
    // whatever the cadence did.
    yield(.progress(counters))
  }

  /// The batch a matched file belongs to. A trash bin's volume is part of its
  /// category, so a bin gets one batch series per volume and every batch of it
  /// carries its own volume however many batches the bin takes.
  private mutating func slot(forRule index: Int, at path: AbsolutePath) -> Int {
    guard CleanupEngine.isTrashBinCategory(rules[index].category) else {
      if let existing = slotOfRule[index] { return existing }
      let slot = openBatch(ruleIndex: index, category: rules[index].category)
      slotOfRule[index] = slot
      return slot
    }
    let key = BinKey(ruleIndex: index, volume: CleanupEngine.volume(containing: path))
    if let existing = slotOfBin[key] { return existing }
    let slot = openBatch(ruleIndex: index, category: .trashBin(volume: key.volume))
    slotOfBin[key] = slot
    return slot
  }

  private mutating func openBatch(ruleIndex: Int, category: FindingCategory) -> Int {
    batches.append(Batch(ruleIndex: ruleIndex, category: category))
    return batches.count - 1
  }

  /// Emits one batch as a finding, entries sorted by path, and adds its
  /// entries and bytes to the counters in the same step.
  private mutating func flush(_ slot: Int, yield: (ScanEvent) -> Void) {
    guard !batches[slot].records.isEmpty else { return }
    let records = batches[slot].records
    batches[slot].records = []
    batches[slot].hasEmitted = true
    let finding = CleanupEngine.makeFinding(
      CleanupEngine.FindingSeed(
        sessionID: sessionID,
        rule: rules[batches[slot].ruleIndex],
        category: batches[slot].category,
        records: records.sorted { $0.path < $1.path }))
    counters.itemCount += finding.itemCount
    counters.bytesReclaimable += finding.byteSize
    yield(.finding(finding))
    yield(.progress(counters))
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

    /// The plan's total is the exact sum of the allocated bytes of the
    /// entries its operations target: a denylist exclusion removes exactly
    /// that entry's bytes, nothing is apportioned or estimated.
    mutating func add(_ finding: Finding) {
      let included = finding.entries.filter { !context.rules.denylist.blocks($0.path) }
      guard !included.isEmpty else { return }
      let isPermanent = plansPermanently(finding.category, mode: context.settings.deletionMode)
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
