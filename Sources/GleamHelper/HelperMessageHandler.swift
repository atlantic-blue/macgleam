import Foundation
import GleamCore
import GleamHelperCore
import os

/// One connection's message loop: decode the bytes, put the request to the
/// connection's policy, and run only what the policy admits.
///
/// Nothing is acted on before C31 has seen it, and the policy holds this
/// connection's handshake state, so a connection that never handshook, or that
/// was once refused, cannot reach the work below however many requests it
/// sends.
///
/// Unchecked rather than checked Sendable because it inherits `NSObject`, not
/// because anything here is shared mutably: every stored property below is a
/// constant, and the one piece of mutable state on a connection, the agreed
/// version, lives inside the policy behind the policy's own lock.
final class HelperMessageHandler: NSObject, GleamHelperXPC, @unchecked Sendable {
  private let policy: HelperConnectionPolicy
  private let client: ClientIdentity
  private let removal: HelperRemoval
  private let codec = HelperWireCodec()
  private let replies = HelperReplyRouter()
  private let now: @Sendable () -> Date
  private let log = Logger(subsystem: GleamHelperService.label, category: "requests")

  init(
    policy: HelperConnectionPolicy,
    client: ClientIdentity,
    removal: HelperRemoval,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.policy = policy
    self.client = client
    self.removal = removal
    self.now = now
  }

  func handle(_ payload: Data, withReply reply: @escaping @Sendable (Data) -> Void) {
    guard let request = try? codec.decodeRequest(from: payload) else {
      log.error("A request that is not a contract message arrived and was refused.")
      answer(.refused(correlationID: nil, reason: .malformedRequest), with: reply)
      return
    }
    switch policy.admit(request, from: client) {
    case .refused(let refusal):
      log.notice("Refused a request: \(refusal.rawValue, privacy: .public).")
      answer(response(to: request, refusing: refusal), with: reply)
    case .admitted:
      Task { [self] in answer(await perform(request), with: reply) }
    }
  }

  // MARK: - Refusals

  private func response(to request: HelperRequest, refusing refusal: HelperRefusal)
    -> HelperResponse
  {
    replies.refused(request, because: refusal, mismatch: policy.versionMismatch)
  }

  // MARK: - Work

  private func perform(_ request: HelperRequest) async -> HelperResponse {
    switch request {
    case .handshake:
      return replies.completed(request, bytesReclaimed: 0)
    case .remove(let target, let destination, _, _):
      return await performRemoval(target, destination, request)
    case .setLaunchItemEnabled(let item, let enabled, _):
      return performLaunchItemChange(item, enabled, request)
    case .runMaintenance(let task, _, _):
      return performMaintenance(task, request)
    }
  }

  private func performRemoval(
    _ target: AbsolutePath,
    _ destination: HelperRemovalDestination,
    _ request: HelperRequest
  ) async -> HelperResponse {
    do {
      let bytesReclaimed = try await removal.remove(target, to: destination)
      log.info("Removed an admitted target of \(bytesReclaimed) bytes.")
      return replies.completed(request, bytesReclaimed: bytesReclaimed)
    } catch {
      return replies.failed(request, because: Self.sentence(for: error))
    }
  }

  private func performLaunchItemChange(
    _ item: LaunchItemID,
    _ enabled: Bool,
    _ request: HelperRequest
  ) -> HelperResponse {
    do {
      let change = try HelperLaunchItems.setEnabled(enabled, item: item, now: now())
      return replies.changed(request, to: change)
    } catch {
      return replies.failed(request, because: Self.sentence(for: error))
    }
  }

  private func performMaintenance(
    _ task: MaintenanceTask,
    _ request: HelperRequest
  ) -> HelperResponse {
    do {
      try HelperMaintenance.run(task)
      return replies.completed(request, bytesReclaimed: 0)
    } catch {
      return replies.failed(request, because: Self.sentence(for: error))
    }
  }

  // MARK: - Bytes

  /// A reply that cannot be encoded is answered with no bytes at all, which
  /// the client reads as an empty reply and fails that one operation on. There
  /// is nothing truthful left to send at that point, and sending a plausible
  /// looking substitute would be worse than silence.
  private func answer(_ response: HelperResponse, with reply: @Sendable (Data) -> Void) {
    guard let payload = try? codec.encode(response) else {
      log.error("A reply could not be encoded, so the request was answered with nothing.")
      reply(Data())
      return
    }
    reply(payload)
  }

  private static func sentence(for error: any Error) -> String {
    let description = error.localizedDescription
    guard description.isEmpty else { return description }
    return "The privileged helper could not complete this, for an unknown reason."
  }
}
