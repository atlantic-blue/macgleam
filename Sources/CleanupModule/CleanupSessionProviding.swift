import Foundation
import GleamCore

/// Mints the per session scan and plan contexts. The one place the file
/// system, rules catalogue and ownership policy are visible to the module
/// wiring; the model itself never holds them, which makes "the model never
/// touches the file system" a compile time property rather than a review
/// note.
///
/// Every `makeScanContext` call mints a fresh session identifier; no two
/// calls return contexts sharing one. `makePlanContext(sessionID:settings:)`
/// returns a context for exactly that session, so planning against a stale
/// session stays detectable.
public protocol CleanupSessionProviding: Sendable {
  func makeScanContext(settings: Settings, hasFullDiskAccess: Bool) async -> ScanContext
  func makePlanContext(sessionID: UUID, settings: Settings) async -> PlanContext
}
