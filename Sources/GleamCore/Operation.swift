import Foundation

/// Stable identifier for a login or background item: label plus scope.
public struct LaunchItemID: Codable, Sendable, Hashable {
  public let value: String

  public init(value: String) {
    self.value = value
  }
}

/// One atomic action. The unit of atomicity for the whole safety story: an
/// operation either fully completes or leaves its target untouched.
public struct Operation: Identifiable, Codable, Sendable, Equatable {
  public enum Kind: Codable, Sendable, Equatable {
    case moveToTrash(target: AbsolutePath)
    case deletePermanently(target: AbsolutePath)
    /// Move into the SafetyNet store, source malware quarantine.
    case quarantine(target: AbsolutePath)
    /// Move into the SafetyNet store, source uninstall archive, grouped so
    /// an uninstall restores as one unit.
    case archive(target: AbsolutePath, groupID: UUID)
    case setLaunchItemEnabled(item: LaunchItemID, enabled: Bool)
    case runMaintenance(task: MaintenanceTask)
  }

  public enum Privilege: String, Codable, Sendable, Equatable {
    case user, root
  }

  public let id: UUID
  public let findingID: UUID
  public let kind: Kind
  public let privilege: Privilege

  public init(id: UUID, findingID: UUID, kind: Kind, privilege: Privilege) {
    self.id = id
    self.findingID = findingID
    self.kind = kind
    self.privilege = privilege
  }
}

/// The outcome of one operation. `skippedDenylisted` is a success of the
/// safety system, not a failure of the run.
public enum OperationResult: Codable, Sendable, Equatable {
  case completed(bytesReclaimed: UInt64)
  case failed(reason: String)
  case skippedDenylisted
  case notStarted
}

/// The closed set of maintenance tasks. Non destructive by design, and
/// idempotent: running one twice is safe and equivalent to once.
public enum MaintenanceTask: String, Codable, Sendable, CaseIterable, Equatable {
  case flushDomainNameSystemCache
  case rebuildLaunchServicesDatabase
  case triggerSpotlightReindex
  case purgeMemoryPressure
  case runPeriodicMaintenance

  /// True for any task whose effect a user can notice as lost data. The UI
  /// must say so before running such a task.
  public var clearsUserVisibleData: Bool {
    self == .flushDomainNameSystemCache
  }
}

/// The complete, ordered account of a plan run. Contains exactly one entry
/// per operation in the plan, in plan order, whatever happened, including
/// cancellation (untouched operations report `notStarted`).
public struct ExecutionReport: Sendable {
  public let planID: UUID
  public let results: [(operationID: UUID, result: OperationResult)]
  public let bytesReclaimed: UInt64
  public let startedAt: Date
  public let finishedAt: Date

  public init(
    planID: UUID,
    results: [(operationID: UUID, result: OperationResult)],
    bytesReclaimed: UInt64,
    startedAt: Date,
    finishedAt: Date
  ) {
    self.planID = planID
    self.results = results
    self.bytesReclaimed = bytesReclaimed
    self.startedAt = startedAt
    self.finishedAt = finishedAt
  }
}

extension ExecutionReport: Equatable {
  public static func == (left: ExecutionReport, right: ExecutionReport) -> Bool {
    left.planID == right.planID
      && left.bytesReclaimed == right.bytesReclaimed
      && left.startedAt == right.startedAt
      && left.finishedAt == right.finishedAt
      && left.results.count == right.results.count
      && zip(left.results, right.results).allSatisfy {
        $0.operationID == $1.operationID && $0.result == $1.result
      }
  }
}

extension ExecutionReport: Codable {
  private struct ResultEntry: Codable {
    let operationID: UUID
    let result: OperationResult
  }

  private enum CodingKeys: String, CodingKey {
    case planID, results, bytesReclaimed, startedAt, finishedAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let entries = try container.decode([ResultEntry].self, forKey: .results)
    self.init(
      planID: try container.decode(UUID.self, forKey: .planID),
      results: entries.map { (operationID: $0.operationID, result: $0.result) },
      bytesReclaimed: try container.decode(UInt64.self, forKey: .bytesReclaimed),
      startedAt: try container.decode(Date.self, forKey: .startedAt),
      finishedAt: try container.decode(Date.self, forKey: .finishedAt)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(planID, forKey: .planID)
    try container.encode(
      results.map { ResultEntry(operationID: $0.operationID, result: $0.result) },
      forKey: .results
    )
    try container.encode(bytesReclaimed, forKey: .bytesReclaimed)
    try container.encode(startedAt, forKey: .startedAt)
    try container.encode(finishedAt, forKey: .finishedAt)
  }
}
