import Foundation
import GleamHelperCore
import os

/// The real connection to the daemon: one XPC (inter process communication)
/// connection, made on the first message and held for the life of this
/// transport, so a transport is a connection and the client's handshake state
/// describes exactly one of them.
///
/// The connection is never silently remade. A remade connection would be a
/// fresh one to the daemon, which by C31 demands a handshake before anything
/// else, while the client still believed a version had been agreed; every
/// request after that would be refused for a reason nobody could act on. So an
/// ended connection is reported as one, and the next plan gets a new transport
/// and a new handshake.
public actor XPCHelperTransport: HelperTransporting {
  public enum TransportError: Error, LocalizedError, Equatable {
    case connectionEnded
    case helperDidNotAnswer(String)

    public var errorDescription: String? {
      switch self {
      case .connectionEnded:
        return "the connection to the privileged helper ended"
      case .helperDidNotAnswer(let detail):
        return detail
      }
    }
  }

  private let machServiceName: String
  private var connection: NSXPCConnection?
  private var hasEnded = false

  public init(machServiceName: String = GleamHelperService.machServiceName) {
    self.machServiceName = machServiceName
  }

  public func send(_ payload: Data) async throws -> Data {
    guard !hasEnded else { throw TransportError.connectionEnded }
    let connection = openConnection()
    return try await withCheckedThrowingContinuation { continuation in
      let answer = OnceOnly(continuation)
      let proxy = connection.remoteObjectProxyWithErrorHandler { error in
        answer.fail(TransportError.helperDidNotAnswer(error.localizedDescription))
      }
      guard let helper = proxy as? GleamHelperXPC else {
        answer.fail(TransportError.helperDidNotAnswer("the helper offered no interface"))
        return
      }
      helper.handle(payload) { reply in answer.succeed(reply) }
    }
  }

  /// Ends the connection. The daemon drops the connection's agreed version
  /// with it, which is the point: a plan's connection outlives no plan.
  public func close() {
    hasEnded = true
    connection?.invalidate()
    connection = nil
  }

  private func openConnection() -> NSXPCConnection {
    if let connection { return connection }
    let opened = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
    opened.remoteObjectInterface = NSXPCInterface(with: GleamHelperXPC.self)
    opened.invalidationHandler = { [weak self] in
      guard let self else { return }
      Task { await self.markEnded() }
    }
    opened.resume()
    connection = opened
    return opened
  }

  private func markEnded() {
    hasEnded = true
    connection = nil
  }
}

/// Resumes a continuation exactly once.
///
/// An XPC exchange has two ways to finish, the reply and the error handler,
/// and on an interrupted connection both can fire. Resuming a continuation
/// twice is a crash, so which one arrived first is the only thing that decides
/// the answer.
private final class OnceOnly: Sendable {
  private let continuation: CheckedContinuation<Data, any Error>
  private let hasAnswered = OSAllocatedUnfairLock(initialState: false)

  init(_ continuation: CheckedContinuation<Data, any Error>) {
    self.continuation = continuation
  }

  func succeed(_ payload: Data) {
    guard claim() else { return }
    continuation.resume(returning: payload)
  }

  func fail(_ error: any Error) {
    guard claim() else { return }
    continuation.resume(throwing: error)
  }

  private func claim() -> Bool {
    hasAnswered.withLock { answered in
      guard !answered else { return false }
      answered = true
      return true
    }
  }
}
