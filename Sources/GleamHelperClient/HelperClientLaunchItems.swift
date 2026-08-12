import Foundation
import GleamCore
import GleamHelperCore

/// The app's only way to change a system scope login item: C24's privileged
/// side, carried over C30's wire.
///
/// It exists as its own entry point rather than as another plan operation
/// because a person flipping a switch is not running a plan. Both kinds arrive
/// here as a `ChangeAttribution`, which is what the request carries and what
/// the reply echoes, so a refusal reconciles to the operation or to the direct
/// change that caused it without either side inferring anything.
extension HelperClient: PrivilegedLaunchItemChanging {

  public func setLaunchItemEnabled(
    _ enabled: Bool,
    item: LaunchItemID,
    attribution: ChangeAttribution
  ) async throws -> LaunchItemChange {
    let operation = Self.operation(for: item, enabled: enabled, attribution: attribution)
    if let reason = await registrationRefusal(for: operation) {
      throw PrivilegedLaunchItemFailure.refused(reason: reason)
    }
    if let reason = await handshakeRefusal(for: operation) {
      throw PrivilegedLaunchItemFailure.refused(reason: reason)
    }
    let request = HelperRequest.setLaunchItemEnabled(
      item: item, enabled: enabled, attribution: attribution)
    switch await exchange(request) {
    case .notSent(let reason):
      throw PrivilegedLaunchItemFailure.refused(
        reason: HelperSentence.joined(reason, operation))
    case .unanswered(let reason):
      throw PrivilegedLaunchItemFailure.refused(
        reason: HelperSentence.uncertain(reason, operation))
    case .reply(let reply):
      return try Self.change(from: reply, for: operation, attribution: attribution)
    }
  }

  /// The reply, checked before a word of it is believed: it must echo this
  /// change's own correlation identifier and be the kind of answer this
  /// request has.
  private static func change(
    from reply: HelperResponse,
    for operation: GleamCore.Operation,
    attribution: ChangeAttribution
  ) throws -> LaunchItemChange {
    guard reply.correlationID == attribution.correlationID else {
      throw PrivilegedLaunchItemFailure.refused(
        reason: HelperSentence.replyNamesAnotherOperation(operation))
    }
    switch reply {
    case .launchItemChanged(_, let change):
      return change
    case .refused(_, .malformedRequest):
      // The helper refuses a launch item it cannot resolve as malformed
      // (C31). To the person reading the row, that is the item being gone.
      throw PrivilegedLaunchItemFailure.itemUnresolvable
    case .refused(_, let refusal):
      throw PrivilegedLaunchItemFailure.refused(
        reason: HelperSentence.refused(refusal, operation))
    case .failed(_, let reason):
      throw PrivilegedLaunchItemFailure.refused(
        reason: HelperSentence.helperFailed(reason, operation))
    case .success, .handshakeAccepted, .handshakeRefused:
      throw PrivilegedLaunchItemFailure.refused(
        reason: HelperSentence.replyOfTheWrongKind(operation))
    }
  }

  /// The change as an operation, for the sentences alone. Its identifier is
  /// the attribution's, so nothing here mints a second identity for the same
  /// change, and it reaches no plan and no `ExecutionReport`.
  private static func operation(
    for item: LaunchItemID,
    enabled: Bool,
    attribution: ChangeAttribution
  ) -> GleamCore.Operation {
    GleamCore.Operation(
      id: attribution.correlationID,
      findingID: attribution.correlationID,
      kind: .setLaunchItemEnabled(item: item, enabled: enabled),
      privilege: .root
    )
  }
}
