import Foundation

/// The privileged half of execution, as the executor sees it.
///
/// The executor decides what needs privilege and what does not (C16 ownership
/// at run time, C17 order); this is the only way it can reach a process that
/// has privilege. The implementation is the helper client, which talks to the
/// root daemon over XPC (inter process communication), but nothing in the
/// executor knows that: from here a privileged operation is one call that
/// always answers with a result and never throws, so a helper that is missing,
/// unapproved, out of date or answering nonsense costs one operation rather
/// than the run.
public protocol PrivilegedOperationPerforming: Sendable {
  func perform(_ operation: Operation, planID: UUID) async -> OperationResult
}
