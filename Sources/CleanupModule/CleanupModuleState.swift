import Foundation
import GleamCore

/// Where the cleanup module is. One closed lifecycle; the degraded banner is
/// not a state here because degraded scanning still scans, so it rides
/// alongside as `degradedNotices` on the model.
public enum CleanupModuleState: Sendable, Equatable {
  /// No scan this session. The entry state, and the state after a result is
  /// acknowledged or a scan fails or is cancelled.
  case idle
  case scanning(CleanupScanProgress)
  case reviewing(CleanupReviewState)
  case executing(CleanupExecutionProgress)
  case result(CleanupResultSummary)
  /// The scan completed and found nothing. The designed reward state, never
  /// a blank panel: it says what was checked.
  case cleanSweep(filesChecked: UInt64)
}

/// Scan progress as the view renders it: the three phase choreography plus
/// the live counters. The phase only ever advances (indeterminate,
/// determinate, settling; determinate may be skipped, never revisited) and
/// the counters never decrease across successive scanning states.
public struct CleanupScanProgress: Sendable, Equatable {
  public let sessionID: UUID
  public let phase: ScanPhase
  public let counters: ScanCounters

  public init(sessionID: UUID, phase: ScanPhase, counters: ScanCounters) {
    self.sessionID = sessionID
    self.phase = phase
    self.counters = counters
  }
}

/// One category group in review, in the order its first finding streamed.
public struct CleanupReviewCategory: Sendable, Equatable, Identifiable {
  public let category: FindingCategory
  public let findings: [Finding]
  public var id: FindingCategory { category }

  public init(category: FindingCategory, findings: [Finding]) {
    self.category = category
    self.findings = findings
  }
}

/// The reviewed findings and the current selection. The selection only ever
/// names findings present in `categories`; the byte and file totals are pure
/// derivations over the selected findings, with no stored copies to drift.
public struct CleanupReviewState: Sendable, Equatable {
  public let sessionID: UUID
  public let categories: [CleanupReviewCategory]
  public let selectedFindingIDs: Set<UUID>

  public init(sessionID: UUID, categories: [CleanupReviewCategory], selectedFindingIDs: Set<UUID>) {
    self.sessionID = sessionID
    self.categories = categories
    let knownIDs = Set(categories.flatMap { $0.findings.map(\.id) })
    self.selectedFindingIDs = selectedFindingIDs.intersection(knownIDs)
  }

  public var selectedByteTotal: UInt64 {
    selectedFindings.reduce(0) { $0 + $1.byteSize }
  }

  public var selectedFileCount: UInt32 {
    UInt32(selectedFindings.reduce(0) { $0 + $1.paths.count })
  }

  var selectedFindings: [Finding] {
    categories.flatMap(\.findings).filter { selectedFindingIDs.contains($0.id) }
  }
}

/// Execution progress as the view renders it: per operation completion and
/// the reclaimed figure ticking up. `finishedOperations` and `bytesReclaimed`
/// never decrease across successive executing states, and `finishedOperations`
/// never exceeds `totalOperations`. `currentOperationID` is the operation the
/// executor last reported started and not yet finished, nil between
/// operations.
public struct CleanupExecutionProgress: Sendable, Equatable {
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

/// The execution report summarised for the result screen. Everything that
/// screen renders is here, so the screen is testable without SwiftUI.
/// `failures` carries one plain sentence per failed operation, in plan order:
/// what failed and what was and was not done, never a code.
/// `skippedDenylistedNames` carries the last path component of each operation
/// skipped by the denylist, in plan order; a skip is the safety system
/// working, distinct from failure.
public struct CleanupResultSummary: Sendable, Equatable {
  public let bytesReclaimed: UInt64
  public let categoryOutcomes: [CleanupCategoryOutcome]
  public let failures: [String]
  public let skippedDenylistedNames: [String]

  public init(
    bytesReclaimed: UInt64,
    categoryOutcomes: [CleanupCategoryOutcome],
    failures: [String],
    skippedDenylistedNames: [String]
  ) {
    self.bytesReclaimed = bytesReclaimed
    self.categoryOutcomes = categoryOutcomes
    self.failures = failures
    self.skippedDenylistedNames = skippedDenylistedNames
  }
}

public struct CleanupCategoryOutcome: Sendable, Equatable {
  public let category: FindingCategory
  public let completedCount: UInt32
  public let failedCount: UInt32
  public let skippedCount: UInt32
  public let notStartedCount: UInt32
  public let bytesReclaimed: UInt64

  public init(
    category: FindingCategory,
    completedCount: UInt32,
    failedCount: UInt32,
    skippedCount: UInt32,
    notStartedCount: UInt32,
    bytesReclaimed: UInt64
  ) {
    self.category = category
    self.completedCount = completedCount
    self.failedCount = failedCount
    self.skippedCount = skippedCount
    self.notStartedCount = notStartedCount
    self.bytesReclaimed = bytesReclaimed
  }
}

/// Why executeSelection did not start. Returned, never thrown, so the thin
/// view branches on it directly; the state is unchanged in every case.
public enum CleanupCommandRefusal: Sendable, Equatable {
  case notReviewing
  case emptySelection
  /// The selection plans permanent deletions and no confirmation was passed.
  /// Carries the scope the confirmation must name.
  case permanentDeletionUnconfirmed(required: PermanentDeletionScope)
  /// A confirmation was passed but its counts do not match the scope.
  case confirmationMismatch(required: PermanentDeletionScope)
}
