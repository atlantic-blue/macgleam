import Foundation
import GleamHelperClient

/// Says where the privileged helper stands, and lets the registration be
/// driven by hand, without a window.
///
/// It exists because the registration path is the one part of the helper story
/// no automated test can reach: `SMAppService` answers about the real system,
/// registration only completes when a human approves it in System Settings,
/// and a service can only be registered by the app bundle that carries it. So
/// checking the assembled bundle means asking the app itself.
///
///     MacGleam --helper status
///     MacGleam --helper register
///     MacGleam --helper unregister
enum HelperDiagnostics {
  enum Request: String {
    case status
    case register
    case unregister
  }

  static func request(from arguments: [String]) -> Request? {
    guard let flag = arguments.firstIndex(of: "--helper"), flag + 1 < arguments.count else {
      return nil
    }
    return Request(rawValue: arguments[flag + 1])
  }

  /// Runs the request and returns what to print. Reading the status registers
  /// nothing, which is the property worth being able to check by hand.
  static func run(_ request: Request) async -> String {
    let service = SystemHelperService()
    switch request {
    case .status:
      let coordinator = HelperRegistrationCoordinator(service: service)
      return "status: \(service.status.rawValue)\nstate: \(describe(await coordinator.state))"
    case .register:
      let coordinator = HelperRegistrationCoordinator(service: service)
      let state = await coordinator.ensureRegistered()
      return "state: \(describe(state))\nstatus: \(service.status.rawValue)"
    case .unregister:
      do {
        try service.unregister()
      } catch {
        return "unregistering failed: \(error.localizedDescription)"
      }
      return "unregistered\nstatus: \(service.status.rawValue)"
    }
  }

  private static func describe(_ state: HelperRegistrationState) -> String {
    switch state {
    case .notRequested:
      return "notRequested"
    case .awaitingApproval:
      return "awaitingApproval"
    case .enabled:
      return "enabled"
    case .unavailable(let reason):
      return "unavailable: \(reason)"
    }
  }
}
