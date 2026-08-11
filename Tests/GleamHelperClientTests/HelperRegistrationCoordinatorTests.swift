import Foundation
import GleamCore
import GleamHelperClient
import Testing

/// The app's side of getting a privileged helper installed, expressed as what
/// the app should do rather than as what the framework returned.
///
/// One empirical fact drives most of this file. On a first registration the
/// system service throws SMAppServiceErrorDomain code 1, "Operation not
/// permitted", while its status becomes `requiresApproval`, and it stays there
/// until a human enables the item in System Settings. That throw is the normal
/// path, not a failure, and a coordinator that reports it as a failure tells
/// the user the helper is broken when it is merely waiting for them. A real
/// Developer ID certificate behaves the same way, so the certificate is not a
/// factor and no test here depends on one.
///
/// That observation is a record of one case, not the rule. The rule is that the
/// status after the attempt decides: a service reporting `requiresApproval` is
/// awaiting approval whatever it threw on the way, because the only useful
/// thing to tell a person there is to approve the item in System Settings.
/// Matching a domain and a code exactly would read an unrecognised error over a
/// pending approval and send the user looking for a fault that does not exist.
///
/// The other half is restraint: nothing registers at launch. Registration
/// prompts the user, and prompting a user who has not yet asked for anything
/// privileged is how an app teaches people to click through its dialogs.
@Suite("Helper registration coordinator")
struct HelperRegistrationCoordinatorTests {

  // MARK: Nothing happens until something privileged needs it

  @Test("constructing the coordinator registers nothing")
  func constructionRegistersNothing() async throws {
    let service = FakeHelperService(status: .notRegistered)

    _ = makeRegistrationCoordinator(service: service)

    #expect(service.registerCallCount == 0)
  }

  @Test(
    "reading the state never registers, whatever the service reports",
    arguments: HelperServiceStatus.allCases)
  func readingTheStateNeverRegisters(status: HelperServiceStatus) async throws {
    let service = FakeHelperService(status: status)
    let coordinator = makeRegistrationCoordinator(service: service)

    _ = await coordinator.state
    _ = await coordinator.state

    #expect(service.registerCallCount == 0, "the app must never register at launch")
  }

  @Test("a service that is not registered, before any privileged need, reads as nothing attempted")
  func notRegisteredBeforeAnyNeedReadsAsNothingAttempted() async throws {
    let coordinator = makeRegistrationCoordinator(
      service: FakeHelperService(status: .notRegistered))

    #expect(await coordinator.state == .notRequested)
  }

  @Test("a service the system cannot find, before any privileged need, reads as nothing attempted")
  func notFoundBeforeAnyNeedReadsAsNothingAttempted() async throws {
    let coordinator = makeRegistrationCoordinator(service: FakeHelperService(status: .notFound))

    #expect(
      await coordinator.state == .notRequested,
      "an item nobody has asked for yet is not an item that failed")
  }

  @Test("a helper enabled on a previous run reads as enabled without registering again")
  func enabledFromAPreviousRunReadsAsEnabled() async throws {
    let service = FakeHelperService(status: .enabled)
    let coordinator = makeRegistrationCoordinator(service: service)

    #expect(await coordinator.state == .enabled)
    #expect(service.registerCallCount == 0)
  }

  @Test("a helper left awaiting approval on a previous run reads as awaiting approval")
  func requiresApprovalFromAPreviousRunReadsAsAwaitingApproval() async throws {
    let service = FakeHelperService(status: .requiresApproval)
    let coordinator = makeRegistrationCoordinator(service: service)

    #expect(await coordinator.state == .awaitingApproval)
    #expect(service.registerCallCount == 0)
  }

  // MARK: The first genuinely privileged need

  @Test("the first privileged need registers exactly once")
  func firstPrivilegedNeedRegistersOnce() async throws {
    let service = FakeHelperService(status: .notRegistered)
    let coordinator = makeRegistrationCoordinator(service: service)

    _ = await coordinator.ensureRegistered()

    #expect(service.registerCallCount == 1)
  }

  @Test(
    "the documented first registration throw, paired with requiresApproval, is awaiting approval")
  func documentedFirstRegistrationThrowIsAwaitingApproval() async throws {
    let service = FakeHelperService(
      status: .notRegistered, onRegister: .throwsOperationNotPermittedAndAwaitsApproval)
    let coordinator = makeRegistrationCoordinator(service: service)

    let state = await coordinator.ensureRegistered()

    #expect(
      state == .awaitingApproval,
      "SMAppServiceErrorDomain code 1 beside a requiresApproval status is the normal first registration"
    )
    #expect(await coordinator.state == .awaitingApproval)
  }

  @Test("the same throw with nothing awaiting approval is reported as unavailable")
  func sameThrowWithoutApprovalPendingIsUnavailable() async throws {
    let service = FakeHelperService(
      status: .notRegistered, onRegister: .throwsOperationNotPermittedAndStaysNotRegistered)
    let coordinator = makeRegistrationCoordinator(service: service)

    let state = await coordinator.ensureRegistered()

    guard case .unavailable(let reason) = state else {
      Issue.record("expected unavailable, got \(state)")
      return
    }
    try expectPlainSentence(reason)
  }

  @Test(
    "a different service management error, with nothing awaiting approval, is unavailable in a plain sentence"
  )
  func differentServiceManagementErrorIsUnavailable() async throws {
    let service = FakeHelperService(
      status: .notRegistered,
      onRegister: .throwsError(
        NSError(
          domain: FakeHelperService.serviceManagementErrorDomain, code: 3,
          userInfo: [NSLocalizedDescriptionKey: "Unable to read plist"]),
        leaving: .notRegistered))
    let coordinator = makeRegistrationCoordinator(service: service)

    let state = await coordinator.ensureRegistered()

    guard case .unavailable(let reason) = state else {
      Issue.record("expected unavailable, got \(state)")
      return
    }
    try expectPlainSentence(reason)
  }

  @Test(
    "an error from another domain entirely, with nothing awaiting approval, is unavailable in a plain sentence"
  )
  func errorFromAnotherDomainIsUnavailable() async throws {
    let service = FakeHelperService(
      status: .notRegistered,
      onRegister: .throwsError(
        NSError(domain: NSPOSIXErrorDomain, code: 1, userInfo: nil), leaving: .notRegistered))
    let coordinator = makeRegistrationCoordinator(service: service)

    let state = await coordinator.ensureRegistered()

    guard case .unavailable(let reason) = state else {
      Issue.record("expected unavailable, got \(state)")
      return
    }
    try expectPlainSentence(reason)
  }

  @Test("a registration that returns with the item enabled is enabled")
  func registrationThatSucceedsOutrightIsEnabled() async throws {
    let coordinator = makeRegistrationCoordinator(
      service: FakeHelperService(status: .notRegistered, onRegister: .succeeds(leaving: .enabled)))

    #expect(await coordinator.ensureRegistered() == .enabled)
  }

  @Test("a registration that returns with the item still awaiting approval is awaiting approval")
  func registrationThatReturnsAwaitingApprovalIsAwaitingApproval() async throws {
    let coordinator = makeRegistrationCoordinator(
      service: FakeHelperService(
        status: .notRegistered, onRegister: .succeeds(leaving: .requiresApproval)))

    #expect(await coordinator.ensureRegistered() == .awaitingApproval)
  }

  @Test("a registration that returns with the item missing is unavailable")
  func registrationThatLeavesTheItemMissingIsUnavailable() async throws {
    let coordinator = makeRegistrationCoordinator(
      service: FakeHelperService(status: .notRegistered, onRegister: .succeeds(leaving: .notFound)))

    let state = await coordinator.ensureRegistered()

    guard case .unavailable(let reason) = state else {
      Issue.record("expected unavailable, got \(state)")
      return
    }
    try expectPlainSentence(reason)
  }

  // MARK: The status after the attempt is what decides

  /// The status is authoritative. If the service reports `requiresApproval`
  /// once the attempt is over, the app is awaiting approval whatever was
  /// thrown, because the only useful thing to tell a person at that point is to
  /// approve the item in System Settings. The documented domain and code are a
  /// record of the one case we have observed, not the decision.
  ///
  /// The converse below is what keeps that from being a licence to guess: with
  /// nothing awaiting approval, the documented error on its own must never
  /// manufacture an approval state.

  @Test(
    "a different code in the same service management domain, with approval pending, is awaiting approval"
  )
  func differentCodeWithApprovalPendingIsAwaitingApproval() async throws {
    let service = FakeHelperService(
      status: .notRegistered,
      onRegister: .throwsError(
        NSError(
          domain: FakeHelperService.serviceManagementErrorDomain, code: 3,
          userInfo: [NSLocalizedDescriptionKey: "Unable to read plist"]),
        leaving: .requiresApproval))
    let coordinator = makeRegistrationCoordinator(service: service)

    let state = await coordinator.ensureRegistered()

    #expect(
      state == .awaitingApproval,
      "an item the service reports as requiresApproval is waiting for a human, whatever it threw")
    #expect(await coordinator.state == .awaitingApproval)
  }

  @Test("an error from another domain entirely, with approval pending, is awaiting approval")
  func otherDomainErrorWithApprovalPendingIsAwaitingApproval() async throws {
    let service = FakeHelperService(
      status: .notRegistered,
      onRegister: .throwsError(
        NSError(domain: NSPOSIXErrorDomain, code: 13, userInfo: nil), leaving: .requiresApproval))
    let coordinator = makeRegistrationCoordinator(service: service)

    let state = await coordinator.ensureRegistered()

    #expect(
      state == .awaitingApproval,
      "the status decides, so an unrecognised error does not hide a pending approval")
    #expect(await coordinator.state == .awaitingApproval)
  }

  @Test(
    "the documented error, with nothing awaiting approval, is unavailable in a plain sentence",
    arguments: [HelperServiceStatus.notRegistered, .notFound])
  func documentedErrorWithoutApprovalPendingIsUnavailable(status: HelperServiceStatus) async throws
  {
    let service = FakeHelperService(
      status: .notRegistered,
      onRegister: .throwsError(FakeHelperService.operationNotPermitted, leaving: status))
    let coordinator = makeRegistrationCoordinator(service: service)

    let state = await coordinator.ensureRegistered()

    guard case .unavailable(let reason) = state else {
      Issue.record("a status of \(status) is not approval pending, yet the state was \(state)")
      return
    }
    try expectPlainSentence(reason)
  }

  // MARK: Asking twice does not register twice

  @Test("asking twice does not register twice")
  func askingTwiceDoesNotRegisterTwice() async throws {
    let service = FakeHelperService(status: .notRegistered)
    let coordinator = makeRegistrationCoordinator(service: service)

    let first = await coordinator.ensureRegistered()
    let second = await coordinator.ensureRegistered()

    #expect(first == .awaitingApproval)
    #expect(second == .awaitingApproval)
    #expect(service.registerCallCount == 1, "one prompt per install, not one per operation")
  }

  @Test("eight privileged needs at once register once")
  func concurrentPrivilegedNeedsRegisterOnce() async throws {
    let service = FakeHelperService(status: .notRegistered)
    let coordinator = makeRegistrationCoordinator(service: service)

    let states = await withTaskGroup(of: HelperRegistrationState.self) { group in
      for _ in 0..<8 {
        group.addTask { await coordinator.ensureRegistered() }
      }
      var seen: [HelperRegistrationState] = []
      for await state in group {
        seen.append(state)
      }
      return seen
    }

    #expect(service.registerCallCount == 1)
    #expect(states.allSatisfy { $0 == .awaitingApproval })
  }

  @Test("an unavailable coordinator does not retry registration")
  func unavailableCoordinatorDoesNotRetry() async throws {
    let service = FakeHelperService(
      status: .notRegistered, onRegister: .throwsOperationNotPermittedAndStaysNotRegistered)
    let coordinator = makeRegistrationCoordinator(service: service)

    let first = await coordinator.ensureRegistered()
    let second = await coordinator.ensureRegistered()

    #expect(first == second)
    #expect(service.registerCallCount == 1)
  }

  // MARK: Approval, whenever it arrives

  @Test("approval granted in System Settings moves the coordinator to enabled")
  func approvalGrantedMovesToEnabled() async throws {
    let service = FakeHelperService(status: .notRegistered)
    let coordinator = makeRegistrationCoordinator(service: service)
    #expect(await coordinator.ensureRegistered() == .awaitingApproval)

    service.approveInSystemSettings()

    #expect(await coordinator.state == .enabled)
    #expect(await coordinator.ensureRegistered() == .enabled)
    #expect(service.registerCallCount == 1, "an approved item is not registered a second time")
  }

  @Test("an item enabled after a failed attempt reads as enabled without registering again")
  func enabledAfterAFailedAttemptReadsAsEnabled() async throws {
    let service = FakeHelperService(
      status: .notRegistered, onRegister: .throwsOperationNotPermittedAndStaysNotRegistered)
    let coordinator = makeRegistrationCoordinator(service: service)
    _ = await coordinator.ensureRegistered()

    service.approveInSystemSettings()

    #expect(await coordinator.state == .enabled)
    #expect(service.registerCallCount == 1)
  }

  @Test("an approval withdrawn again leaves the helper unusable rather than silently enabled")
  func approvalWithdrawnLeavesTheHelperUnusable() async throws {
    let service = FakeHelperService(status: .enabled)
    let coordinator = makeRegistrationCoordinator(service: service)
    #expect(await coordinator.state == .enabled)

    service.setStatus(.requiresApproval)

    #expect(await coordinator.state == .awaitingApproval)
  }
}
