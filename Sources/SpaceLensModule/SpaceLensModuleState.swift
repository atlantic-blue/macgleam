import Foundation
import GleamCore
import GleamHub
import SpaceLensEngine

/// The narrow engine seam the module model consumes, so tests script the
/// streaming map and the plan without the real engine. SpaceLensEngine is
/// the one production conformance; this protocol adds nothing to C22 and
/// takes nothing from it: `map` and `plan` carry C22's guarantees verbatim.
public protocol SpaceLensMapProviding: Sendable {
  var module: GleamModule { get }
  func map(
    volume: AbsolutePath,
    context: ScanContext
  ) -> AsyncThrowingStream<SpaceLensUpdate, Error>
  func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan
}

extension SpaceLensEngine: SpaceLensMapProviding {}

/// Mints the per session contexts of C15 for Space Lens. Every
/// makeScanContext call mints a fresh session identifier, and plan contexts
/// are bound to exactly their session. A deliberate duplicate of the cleanup
/// module's protocol rather than a shared abstraction; the third module
/// surface extracts the pattern.
public protocol SpaceLensSessionProviding: Sendable {
  func makeScanContext(settings: Settings, hasFullDiskAccess: Bool) async -> ScanContext
  func makePlanContext(sessionID: UUID, settings: Settings) async -> PlanContext
}

/// One node of the streaming tree the thin view renders.
///
/// `allocatedBytesSoFar` never decreases across successive published trees,
/// `hasConverged` flips false to true at most once and never back, and when
/// the stream completes every node has converged with `allocatedBytesSoFar`
/// equal to the engine's final total for the path. `isSelectable` is false
/// for every denylisted path and always false for the volume root, whatever
/// the denylist says: the map never offers deleting the volume it is
/// mapping. `children` is sorted by allocatedBytesSoFar descending, ties
/// broken lexicographically by path, so the rendered map is a pure,
/// reproducible function of the tree.
public struct SpaceLensTreeNode: Sendable, Equatable, Identifiable {
  public var id: AbsolutePath { path }
  public let path: AbsolutePath
  public let isDirectory: Bool
  public let allocatedBytesSoFar: UInt64
  public let hasConverged: Bool
  public let isSelectable: Bool
  public let children: [SpaceLensTreeNode]

  public init(
    path: AbsolutePath,
    isDirectory: Bool,
    allocatedBytesSoFar: UInt64,
    hasConverged: Bool,
    isSelectable: Bool,
    children: [SpaceLensTreeNode]
  ) {
    self.path = path
    self.isDirectory = isDirectory
    self.allocatedBytesSoFar = allocatedBytesSoFar
    self.hasConverged = hasConverged
    self.isSelectable = isSelectable
    self.children = children
  }
}

/// The map as the view renders it: the tree, where the user has drilled to,
/// and what they have selected.
///
/// `root` is nil only before the first node arrives; from then on it is the
/// volume root's node. `focusPath` is always the volume root or a directory
/// node present in the tree. `selectedPaths` contains only selectable nodes
/// and is an antichain under `isDescendant(of:)`: it never contains a path
/// and a descendant of that path, so no byte is ever counted twice.
public struct SpaceLensMapState: Sendable, Equatable {
  public let sessionID: UUID
  public let volume: AbsolutePath
  public let root: SpaceLensTreeNode?
  public let focusPath: AbsolutePath
  public let selectedPaths: Set<AbsolutePath>

  public init(
    sessionID: UUID,
    volume: AbsolutePath,
    root: SpaceLensTreeNode?,
    focusPath: AbsolutePath,
    selectedPaths: Set<AbsolutePath>
  ) {
    self.sessionID = sessionID
    self.volume = volume
    self.root = root
    self.focusPath = focusPath
    self.selectedPaths = selectedPaths
  }

  /// Derived: the sum of `allocatedBytesSoFar` over the selected nodes. A
  /// pure derivation, no stored copy to drift.
  public var selectedByteTotal: UInt64 {
    guard let root else { return 0 }
    var total: UInt64 = 0
    var stack = [root]
    while let node = stack.popLast() {
      if selectedPaths.contains(node.path) {
        total += node.allocatedBytesSoFar
      }
      stack.append(contentsOf: node.children)
    }
    return total
  }
}

/// Where the Space Lens module is. Space Lens is hub chrome, not a card:
/// HubModule has no case for it and the hub's module state slots do not
/// apply. Entry and exit of the surface is chrome wiring; the model owns
/// everything inside it.
public enum SpaceLensModuleState: Sendable, Equatable {
  /// No map this session: the entry state, and the state after a result is
  /// acknowledged, a mapping fails or is cancelled. A result acknowledgement
  /// always lands here, never back on the old map: an executed plan means
  /// the tree no longer matches the disk, and a stale map is worse than no
  /// map.
  case idle
  /// The stream is running. The map grows, drill and selection work,
  /// execution is refused until completion.
  case mapping(SpaceLensMapState)
  /// The stream completed: every total converged and true. The only state
  /// that admits executeSelection, so every byte figure a confirmation
  /// names is a true allocated total, never an estimate.
  case browsing(SpaceLensMapState)
  case executing(SpaceLensExecutionProgress)
  case result(SpaceLensResultSummary)
}

/// One drill step, as data, for the view to animate. Reuses the hub zoom
/// grammar: the view resolves `direction` through HubZoomResolver, so
/// drilling into a folder uses exactly the animation tokens the hub zoom
/// uses and the whole app keeps one navigation language. HubZoom itself is
/// not reused: it names a HubModule, and a folder is not a module.
public struct SpaceLensDrill: Sendable, Equatable {
  public let target: AbsolutePath
  public let direction: HubZoomDirection

  public init(target: AbsolutePath, direction: HubZoomDirection) {
    self.target = target
    self.direction = direction
  }
}

/// Execution progress as the view renders it. `finishedOperations` and
/// `bytesReclaimed` never decrease across successive executing states,
/// `finishedOperations` never exceeds `totalOperations`, and
/// `currentOperationID` is the operation the executor last reported started
/// and not yet finished, nil between operations.
public struct SpaceLensExecutionProgress: Sendable, Equatable {
  public let planID: UUID
  public let totalOperations: UInt32
  public let finishedOperations: UInt32
  public let bytesReclaimed: UInt64
  public let currentOperationID: UUID?

  public init(
    planID: UUID,
    totalOperations: UInt32,
    finishedOperations: UInt32,
    bytesReclaimed: UInt64,
    currentOperationID: UUID?
  ) {
    self.planID = planID
    self.totalOperations = totalOperations
    self.finishedOperations = min(finishedOperations, totalOperations)
    self.bytesReclaimed = bytesReclaimed
    self.currentOperationID = currentOperationID
  }
}

/// The result screen's whole content, derived from exactly one execution
/// report and consistent with it: `bytesReclaimed` equals the report's
/// total, and the counts sum to one entry per operation in the plan.
/// `failures` carries one plain sentence per failed operation, in plan
/// order. `skippedDenylistedNames` carries the last path component of each
/// denylist skip, in plan order, reported as the safety system working,
/// distinct from failure. `notStartedCount` counts a cancelled run's
/// untouched operations, which is how the partial result says exactly which
/// is which.
public struct SpaceLensResultSummary: Sendable, Equatable {
  public let bytesReclaimed: UInt64
  public let completedCount: UInt32
  public let failedCount: UInt32
  public let notStartedCount: UInt32
  public let failures: [String]
  public let skippedDenylistedNames: [String]

  public init(
    bytesReclaimed: UInt64,
    completedCount: UInt32,
    failedCount: UInt32,
    notStartedCount: UInt32,
    failures: [String],
    skippedDenylistedNames: [String]
  ) {
    self.bytesReclaimed = bytesReclaimed
    self.completedCount = completedCount
    self.failedCount = failedCount
    self.notStartedCount = notStartedCount
    self.failures = failures
    self.skippedDenylistedNames = skippedDenylistedNames
  }
}

/// Why executeSelection did not start. Returned, never thrown; the state is
/// unchanged in every case.
public enum SpaceLensCommandRefusal: Sendable, Equatable {
  case notBrowsing
  /// The stream is still running: totals are not yet true, so no
  /// confirmation could name honest counts.
  case mappingStillRunning
  case emptySelection
  case permanentDeletionUnconfirmed(required: PermanentDeletionScope)
  case confirmationMismatch(required: PermanentDeletionScope)
}
