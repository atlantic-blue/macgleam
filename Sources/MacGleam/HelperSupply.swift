import Foundation
import GleamCore
import GleamHelperClient
import ServiceManagement
import os

/// The app's privileged half, assembled but not started.
///
/// Building this connects to nothing and registers nothing. The registration
/// coordinator is shared across every run, so the system is asked to register
/// the helper at most once however many plans are executed, and it is asked by
/// the first operation that genuinely needs privilege rather than by launch.
/// The connection is per run: each plan gets its own transport, and so its own
/// handshake, and a run's connection outlives no run.
final class HelperSupply: Sendable {
  private let registration: HelperRegistrationCoordinator
  private let userHome: AbsolutePath
  private let safetyNetStoreDirectory: AbsolutePath
  private let hasDirectedToSettings = OSAllocatedUnfairLock(initialState: false)

  init(
    service: any HelperServiceRegistering = SystemHelperService(),
    userHome: AbsolutePath = AbsolutePath(normalising: NSHomeDirectory()),
    safetyNetStoreDirectory: AbsolutePath = HelperSupply.applicationSupportSafetyNetStore()
  ) {
    self.registration = HelperRegistrationCoordinator(service: service)
    self.userHome = userHome
    self.safetyNetStoreDirectory = safetyNetStoreDirectory
  }

  func makeHelper() -> any PrivilegedOperationPerforming {
    ApprovalDirectingHelper(
      client: HelperClient(
        transport: XPCHelperTransport(),
        registration: registration,
        userHome: userHome,
        safetyNetStoreDirectory: safetyNetStoreDirectory
      ),
      registration: registration,
      directToApproval: { [hasDirectedToSettings] in
        let isFirstTime = hasDirectedToSettings.withLock { directed -> Bool in
          guard !directed else { return false }
          directed = true
          return true
        }
        guard isFirstTime else { return }
        Task { @MainActor in SMAppService.openSystemSettingsLoginItems() }
      }
    )
  }

  /// Where a quarantined or archived item the helper moves is put. It sits
  /// beside the settings in Application Support, which is the store's home in
  /// C18 and the reason it survives a reinstall.
  static func applicationSupportSafetyNetStore() -> AbsolutePath {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return AbsolutePath(normalising: base.appending(path: "MacGleam/SafetyNet").path)
  }
}

/// Opens the approval screen the first time the helper turns out to be waiting
/// for it, and never again.
///
/// It sits outside the helper client on purpose. The client decides what an
/// operation's result is and nothing else; opening a window at somebody is an
/// app's business, and a client that did it could not be reasoned about from
/// its result alone. Once per app run, too: a plan of forty system items that
/// threw the approval screen up forty times would be the app shouting.
struct ApprovalDirectingHelper: PrivilegedOperationPerforming {
  let client: HelperClient
  let registration: HelperRegistrationCoordinator
  let directToApproval: @Sendable () -> Void

  func perform(_ operation: GleamCore.Operation, planID: UUID) async -> OperationResult {
    let result = await client.perform(operation, planID: planID)
    if case .awaitingApproval = await registration.state { directToApproval() }
    return result
  }
}
