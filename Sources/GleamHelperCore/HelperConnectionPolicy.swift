import Foundation
import GleamCore

/// The helper's gate for one connection.
///
/// A reference type because the handshake is connection state: it is created
/// with the connection, changes once when the versions are compared, and dies
/// with the connection. One instance guards one connection and nothing else.
///
/// Requests are evaluated in the contract's order, and a request failing
/// several stages is refused on the first: identity, then handshake, then
/// domain (resolving a launch item to a file inside that stage), then the
/// denylist. The denylist consulted is the helper's own; a catalogue the
/// helper has not verified itself has no say in it, so a compromised app
/// process cannot make the helper cross it.
public final class HelperConnectionPolicy: HelperPolicy, @unchecked Sendable {
  private enum HandshakeState {
    case pending
    case agreed
    case refused
  }

  private let expectedClient: ExpectedClientIdentity
  private let contractVersion: UInt16
  private let denylist: Denylist
  private let ownership: any PathOwnershipPolicy
  private let environment: OwnershipEnvironment
  private let launchItems: any HelperLaunchItemLocating

  /// Guards the handshake state below, which one connection can reach from
  /// more than one thread.
  private let handshakeLock = NSLock()
  private var handshakeState: HandshakeState = .pending
  private var recordedMismatch: HelperVersionMismatch?

  public init(
    expectedClient: ExpectedClientIdentity,
    contractVersion: UInt16,
    denylist: Denylist,
    ownership: any PathOwnershipPolicy,
    environment: OwnershipEnvironment,
    launchItems: any HelperLaunchItemLocating
  ) {
    self.expectedClient = expectedClient
    self.contractVersion = contractVersion
    self.denylist = denylist
    self.ownership = ownership
    self.environment = environment
    self.launchItems = launchItems
  }

  /// The version disagreement recorded for this connection, if there was one.
  /// Helper side diagnostics: the app learns the numbers from the handshake
  /// exchange, never from this.
  public var versionMismatch: HelperVersionMismatch? {
    handshakeLock.lock()
    defer { handshakeLock.unlock() }
    return recordedMismatch
  }

  public func admit(_ request: HelperRequest, from client: ClientIdentity) -> HelperAdmission {
    guard isExpected(client) else { return .refused(.identityRejected) }
    if let refusal = versionRefusal(for: request) { return .refused(refusal) }
    if let refusal = targetRefusal(for: request) { return .refused(refusal) }
    return .admitted
  }

  private func isExpected(_ client: ClientIdentity) -> Bool {
    client.codeSigningValid
      && client.teamIdentifier == expectedClient.teamIdentifier
      && client.bundleIdentifier == expectedClient.bundleIdentifier
  }

  /// The handshake stage. A request of any other kind arriving before any
  /// handshake is refused `versionMismatch`, because no version has been
  /// agreed and no agreement is treated exactly as disagreement. A connection
  /// once refused stays refused, so a stale app cannot retry its way in.
  private func versionRefusal(for request: HelperRequest) -> HelperRefusal? {
    handshakeLock.lock()
    defer { handshakeLock.unlock() }
    guard handshakeState != .refused else { return .versionMismatch }
    guard case .handshake(let claimedVersion) = request else {
      return handshakeState == .agreed ? nil : .versionMismatch
    }
    guard claimedVersion == contractVersion else {
      handshakeState = .refused
      recordedMismatch = HelperVersionMismatch(
        helperContractVersion: contractVersion,
        clientContractVersion: claimedVersion
      )
      return .versionMismatch
    }
    handshakeState = .agreed
    return nil
  }

  /// The domain stage and the denylist stage. A launch item is resolved to
  /// the file it would mutate first, because the helper cannot place a file
  /// in a domain until it knows which file it is, and it refuses rather than
  /// guessing when it cannot find one.
  private func targetRefusal(for request: HelperRequest) -> HelperRefusal? {
    switch request {
    case .handshake, .runMaintenance:
      return nil
    case .remove(let target, _, _, _):
      return refusal(forTarget: target)
    case .setLaunchItemEnabled(let item, _, _):
      guard let location = launchItems.location(of: item) else { return .malformedRequest }
      return refusal(forTarget: location)
    }
  }

  private func refusal(forTarget target: AbsolutePath) -> HelperRefusal? {
    guard ownership.ownership(of: target, environment: environment) == .systemDomain else {
      return .notSystemDomain
    }
    guard !denylist.blocks(target) else { return .denylisted }
    return nil
  }
}
