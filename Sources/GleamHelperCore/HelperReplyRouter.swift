import Foundation
import GleamCore

/// Which reply answers which request.
///
/// It lives here, in the package both processes link, rather than inside the
/// daemon, because the echo is a contract promise and a promise kept only in
/// an executable target is a promise nothing can test. The daemon does the
/// work; this decides what the answer looks like.
///
/// One rule runs through all of it: a reply carries the correlation identifier
/// of the request that caused it, whatever kind of request that was. A plan
/// operation echoes its operation identifier and a change somebody made in the
/// interface echoes its own change identifier, so a refusal reconciles one to
/// one without either process inferring which it was.
public struct HelperReplyRouter: Sendable {

  public init() {}

  /// The reply to an admitted request whose work completed. A handshake's
  /// completion is the acceptance, which is why it is not a special case at
  /// the call site.
  public func completed(
    _ request: HelperRequest,
    bytesReclaimed: UInt64,
    contractVersion: UInt16 = HelperContract.version
  ) -> HelperResponse {
    switch request {
    case .handshake:
      return .handshakeAccepted(contractVersion: contractVersion)
    case .remove, .runMaintenance, .setLaunchItemEnabled:
      guard let correlationID = request.correlationID else {
        return .refused(correlationID: nil, reason: .malformedRequest)
      }
      return .success(correlationID: correlationID, bytesReclaimed: bytesReclaimed)
    case .archiveIntoSafetyNet, .describeArchived, .restoreArchived, .discardArchived:
      // The archive family has its own three replies, each carrying what only
      // it can report. A bare success would say the work happened and nothing
      // about what was observed, which is the whole content of an archive.
      return .refused(correlationID: request.correlationID, reason: .malformedRequest)
    }
  }

  /// The reply to an archive made or an archive described. One reply for both,
  /// because the report of making an archive and a description of that archive
  /// are one fact read at two moments, which is what lets a store whose reply
  /// was lost ask again and recover.
  public func archived(
    _ request: HelperRequest,
    report: PrivilegedArchiveReport
  ) -> HelperResponse {
    switch request {
    case .archiveIntoSafetyNet(_, _, let itemID), .describeArchived(_, let itemID):
      return .archived(correlationID: itemID, report: report)
    case .handshake, .remove, .setLaunchItemEnabled, .runMaintenance, .restoreArchived,
      .discardArchived:
      return .refused(correlationID: request.correlationID, reason: .malformedRequest)
    }
  }

  /// The reply to a payload put back. It carries where it went, read from the
  /// payload's own stamp, so the store checks the move against the item it
  /// holds rather than taking it on trust.
  public func restored(
    _ request: HelperRequest,
    to originPath: AbsolutePath
  ) -> HelperResponse {
    guard case .restoreArchived(_, let itemID) = request else {
      return .refused(correlationID: request.correlationID, reason: .malformedRequest)
    }
    return .restoredArchive(correlationID: itemID, originPath: originPath)
  }

  /// The reply to a payload deleted. It carries no byte figure: the purge
  /// total is the sum of sizes recorded at store time, and a second figure
  /// measured here could only disagree with it.
  public func discarded(_ request: HelperRequest) -> HelperResponse {
    guard case .discardArchived(_, let itemID) = request else {
      return .refused(correlationID: request.correlationID, reason: .malformedRequest)
    }
    return .discardedArchive(correlationID: itemID)
  }

  /// The reply to a launch item change that took effect. Any other request
  /// answered with a change is refused rather than answered, because a reply
  /// of the wrong kind is worse than no reply: the app would read it as a
  /// change it never asked for.
  public func changed(
    _ request: HelperRequest,
    to change: LaunchItemChange
  ) -> HelperResponse {
    guard case .setLaunchItemEnabled = request, let correlationID = request.correlationID else {
      return .refused(correlationID: request.correlationID, reason: .malformedRequest)
    }
    return .launchItemChanged(correlationID: correlationID, change: change)
  }

  /// The reply to a request the helper admitted and could not carry out.
  public func failed(_ request: HelperRequest, because reason: String) -> HelperResponse {
    guard let correlationID = request.correlationID else {
      return .refused(correlationID: nil, reason: .malformedRequest)
    }
    return .failed(correlationID: correlationID, reason: reason)
  }

  /// The reply to a request the policy refused. A version disagreement is the
  /// one refusal that names numbers, because the app has to say which side is
  /// behind; every other refusal, a handshake refused on identity included,
  /// names no version at all.
  public func refused(
    _ request: HelperRequest,
    because refusal: HelperRefusal,
    mismatch: HelperVersionMismatch?
  ) -> HelperResponse {
    guard case .handshake = request, refusal == .versionMismatch, let mismatch else {
      return .refused(correlationID: request.correlationID, reason: refusal)
    }
    return .handshakeRefused(
      helperContractVersion: mismatch.helperContractVersion,
      clientContractVersion: mismatch.clientContractVersion
    )
  }
}
