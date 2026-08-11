import Foundation

/// The privileged service as the app can see it: a status it can read and a
/// registration it can ask for. `SMAppService` shaped, so the adapter over the
/// real service is a pass through and everything worth testing sits above this
/// line rather than behind Apple's.
public protocol HelperServiceRegistering: Sendable {
  /// Read, never a request. Nothing about reading this registers anything.
  var status: HelperServiceStatus { get }
  func register() throws
}

/// Where the privileged service stands with the system.
public enum HelperServiceStatus: String, Sendable, Equatable, CaseIterable {
  /// Known to the system and never registered, or registered and then removed.
  case notRegistered
  /// Approved and running on demand. The only status that may be talked to.
  case enabled
  /// Registered, and waiting for a human to enable it in System Settings.
  case requiresApproval
  /// The system cannot find the service: no property list in the bundle, or a
  /// bundle it will not read.
  case notFound
}

/// What the app should do about the helper, which is not the same as what the
/// system's status says. `awaitingApproval` is the whole reason this type
/// exists: a first registration that throws while the status turns to
/// `requiresApproval` is the normal path, and reporting it as a failure would
/// tell the user the app is broken at the moment it is working.
public enum HelperRegistrationState: Sendable, Equatable {
  case notRequested
  case awaitingApproval
  case enabled
  case unavailable(reason: String)
}
