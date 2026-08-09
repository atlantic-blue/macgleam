import Foundation

/// Evidence that the user saw and confirmed the exact scope of a permanent
/// deletion. Constructed by the UI at confirmation time, validated by the
/// executor.
public struct PermanentDeletionConfirmation: Codable, Sendable, Equatable {
  public let fileCount: UInt32
  public let byteTotal: UInt64
  public let confirmedAt: Date

  public init(fileCount: UInt32, byteTotal: UInt64, confirmedAt: Date) {
    self.fileCount = fileCount
    self.byteTotal = byteTotal
    self.confirmedAt = confirmedAt
  }
}

/// An ordered, executable description of destructive work, derived from the
/// user's reviewed selection. The only input the executor accepts. Plans are
/// immutable once built; deselecting in the UI builds a new plan.
public struct OperationPlan: Identifiable, Codable, Sendable, Equatable {
  public let id: UUID
  public let sessionID: UUID
  public let operations: [Operation]
  public let totalBytes: UInt64
  public let permanentDeletionConfirmation: PermanentDeletionConfirmation?

  public init(
    id: UUID,
    sessionID: UUID,
    operations: [Operation],
    totalBytes: UInt64,
    permanentDeletionConfirmation: PermanentDeletionConfirmation?
  ) {
    self.id = id
    self.sessionID = sessionID
    self.operations = operations
    self.totalBytes = totalBytes
    self.permanentDeletionConfirmation = permanentDeletionConfirmation
  }

  /// The number of permanent deletion operations in the plan. A plan
  /// containing any must carry a confirmation whose fileCount equals this.
  public var permanentOperationCount: Int {
    operations.filter {
      if case .deletePermanently = $0.kind { return true }
      return false
    }.count
  }

  /// True when the confirmation rule holds: no permanent operations, or a
  /// confirmation whose fileCount equals the count of permanent operations.
  public var hasValidPermanentDeletionConfirmation: Bool {
    let permanentCount = permanentOperationCount
    guard permanentCount > 0 else { return true }
    guard let confirmation = permanentDeletionConfirmation else { return false }
    return confirmation.fileCount == UInt32(permanentCount)
  }
}
