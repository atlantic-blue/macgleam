import Foundation
import GleamCore

/// Where the Protection module is. One closed lifecycle, the same shape as
/// Cleanup's, because a person moving between the two modules should not have
/// to learn a second grammar.
public enum ProtectionModuleState: Sendable, Equatable {
  case idle
  case scanning(ProtectionScanProgress)
  case reviewing(ProtectionReviewState)
  case executing(ProtectionExecutionProgress)
  case result(ProtectionResultSummary)
  /// The scan finished and found nothing. The designed reward state: it says
  /// what was checked rather than showing an empty list.
  case allClear(filesChecked: UInt64)
}

public struct ProtectionScanProgress: Sendable, Equatable {
  public let sessionID: UUID
  public let phase: ScanPhase
  public let counters: ScanCounters

  public init(sessionID: UUID, phase: ScanPhase, counters: ScanCounters) {
    self.sessionID = sessionID
    self.phase = phase
    self.counters = counters
  }
}

/// What the review shows, split the way a person decides.
///
/// Threats and traces are two lists rather than one, because they are two
/// different questions. A detection is something nobody chose to have and it
/// arrives ticked; a browser history is something a person made and it never
/// does. Putting them in one list would make one checkbox mean both.
public struct ProtectionReviewState: Sendable, Equatable {
  public let sessionID: UUID
  public let threats: [Finding]
  public let traces: [Finding]
  public let selectedFindingIDs: Set<UUID>

  public init(
    sessionID: UUID,
    threats: [Finding],
    traces: [Finding],
    selectedFindingIDs: Set<UUID>
  ) {
    self.sessionID = sessionID
    self.threats = threats
    self.traces = traces
    let known = Set((threats + traces).map(\.id))
    self.selectedFindingIDs = selectedFindingIDs.intersection(known)
  }

  public var selectedFindings: [Finding] {
    (threats + traces).filter { selectedFindingIDs.contains($0.id) }
  }

  public var selectedByteTotal: UInt64 {
    selectedFindings.reduce(0) { $0 + $1.byteSize }
  }

  /// The traces a person ticked, which are the rows that will be deleted
  /// rather than contained. The confirmation a run needs is built from
  /// exactly these.
  public var selectedTraces: [Finding] {
    traces.filter { selectedFindingIDs.contains($0.id) }
  }
}

public struct ProtectionExecutionProgress: Sendable, Equatable {
  public let planID: UUID
  public let totalOperations: UInt32
  public let finishedOperations: UInt32
  public let currentOperationID: UUID?

  public init(
    planID: UUID,
    totalOperations: UInt32,
    finishedOperations: UInt32,
    currentOperationID: UUID?
  ) {
    self.planID = planID
    self.totalOperations = totalOperations
    self.finishedOperations = min(finishedOperations, totalOperations)
    self.currentOperationID = currentOperationID
  }
}

/// What the result screen says. Contained and cleared are counted apart,
/// because one of them is reversible and the other is not, and a screen that
/// added them together would be hiding exactly the difference that matters.
public struct ProtectionResultSummary: Sendable, Equatable {
  public let containedCount: UInt32
  public let clearedCount: UInt32
  public let bytesReclaimed: UInt64
  public let failures: [String]
  public let skippedDenylistedNames: [String]

  public init(
    containedCount: UInt32,
    clearedCount: UInt32,
    bytesReclaimed: UInt64,
    failures: [String],
    skippedDenylistedNames: [String]
  ) {
    self.containedCount = containedCount
    self.clearedCount = clearedCount
    self.bytesReclaimed = bytesReclaimed
    self.failures = failures
    self.skippedDenylistedNames = skippedDenylistedNames
  }
}

/// Why a run did not start. Returned rather than thrown, so a thin view
/// branches on it; the state is unchanged in every case.
public enum ProtectionCommandRefusal: Sendable, Equatable {
  case notReviewing
  case emptySelection
  /// Traces are cleared permanently, so the selection needs a confirmation
  /// naming their exact counts before anything runs.
  case tracesUnconfirmed(required: PermanentDeletionScope)
  case confirmationMismatch(required: PermanentDeletionScope)
}
