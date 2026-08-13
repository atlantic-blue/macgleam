import Foundation
import GleamCore

/// One event of the streaming disk map. Nodes stream with parents before
/// children, size revisions only ever increase a path's subtree total, and
/// exactly one `completed` terminates a successful stream.
public enum DiskMapUpdate: Sendable, Equatable {
  case node(DiskMapNode)
  case sizeRevision(path: AbsolutePath, subtreeBytes: UInt64)
  case completed
}

/// One discovered node of the map. `subtreeBytes` is the allocated total
/// known when the node streamed; later `sizeRevision` events grow it towards
/// the true allocated subtree total.
public struct DiskMapNode: Sendable, Equatable {
  public let path: AbsolutePath
  public let parent: AbsolutePath?
  public let isDirectory: Bool
  public let subtreeBytes: UInt64
  public let isSelectable: Bool

  public init(
    path: AbsolutePath,
    parent: AbsolutePath?,
    isDirectory: Bool,
    subtreeBytes: UInt64,
    isSelectable: Bool
  ) {
    self.path = path
    self.parent = parent
    self.isDirectory = isDirectory
    self.subtreeBytes = subtreeBytes
    self.isSelectable = isSelectable
  }
}

/// The streaming disk map engine. `map` streams the tree as it is discovered
/// so the rendered map builds outward from the root while scanning; totals
/// only ever grow and converge to the true allocated subtree totals when the
/// stream completes. A denylisted path renders but is never selectable.
/// Planning turns diskMapSelection findings into the standard operation
/// plan: Trash by default, permanent deletion only when the user opted in,
/// with denylist exclusions exact and totals summed from the findings' own
/// entries.
public struct DiskMapEngine: GleamEngine {
  public var module: GleamModule { .diskMap }

  public init() {}

  /// Disk Map has no rule driven scan surface: findings are minted from
  /// the user's map selection, never discovered. The scan stream therefore
  /// runs the phase choreography and finds nothing.
  public func scan(_ context: ScanContext) -> AsyncThrowingStream<ScanEvent, Error> {
    AsyncThrowingStream { continuation in
      continuation.yield(.phase(.indeterminate))
      continuation.yield(.phase(.settling))
      continuation.finish()
    }
  }

  public func map(
    volume: AbsolutePath,
    context: ScanContext
  ) -> AsyncThrowingStream<DiskMapUpdate, Error> {
    AsyncThrowingStream { continuation in
      // A walk runs below whatever asked for it. Reading a few hundred
      // thousand files at the interface's own priority makes the whole machine
      // feel slow while a scan is on, and nobody is waiting on any single file
      // of it.
      let mapTask = Task(priority: .utility) {
        do {
          try await Self.runMap(volume: volume, context: context) { continuation.yield($0) }
          continuation.yield(.completed)
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in mapTask.cancel() }
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

// MARK: - Mapping

extension DiskMapEngine {
  /// Walks the volume and streams the growing tree. Enumeration order is not
  /// guaranteed, so any ancestor a record arrives ahead of is synthesised
  /// first, which keeps parents streaming before children. Every record's
  /// allocated bytes propagate up the ancestor chain as size revisions, so
  /// per path totals only ever grow and converge to the true allocated
  /// subtree totals when the walk ends.
  fileprivate static func runMap(
    volume: AbsolutePath,
    context: ScanContext,
    yield: @escaping @Sendable (DiskMapUpdate) -> Void
  ) async throws {
    var walk = MapWalk(volume: volume, denylist: context.rules.denylist, yield: yield)
    let rootRecord = try await context.fileSystem.metadata(at: volume)
    walk.emitRoot(rootRecord)
    let options = EnumerationOptions(
      includesHiddenFiles: true,
      descendsIntoPackages: true,
      skipSubtrees: [])
    for try await event in context.fileSystem.enumerate(root: volume, options: options) {
      try Task.checkCancellation()
      guard case .record(let record) = event else { continue }
      walk.absorb(record)
    }
    walk.finish()
  }

  fileprivate struct MapWalk {
    /// Every file grows the total of every directory above it, so revising
    /// on each one costs an event per ancestor per file. Revisions are
    /// accumulated and flushed every this many records instead: totals still
    /// only grow, still converge, and the map redraws in batches rather than
    /// once per byte counted.
    private static let flushInterval = 4_096

    /// What is known about one path: the running allocated total of its
    /// subtree, and the total the stream has already reported for it.
    private struct Subtree {
      var total: UInt64
      var streamed: UInt64
    }

    private let volume: AbsolutePath
    private let denylist: Denylist
    private let yield: @Sendable (DiskMapUpdate) -> Void
    private var subtrees: [AbsolutePath: Subtree] = [:]
    private var pending: Set<AbsolutePath> = []
    private var absorbedSinceFlush = 0

    init(
      volume: AbsolutePath,
      denylist: Denylist,
      yield: @escaping @Sendable (DiskMapUpdate) -> Void
    ) {
      self.volume = volume
      self.denylist = denylist
      self.yield = yield
    }

    mutating func emitRoot(_ record: FileRecord) {
      emit(
        DiskMapNode(
          path: volume,
          parent: nil,
          isDirectory: record.isDirectory,
          subtreeBytes: record.allocatedBytes,
          isSelectable: !denylist.blocks(volume)))
    }

    mutating func absorb(_ record: FileRecord) {
      let ancestors = record.path.ancestors(downTo: volume)
      guard !ancestors.isEmpty else { return }
      emitMissingAncestors(ancestors)
      if subtrees[record.path] == nil {
        emit(
          DiskMapNode(
            path: record.path,
            parent: ancestors.first,
            isDirectory: record.isDirectory,
            subtreeBytes: record.allocatedBytes,
            isSelectable: !denylist.blocks(record.path)))
      } else if record.allocatedBytes > 0 {
        grow(record.path, by: record.allocatedBytes)
      }
      if record.allocatedBytes > 0 {
        for ancestor in ancestors {
          grow(ancestor, by: record.allocatedBytes)
        }
      }
      absorbedSinceFlush += 1
      if absorbedSinceFlush >= Self.flushInterval { flush() }
    }

    /// Reports every total that grew since it was last reported, so the
    /// stream ends on the true allocated subtree totals.
    mutating func finish() {
      flush()
    }

    /// Synthesises any directory between the volume root and the record that
    /// has not streamed yet, top down, so a child never precedes its parent.
    /// The chain arrives nearest first, so it is walked in reverse.
    private mutating func emitMissingAncestors(_ ancestors: [AbsolutePath]) {
      for index in ancestors.indices.reversed() where subtrees[ancestors[index]] == nil {
        emit(
          DiskMapNode(
            path: ancestors[index],
            parent: index + 1 < ancestors.count ? ancestors[index + 1] : nil,
            isDirectory: true,
            subtreeBytes: 0,
            isSelectable: !denylist.blocks(ancestors[index])))
      }
    }

    private mutating func emit(_ node: DiskMapNode) {
      subtrees[node.path] = Subtree(total: node.subtreeBytes, streamed: node.subtreeBytes)
      pending.remove(node.path)
      yield(.node(node))
    }

    private mutating func grow(_ path: AbsolutePath, by bytes: UInt64) {
      subtrees[path, default: Subtree(total: 0, streamed: 0)].total += bytes
      pending.insert(path)
    }

    /// Nearest the root first, so a parent's revision never trails its
    /// child's within a batch.
    private mutating func flush() {
      absorbedSinceFlush = 0
      guard !pending.isEmpty else { return }
      for path in pending.sorted() {
        guard let subtree = subtrees[path], subtree.total > subtree.streamed else { continue }
        subtrees[path]?.streamed = subtree.total
        yield(.sizeRevision(path: path, subtreeBytes: subtree.total))
      }
      pending.removeAll(keepingCapacity: true)
    }
  }
}

// MARK: - Planning

extension DiskMapEngine {
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
