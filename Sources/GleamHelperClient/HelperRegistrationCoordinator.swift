import Foundation

/// Decides when the privileged service is asked for, and what its answers
/// mean.
///
/// Nothing here runs at launch. `ensureRegistered` is called by the first
/// operation that genuinely needs privilege, so a user who never touches a
/// system path is never asked to approve anything, and reading `state` is a
/// read: it reports where the service stands and registers nothing.
///
/// Registration is asked for at most once for the life of a coordinator, even
/// when several operations arrive together, because a second request cannot
/// make a human approve any faster. The status is read afresh every time
/// though, by both `state` and `ensureRegistered`, so an approval that lands
/// minutes later is seen without the app being restarted, and one withdrawn
/// again stops reading as enabled.
public actor HelperRegistrationCoordinator {
  private let service: any HelperServiceRegistering
  private var registrationOutcome: HelperRegistrationState = .notRequested
  private var hasRequestedRegistration = false

  public init(service: any HelperServiceRegistering) {
    self.service = service
  }

  /// Where the helper stands right now. A read, never a request.
  public var state: HelperRegistrationState {
    approvalState(of: service.status) ?? registrationOutcome
  }

  /// The state to act on for the operation about to run, registering first if
  /// that has not been asked for yet.
  @discardableResult
  public func ensureRegistered() -> HelperRegistrationState {
    if let settled = approvalState(of: service.status) { return settled }
    registrationOutcome = requestRegistration()
    return registrationOutcome
  }

  /// What a status settles on its own. The other two settle nothing: a service
  /// that is not registered, and one the system cannot find, both describe a
  /// world where nothing has been asked for yet, and what they mean depends on
  /// whether this app has since asked.
  private func approvalState(of status: HelperServiceStatus) -> HelperRegistrationState? {
    switch status {
    case .enabled:
      return .enabled
    case .requiresApproval:
      return .awaitingApproval
    case .notRegistered, .notFound:
      return nil
    }
  }

  /// Registration is asked for from both unsettled statuses, including the one
  /// that reads as the system not finding the service. Observed on macOS 15: a
  /// daemon carried inside the app reads `notFound` until it has been
  /// registered once, because the answer comes from the background task
  /// manager's records rather than from the property list, and there is no
  /// record until the first registration. Treating that status as a dead end
  /// would mean never registering at all.
  private func requestRegistration() -> HelperRegistrationState {
    guard !hasRequestedRegistration else { return registrationOutcome }
    hasRequestedRegistration = true
    do {
      try service.register()
    } catch {
      return stateAfterRegistrationThrew(error)
    }
    return approvalState(of: service.status) ?? unavailableAfterRequest()
  }

  private func unavailableAfterRequest() -> HelperRegistrationState {
    guard service.status == .notFound else {
      return .unavailable(reason: Self.stillNotRegisteredSentence)
    }
    return .unavailable(reason: Self.notFoundSentence)
  }

  /// A throw is not a verdict on its own, and the status after the attempt is.
  /// A service reporting `requiresApproval` is waiting for a human whatever was
  /// thrown to get there, because the only useful thing to tell someone in that
  /// state is to approve the item in System Settings. Any other status leaves
  /// the throw as the failure it reads like, so an error on its own can never
  /// produce an approval state.
  private func stateAfterRegistrationThrew(_ error: any Error) -> HelperRegistrationState {
    guard service.status == .requiresApproval else {
      return .unavailable(reason: Self.registrationFailedSentence(error as NSError))
    }
    return .awaitingApproval
  }

  private static let notFoundSentence =
    "macOS cannot find MacGleam's privileged helper, so system items cannot be changed. "
    + "Reinstalling MacGleam replaces it."

  private static let stillNotRegisteredSentence =
    "MacGleam asked macOS to register its privileged helper and the helper is still not "
    + "registered, so system items cannot be changed."

  private static func registrationFailedSentence(_ failure: NSError) -> String {
    let detail = failure.localizedDescription
    let ending = detail.isEmpty ? "." : ": \(detail)"
    return
      "MacGleam could not register its privileged helper, so system items cannot be changed"
      + ending
  }
}
