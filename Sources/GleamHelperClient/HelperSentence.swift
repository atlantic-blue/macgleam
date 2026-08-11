import Foundation
import GleamCore
import GleamHelperCore

/// Every sentence the helper client reports a failure with.
///
/// They are gathered here because they are the whole user facing surface of a
/// process the user never sees, and because each one has the same job: say
/// what stopped, and say what was and was not done to the item named. None of
/// them mention XPC, a domain, an error code or a status, which are the app's
/// problem rather than the reader's.
enum HelperSentence {
  static let registrationNotRequested =
    "MacGleam has not asked macOS to register its privileged helper yet, so system items "
    + "cannot be changed."

  static let requestNotEncodable =
    "MacGleam could not put this request into a form the privileged helper reads."

  static let emptyReply =
    "The privileged helper answered with nothing."

  static let undecodableReply =
    "The privileged helper's answer was not a message MacGleam understands."

  static let unusableHandshakeReply =
    "The privileged helper answered the version check with something other than a version, "
    + "so MacGleam will not send it any work."

  static func awaitingApproval(_ operation: GleamCore.Operation) -> String {
    joined(
      "MacGleam's privileged helper is waiting for approval. Open System Settings, then "
        + "General, then Login Items and Extensions, and approve MacGleam.",
      operation)
  }

  static func unavailable(_ reason: String, _ operation: GleamCore.Operation) -> String {
    joined(reason, operation)
  }

  static func transportFailed(_ error: any Error) -> String {
    let detail = error.localizedDescription
    let ending = detail.isEmpty ? "." : ": \(detail)"
    return "MacGleam could not reach its privileged helper\(ending)"
  }

  static func versionDisagreement(_ verdict: HelperVersionVerdict) -> String {
    switch verdict {
    case .helperIsBehind:
      return
        "MacGleam's privileged helper is an older version than MacGleam and refused the "
        + "version check. Reinstalling MacGleam replaces the helper with a matching one."
    case .appIsBehind:
      return
        "MacGleam is an older version than its privileged helper and the helper refused the "
        + "version check. Updating MacGleam brings the two back into step."
    case .agreed:
      return "The privileged helper refused the version check."
    }
  }

  static func handshakeRefused(_ refusal: HelperRefusal) -> String {
    switch refusal {
    case .identityRejected:
      return
        "MacGleam's privileged helper could not confirm that this copy of MacGleam is the one "
        + "it was installed for, so it will not do privileged work for it."
    case .versionMismatch:
      return
        "MacGleam's privileged helper would not agree a version on this connection, so "
        + "MacGleam will not send it any work."
    case .denylisted, .notSystemDomain, .malformedRequest:
      return
        "MacGleam's privileged helper refused the version check, so MacGleam will not send "
        + "it any work."
    }
  }

  static func replyNamesAnotherOperation(_ operation: GleamCore.Operation) -> String {
    joined(
      "The privileged helper answered about something other than what MacGleam asked for.",
      operation)
  }

  static func replyOfTheWrongKind(_ operation: GleamCore.Operation) -> String {
    joined(
      "The privileged helper's answer was not the kind of answer this request has.",
      operation)
  }

  static func refused(_ refusal: HelperRefusal, _ operation: GleamCore.Operation) -> String {
    joined(refusalCause(refusal), operation)
  }

  static func helperFailed(_ reason: String, _ operation: GleamCore.Operation) -> String {
    let cause = reason.isEmpty ? "The privileged helper could not complete this." : reason
    return joined(cause, operation)
  }

  /// A cause, then what became of the item because of it. Both halves matter:
  /// the first says why, and the second is the part the result screen needs.
  static func joined(_ cause: String, _ operation: GleamCore.Operation) -> String {
    "\(cause) \(outcome(of: operation))."
  }

  /// For the failures that happen after a request has left: the reply was
  /// empty, or unreadable, or never came. The helper may have done the work
  /// before the answer was lost, so the item is named without a claim about
  /// what became of it. Saying it was left untouched would be the more
  /// comfortable sentence and might not be true.
  static func uncertain(_ cause: String, _ operation: GleamCore.Operation) -> String {
    "\(cause) MacGleam cannot say whether \(subject(of: operation)) was changed."
  }

  private static func refusalCause(_ refusal: HelperRefusal) -> String {
    switch refusal {
    case .denylisted:
      return "The privileged helper's own denylist blocks this item."
    case .notSystemDomain:
      return
        "The privileged helper refused this because it is not a system item, and the helper "
        + "does no work MacGleam can do itself."
    case .versionMismatch:
      return "MacGleam and its privileged helper have not agreed a version on this connection."
    case .identityRejected:
      return
        "MacGleam's privileged helper could not confirm that this copy of MacGleam is the one "
        + "it was installed for."
    case .malformedRequest:
      return "MacGleam's privileged helper could not make sense of the request."
    }
  }

  /// What became of the operation's item, in the same words the user process
  /// uses for the same kinds, so a report never reads as two products.
  private static func outcome(of operation: GleamCore.Operation) -> String {
    switch operation.kind {
    case .moveToTrash, .deletePermanently, .quarantine, .archive:
      return "\(subject(of: operation)) was left untouched"
    case .setLaunchItemEnabled:
      return "\(subject(of: operation)) was left unchanged"
    case .runMaintenance:
      return "\(subject(of: operation)) was not run"
    }
  }

  /// The thing the operation is about, named the way the user reviewed it.
  private static func subject(of operation: GleamCore.Operation) -> String {
    switch operation.kind {
    case .moveToTrash(let target), .deletePermanently(let target), .quarantine(let target),
      .archive(let target, _):
      return target.value
    case .setLaunchItemEnabled(let item, _):
      return item.value
    case .runMaintenance(let task):
      return task.rawValue
    }
  }
}
