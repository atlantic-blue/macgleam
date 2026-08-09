import Foundation

/// What the onboarding flow hands the cleanup module about Full Disk Access.
/// A plain value so tests construct any degraded condition directly.
/// `unavailable` is empty exactly when `hasFullDiskAccess` is true; each entry
/// is a plain sentence naming something the module cannot reach, renderable in
/// the honest banner verbatim.
public struct CleanupDegradedState: Sendable, Equatable {
  public let hasFullDiskAccess: Bool
  public let unavailable: [String]

  public init(hasFullDiskAccess: Bool, unavailable: [String]) {
    self.hasFullDiskAccess = hasFullDiskAccess
    self.unavailable = unavailable
  }
}

/// The module's view of the onboarding model's degraded state. A protocol so
/// tests script grant and decline without the real monitor.
public protocol CleanupDegradedStateProviding: Sendable {
  func current() async -> CleanupDegradedState
}
