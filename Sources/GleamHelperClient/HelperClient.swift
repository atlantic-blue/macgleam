import Foundation
import GleamCore
import GleamHelperCore

/// Which side of the version handshake is the old one. The handshake exchange
/// carries both numbers by construction, so a disagreement is never a bare
/// mismatch: the app says which side is behind and prompts to update that one.
public enum HelperVersionVerdict: Sendable, Equatable {
  /// The version now in force, which is the helper's own and, by the
  /// agreement, the app's too.
  case agreed(version: UInt16)
  case helperIsBehind(helperVersion: UInt16, appVersion: UInt16)
  case appIsBehind(helperVersion: UInt16, appVersion: UInt16)
}

/// The app's side of the privileged boundary: it turns one operation into one
/// C30 request, sends the bytes, and validates what comes back before it
/// believes a word of it.
///
/// Three things happen before any bytes leave, in this order. The helper must
/// be registered and approved, so an unapproved helper never has an operation
/// sent at it. The connection must have agreed a contract version, so the
/// handshake is always the first message on a connection, is reused once
/// agreed, and is never asked again on a connection the helper refused. Only
/// then is the operation transmitted.
///
/// Nothing here ends the run. Every failure, refusal, nonsense reply and dead
/// transport is the result of the one operation it happened to, and the client
/// keeps serving the next one.
public actor HelperClient: PrivilegedOperationPerforming {
  private enum HandshakeState {
    case pending
    case agreed
    case refused(reason: String)
  }

  enum Exchange {
    case reply(HelperResponse)
    /// Failed before any bytes left, so the target is certainly untouched.
    case notSent(reason: String)
    /// The bytes left and no answer MacGleam can read came back, so what the
    /// helper did or did not do is genuinely unknown.
    case unanswered(reason: String)
  }

  private enum PositiveReply {
    case success
    case launchItemChange
  }

  private let transport: any HelperTransporting
  private let registration: HelperRegistrationCoordinator
  private let userHome: AbsolutePath
  private let safetyNetStoreDirectory: AbsolutePath
  private let contractVersion: UInt16
  private let codec = HelperWireCodec()

  private var handshake: HandshakeState = .pending
  private var handshakeInFlight: Task<String?, Never>?
  private var verdict: HelperVersionVerdict?

  public init(
    transport: any HelperTransporting,
    registration: HelperRegistrationCoordinator,
    userHome: AbsolutePath,
    safetyNetStoreDirectory: AbsolutePath,
    contractVersion: UInt16 = HelperContract.version
  ) {
    self.transport = transport
    self.registration = registration
    self.userHome = userHome
    self.safetyNetStoreDirectory = safetyNetStoreDirectory
    self.contractVersion = contractVersion
  }

  /// What the handshake settled, and nil while no handshake has been answered
  /// on this connection.
  public var versionVerdict: HelperVersionVerdict? {
    verdict
  }

  public func perform(_ operation: GleamCore.Operation, planID: UUID) async -> OperationResult {
    if let reason = await registrationRefusal(for: operation) {
      return .failed(reason: reason)
    }
    if let reason = await handshakeRefusal(for: operation) {
      return .failed(reason: reason)
    }
    return await transmit(operation, planID: planID)
  }

  // MARK: - Registration

  /// Read before every privileged operation, never once at launch: approval
  /// can land or be withdrawn between two operations of the same plan.
  func registrationRefusal(for operation: GleamCore.Operation) async -> String? {
    switch await registration.ensureRegistered() {
    case .enabled:
      return nil
    case .awaitingApproval:
      return HelperSentence.awaitingApproval(operation)
    case .unavailable(let reason):
      return HelperSentence.unavailable(reason, operation)
    case .notRequested:
      return HelperSentence.unavailable(HelperSentence.registrationNotRequested, operation)
    }
  }

  // MARK: - Handshake

  func handshakeRefusal(for operation: GleamCore.Operation) async -> String? {
    switch handshake {
    case .agreed:
      return nil
    case .refused(let reason):
      return HelperSentence.joined(reason, operation)
    case .pending:
      break
    }
    if let inFlight = handshakeInFlight {
      guard let reason = await inFlight.value else { return nil }
      return HelperSentence.joined(reason, operation)
    }
    let exchange = Task { await self.exchangeHandshake() }
    handshakeInFlight = exchange
    let reason = await exchange.value
    handshakeInFlight = nil
    guard let reason else { return nil }
    return HelperSentence.joined(reason, operation)
  }

  /// Sends the handshake and records what it settled. Returns nil when the
  /// versions agreed, and the reason the connection is unusable otherwise.
  private func exchangeHandshake() async -> String? {
    switch await exchange(.handshake(contractVersion: contractVersion)) {
    case .notSent(let reason), .unanswered(let reason):
      return reason
    case .reply(.handshakeAccepted(let version)) where version == contractVersion:
      handshake = .agreed
      verdict = .agreed(version: version)
      return nil
    case .reply(.handshakeRefused(let helperVersion, let appVersion))
    where helperVersion != appVersion:
      let behind =
        helperVersion < appVersion
        ? HelperVersionVerdict.helperIsBehind(helperVersion: helperVersion, appVersion: appVersion)
        : HelperVersionVerdict.appIsBehind(helperVersion: helperVersion, appVersion: appVersion)
      verdict = behind
      let reason = HelperSentence.versionDisagreement(behind)
      handshake = .refused(reason: reason)
      return reason
    case .reply(.refused(_, let refusal)):
      let reason = HelperSentence.handshakeRefused(refusal)
      handshake = .refused(reason: reason)
      return reason
    case .reply:
      return HelperSentence.unusableHandshakeReply
    }
  }

  // MARK: - Operations

  private func transmit(_ operation: GleamCore.Operation, planID: UUID) async -> OperationResult {
    switch await exchange(request(for: operation, planID: planID)) {
    case .notSent(let reason):
      return .failed(reason: HelperSentence.joined(reason, operation))
    case .unanswered(let reason):
      return .failed(reason: HelperSentence.uncertain(reason, operation))
    case .reply(let reply):
      return result(of: reply, for: operation)
    }
  }

  private func request(for operation: GleamCore.Operation, planID: UUID) -> HelperRequest {
    switch operation.kind {
    case .moveToTrash(let target):
      return removal(of: target, to: .userTrash(userHome: userHome), operation, planID)
    case .deletePermanently(let target):
      return removal(of: target, to: .permanent, operation, planID)
    case .quarantine(let target), .archive(let target, _):
      let store = HelperRemovalDestination.safetyNetStore(storeDirectory: safetyNetStoreDirectory)
      return removal(of: target, to: store, operation, planID)
    case .setLaunchItemEnabled(let item, let enabled):
      return .setLaunchItemEnabled(
        item: item,
        enabled: enabled,
        attribution: .operation(planID: planID, operationID: operation.id))
    case .runMaintenance(let task):
      return .runMaintenance(task: task, planID: planID, operationID: operation.id)
    }
  }

  private func removal(
    of target: AbsolutePath,
    to destination: HelperRemovalDestination,
    _ operation: GleamCore.Operation,
    _ planID: UUID
  ) -> HelperRequest {
    .remove(
      target: target, destination: destination, planID: planID, operationID: operation.id)
  }

  // MARK: - Reply validation

  /// Nothing that arrives is taken at face value. A reply must name this
  /// operation and be the kind of answer this request has, or the operation
  /// fails and the run continues.
  private func result(of reply: HelperResponse, for operation: GleamCore.Operation)
    -> OperationResult
  {
    guard reply.correlationID == operation.id else {
      return .failed(reason: HelperSentence.replyNamesAnotherOperation(operation))
    }
    switch reply {
    case .success(_, let bytesReclaimed):
      guard Self.positiveReply(for: operation) == .success else {
        return .failed(reason: HelperSentence.replyOfTheWrongKind(operation))
      }
      return .completed(bytesReclaimed: bytesReclaimed)
    case .launchItemChanged:
      guard Self.positiveReply(for: operation) == .launchItemChange else {
        return .failed(reason: HelperSentence.replyOfTheWrongKind(operation))
      }
      return .completed(bytesReclaimed: 0)
    case .refused(_, let refusal):
      guard refusal != .denylisted else { return .skippedDenylisted }
      return .failed(reason: HelperSentence.refused(refusal, operation))
    case .failed(_, let reason):
      return .failed(reason: HelperSentence.helperFailed(reason, operation))
    case .handshakeAccepted, .handshakeRefused:
      return .failed(reason: HelperSentence.replyOfTheWrongKind(operation))
    }
  }

  private static func positiveReply(for operation: GleamCore.Operation) -> PositiveReply {
    switch operation.kind {
    case .moveToTrash, .deletePermanently, .quarantine, .archive, .runMaintenance:
      return .success
    case .setLaunchItemEnabled:
      return .launchItemChange
    }
  }

  // MARK: - Bytes

  func exchange(_ request: HelperRequest) async -> Exchange {
    let payload: Data
    do {
      payload = try codec.encode(request)
    } catch {
      return .notSent(reason: HelperSentence.requestNotEncodable)
    }
    let replyBytes: Data
    do {
      replyBytes = try await transport.send(payload)
    } catch {
      return .unanswered(reason: HelperSentence.transportFailed(error))
    }
    guard !replyBytes.isEmpty else { return .unanswered(reason: HelperSentence.emptyReply) }
    do {
      return .reply(try codec.decodeResponse(from: replyBytes))
    } catch {
      return .unanswered(reason: HelperSentence.undecodableReply)
    }
  }
}

extension HelperResponse {
  /// The request a reply answers, and nil for the two handshake replies and
  /// for a refusal that named none.
  var correlationID: UUID? {
    switch self {
    case .handshakeAccepted, .handshakeRefused:
      return nil
    case .success(let correlationID, _), .launchItemChanged(let correlationID, _),
      .failed(let correlationID, _):
      return correlationID
    case .refused(let correlationID, _):
      return correlationID
    }
  }
}
