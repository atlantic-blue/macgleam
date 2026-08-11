import Foundation
import GleamCore

/// The one place the contract version is declared, in the package both
/// processes link, so app and helper cannot disagree about what the current
/// contract is without one of them being an older build. Any change to the
/// message set below bumps this in the same commit as the change.
public enum HelperContract {
  public static let version: UInt16 = 1
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
  case setLaunchItemEnabled(item: LaunchItemID, enabled: Bool, planID: UUID, operationID: UUID)
  case runMaintenance(task: MaintenanceTask, planID: UUID, operationID: UUID)

  /// The plan this request belongs to, and nil for the handshake, which
  /// belongs to the connection rather than to any plan.
  public var planID: UUID? {
    switch self {
    case .handshake:
      return nil
    case .remove(_, _, let planID, _), .setLaunchItemEnabled(_, _, let planID, _),
      .runMaintenance(_, let planID, _):
      return planID
    }
  }

  /// The operation this request performs, and nil for the handshake, which
  /// performs none.
  public var operationID: UUID? {
    switch self {
    case .handshake:
      return nil
    case .remove(_, _, _, let operationID), .setLaunchItemEnabled(_, _, _, let operationID),
      .runMaintenance(_, _, let operationID):
      return operationID
    }
  }
}

/// Where a removed file goes. The helper never decides this.
public enum HelperRemovalDestination: Codable, Sendable, Equatable {
  /// Move into the requesting user's trash, transferring ownership so the
  /// user can restore it.
  case userTrash(userHome: AbsolutePath)
  /// Move into the SafetyNet store directory provided by the app.
  case safetyNetStore(storeDirectory: AbsolutePath)
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
  case success(operationID: UUID, bytesReclaimed: UInt64)
  case launchItemChanged(operationID: UUID, change: LaunchItemChange)
  /// Every refusal that is not a version disagreement, including a handshake
  /// refused on identity. It names the operation it refused where there is
  /// one, and it names no version: a client the helper could not verify is
  /// told nothing about the helper.
  case refused(operationID: UUID?, reason: HelperRefusal)
  case failed(operationID: UUID, reason: String)
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
}
