import Foundation
import GleamCore

/// The one place the contract version is declared, in the package both
/// processes link, so app and helper cannot disagree about what the current
/// contract is without one of them being an older build. Any change to the
/// message set below bumps this in the same commit as the change.
public enum HelperContract {
  public static let version: UInt16 = 3
}

/// The complete message set from MacGleam.app to GleamHelper.
///
/// The set is closed: there is no request carrying a command string, a shell
/// fragment or an arbitrary verb, so the helper is not a general file service.
/// Every mutating request names the plan and the operation it belongs to, so
/// the helper's log and the app's report reconcile one to one, and `remove`
/// carries an explicit destination so the helper never chooses where a file
/// goes.
public enum HelperRequest: Codable, Sendable, Equatable {
  case handshake(contractVersion: UInt16)
  case remove(
    target: AbsolutePath, destination: HelperRemovalDestination, planID: UUID, operationID: UUID)
  /// The attribution is the plan operation or the direct change this belongs
  /// to (C24), and it replaces the plan and operation identifiers the other
  /// requests carry. It is not optional and `ChangeAttribution` has no case
  /// meaning none, so a privileged launch item change that says nothing about
  /// who asked for it cannot be built, let alone sent.
  case setLaunchItemEnabled(item: LaunchItemID, enabled: Bool, attribution: ChangeAttribution)
  case runMaintenance(task: MaintenanceTask, planID: UUID, operationID: UUID)
  /// Take a system domain payload into the SafetyNet store at exactly
  /// `storedPath`, contain it, and report what was measured and snapshotted at
  /// the origin. The store chooses `storedPath` and `itemID`; the helper
  /// chooses nothing.
  case archiveIntoSafetyNet(target: AbsolutePath, storedPath: AbsolutePath, itemID: UUID)
  /// Read back the stamp of a payload already archived. The recovery path for
  /// a store whose archive reply never arrived.
  case describeArchived(storedPath: AbsolutePath, itemID: UUID)
  /// Put the payload back where its own stamp says it came from. Carries no
  /// origin and no metadata by design: the request is the part an attacker
  /// would choose.
  case restoreArchived(storedPath: AbsolutePath, itemID: UUID)
  /// Delete the payload permanently. The purge of a root owned payload.
  case discardArchived(storedPath: AbsolutePath, itemID: UUID)

  /// The plan this request belongs to. Nil for the handshake, which belongs to
  /// the connection rather than to any plan; nil for a launch item change
  /// somebody made directly in the interface; and nil for the whole archive
  /// family, whose attribution is the SafetyNet item rather than a plan,
  /// because an archive outlives the plan that caused it and a restore months
  /// later belongs to no plan at all.
  public var planID: UUID? {
    switch self {
    case .handshake:
      return nil
    case .remove(_, _, let planID, _), .runMaintenance(_, let planID, _):
      return planID
    case .setLaunchItemEnabled(_, _, let attribution):
      guard case .operation(let planID, _) = attribution else { return nil }
      return planID
    case .archiveIntoSafetyNet, .describeArchived, .restoreArchived, .discardArchived:
      return nil
    }
  }

  /// The identifier the reply echoes to tie itself to this request. Nil for
  /// the handshake, which performs nothing. For a planned operation it is the
  /// operation identifier; for a direct change it is the change identifier,
  /// which appears in no plan, so a refusal reconciles one to one either way.
  public var correlationID: UUID? {
    switch self {
    case .handshake:
      return nil
    case .remove(_, _, _, let operationID), .runMaintenance(_, _, let operationID):
      return operationID
    case .setLaunchItemEnabled(_, _, let attribution):
      return attribution.correlationID
    case .archiveIntoSafetyNet(_, _, let itemID), .describeArchived(_, let itemID),
      .restoreArchived(_, let itemID), .discardArchived(_, let itemID):
      return itemID
    }
  }
}

/// Where a removed file goes. The helper never decides this. There are two,
/// and an archive is not one of them: a `safetyNetStore(storeDirectory:)` case
/// was removed at version 3 because it named a directory for the helper to
/// pick a name in, which is how a payload came to sit in the store with
/// nothing recording it.
public enum HelperRemovalDestination: Codable, Sendable, Equatable {
  /// Move into the requesting user's trash, transferring ownership so the
  /// user can restore it.
  case userTrash(userHome: AbsolutePath)
  case permanent
}

/// The complete message set from GleamHelper back to MacGleam.app.
public enum HelperResponse: Codable, Sendable, Equatable {
  /// The versions agreed. The value is the version now in force, which is the
  /// helper's own and, by that agreement, the app's too.
  case handshakeAccepted(contractVersion: UInt16)
  /// The versions disagreed. Sent for that reason and no other, and it names
  /// both by construction, so the app never has to infer which side is
  /// behind. The two are never equal in this reply.
  case handshakeRefused(helperContractVersion: UInt16, clientContractVersion: UInt16)
  case success(correlationID: UUID, bytesReclaimed: UInt64)
  case launchItemChanged(correlationID: UUID, change: LaunchItemChange)
  /// Answers `archiveIntoSafetyNet` and `describeArchived` alike, because the
  /// report of making an archive and a description of that archive are one
  /// fact read at two moments. The correlation identifier is the item's.
  case archived(correlationID: UUID, report: PrivilegedArchiveReport)
  /// The payload went back to the origin its own stamp named, and that path is
  /// carried here so the store can check it against the item it holds rather
  /// than take the move on trust.
  case restoredArchive(correlationID: UUID, originPath: AbsolutePath)
  /// The payload is gone. It carries no byte figure: the purge total is the
  /// sum of sizes recorded at store time, and a second figure measured here
  /// could only disagree with it.
  case discardedArchive(correlationID: UUID)
  /// Every refusal that is not a version disagreement, including a handshake
  /// refused on identity. It echoes the correlation identifier of the request
  /// it refused where there is one, and it names no version: a client the
  /// helper could not verify is told nothing about the helper.
  case refused(correlationID: UUID?, reason: HelperRefusal)
  case failed(correlationID: UUID, reason: String)
}

public enum HelperRefusal: String, Codable, Sendable, Equatable {
  /// Target blocked by the helper's own denylist.
  case denylisted
  /// Target is user domain; least privilege cuts both ways.
  case notSystemDomain
  /// No version agreed on this connection, or the agreed versions differ.
  case versionMismatch
  /// The connecting client failed code signing verification.
  case identityRejected
  case malformedRequest
  /// The archive path in the request is not one the helper will write to or
  /// act on: outside the connecting user's home, not the shape of a store
  /// payload, a component that is a symbolic link, a parent that does not
  /// exist, or a payload that is not root owned and stamped where the request
  /// requires one.
  case destinationRejected
}
