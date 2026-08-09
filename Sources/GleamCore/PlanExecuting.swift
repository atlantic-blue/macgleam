import Foundation

/// Why an execution run was refused, in whole or from a given item onward.
public enum ExecutionRefusal: Sendable, Equatable {
  /// The plan contains permanent deletions and its confirmation is missing
  /// or does not name the exact file count and byte total.
  case permanentDeletionUnconfirmed
  /// An operation routed to the privileged helper and no helper is
  /// available. The reason is a plain sentence.
  case helperUnavailable(reason: String)
}

/// One step in the ordered account of a plan run.
public enum ExecutionEvent: Sendable, Equatable {
  case refused(ExecutionRefusal)
  case operationStarted(operationID: UUID)
  case operationFinished(operationID: UUID, result: OperationResult)
  case planCompleted(ExecutionReport)
}

/// The only component that performs destructive work in the user process.
/// Routes each operation to the user process file system or to the helper by
/// path ownership, atomically per item. The stream always terminates with
/// exactly one `planCompleted` carrying the full report, whatever happened,
/// including refusal and cancellation.
public protocol PlanExecuting: Sendable {
  func execute(_ plan: OperationPlan) -> AsyncStream<ExecutionEvent>
}
