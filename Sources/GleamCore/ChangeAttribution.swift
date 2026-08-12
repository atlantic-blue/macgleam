import Foundation

/// What a change is attributable to. There is no case meaning unknown and no
/// optional field: which of the two it is, is a fact about how the change was
/// asked for, recorded at that moment and never inferred afterwards.
///
/// The two callers are the executor, which is running one operation of a plan
/// and is the only thing that knows both identifiers, and the Performance
/// module, which is passing on a switch somebody flipped in the interface. A
/// direct change is attributable to itself rather than to a synthetic single
/// operation plan: an identifier in the helper's log that matches no plan the
/// app ever built reconciles to something that did not happen, which is worse
/// than no attribution at all.
public enum ChangeAttribution: Codable, Sendable, Equatable, Hashable {
  /// One operation of a plan the executor is running (C6, C17).
  case operation(planID: UUID, operationID: UUID)
  /// One change a person made directly in the interface, outside any plan.
  /// `changeID` is minted at the moment of the change and identifies nothing
  /// else: no plan carries it and no `ExecutionReport` names it.
  case directChange(changeID: UUID)

  /// The plan this change belongs to, and nil for a direct change, which
  /// belongs to none. Nil is the whole point rather than a missing value: a
  /// change somebody made by hand has no plan to be reconciled against.
  public var planID: UUID? {
    guard case .operation(let planID, _) = self else { return nil }
    return planID
  }

  /// The identifier a reply echoes to tie itself to the request that caused
  /// it. Never nil, so reconciliation needs no special case for either kind.
  public var correlationID: UUID {
    switch self {
    case .operation(_, let operationID):
      return operationID
    case .directChange(let changeID):
      return changeID
    }
  }
}
