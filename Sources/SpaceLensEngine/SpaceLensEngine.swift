import Foundation
import GleamCore

/// One event of the streaming disk map. Nodes stream with parents before
/// children, size revisions only ever increase a path's subtree total, and
/// exactly one `completed` terminates a successful stream.
public enum SpaceLensUpdate: Sendable, Equatable {
  case node(SpaceLensNode)
  case sizeRevision(path: AbsolutePath, subtreeBytes: UInt64)
  case completed
}

/// One discovered node of the map. `subtreeBytes` is the allocated total
/// known when the node streamed; later `sizeRevision` events grow it towards
/// the true allocated subtree total.
public struct SpaceLensNode: Sendable, Equatable {
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
/// Planning turns spaceLensSelection findings into the standard operation
/// plan: Trash by default, permanent deletion only when the user opted in,
/// with denylist exclusions exact and totals summed from the findings' own
/// entries.
public struct SpaceLensEngine: GleamEngine {
  public var module: GleamModule { .spaceLens }

  public init() {}

  /// Space Lens has no rule driven scan surface: findings are minted from
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
  ) -> AsyncThrowingStream<SpaceLensUpdate, Error> {
    AsyncThrowingStream { continuation in
      let mapTask = Task {
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

extension SpaceLensEngine {
  /// Walks the volume and streams the growing tree. Enumeration order is not
  /// guaranteed, so any ancestor a record arrives ahead of is synthesised
  /// first, which keeps parents streaming before children. Every record's
  /// allocated bytes propagate up the ancestor chain as size revisions, so
  /// per path totals only ever grow and converge to the true allocated
  /// subtree totals when the walk ends.
  fileprivate static func runMap(
    volume: AbsolutePath,
    context: ScanContext,
    yield: @escaping @Sendable (SpaceLensUpdate) -> Void
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
  }

  fileprivate struct MapWalk {
    private let volume: AbsolutePath
    private let denylist: Denylist
    private let yield: @Sendable (SpaceLensUpdate) -> Void
    private var totals: [AbsolutePath: UInt64] = [:]
    private var emitted: Set<AbsolutePath> = []

    init(
      volume: AbsolutePath,
      denylist: Denylist,
      yield: @escaping @Sendable (SpaceLensUpdate) -> Void
    ) {
      self.volume = volume
      self.denylist = denylist
      self.yield = yield
    }

    mutating func emitRoot(_ record: FileRecord) {
      totals[volume] = record.allocatedBytes
      emitted.insert(volume)
      yield(
        .node(
          SpaceLensNode(
            path: volume,
            parent: nil,
            isDirectory: record.isDirectory,
            subtreeBytes: record.allocatedBytes,
            isSelectable: !denylist.blocks(volume))))
    }

    mutating func absorb(_ record: FileRecord) {
      guard record.path.isDescendant(of: volume) else { return }
      emitMissingAncestors(of: record.path)
      if emitted.insert(record.path).inserted {
        totals[record.path] = record.allocatedBytes
        yield(
          .node(
            SpaceLensNode(
              path: record.path,
              parent: parentPath(of: record.path),
              isDirectory: record.isDirectory,
              subtreeBytes: record.allocatedBytes,
              isSelectable: !denylist.blocks(record.path))))
      } else if record.allocatedBytes > 0 {
        grow(record.path, by: record.allocatedBytes)
      }
      guard record.allocatedBytes > 0 else { return }
      var ancestor = parentPath(of: record.path)
      while let current = ancestor {
        grow(current, by: record.allocatedBytes)
        guard current != volume else { break }
        ancestor = parentPath(of: current)
      }
    }

    /// Synthesises any directory between the volume root and the record that
    /// has not streamed yet, top down, so a child never precedes its parent.
    private mutating func emitMissingAncestors(of path: AbsolutePath) {
      var chain: [AbsolutePath] = []
      var ancestor = parentPath(of: path)
      while let current = ancestor, current != volume {
        chain.append(current)
        ancestor = parentPath(of: current)
      }
      for directory in chain.reversed() where !emitted.contains(directory) {
        emitted.insert(directory)
        totals[directory] = totals[directory] ?? 0
        yield(
          .node(
            SpaceLensNode(
              path: directory,
              parent: parentPath(of: directory),
              isDirectory: true,
              subtreeBytes: totals[directory] ?? 0,
              isSelectable: !denylist.blocks(directory))))
      }
    }

    private mutating func grow(_ path: AbsolutePath, by bytes: UInt64) {
      let next = (totals[path] ?? 0) + bytes
      totals[path] = next
      yield(.sizeRevision(path: path, subtreeBytes: next))
    }

    /// The containing directory, computed on the normalised value because
    /// the walk never leaves the volume. Nil at the file system root.
    private func parentPath(of path: AbsolutePath) -> AbsolutePath? {
      guard path.value != "/" else { return nil }
      let components = path.value.split(separator: "/").dropLast()
      guard !components.isEmpty else { return AbsolutePath(normalising: "/") }
      return AbsolutePath(normalising: "/" + components.joined(separator: "/"))
    }
  }
}

// MARK: - Planning

extension SpaceLensEngine {
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
