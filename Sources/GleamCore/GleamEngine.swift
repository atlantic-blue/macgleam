import Foundation

/// The shape every engine shares. Scan streams findings; plan turns the
/// user's selection into an operation plan; execution belongs to the
/// executor. Engines never delete anything themselves.
///
/// Scanning is read only and side effect free: running it twice against the
/// same file system state yields the same findings, identifiers aside. Phases
/// advance per ScanPhase and counters are monotonic. Without Full Disk Access
/// an engine scans what the user domain allows and reports what it skipped
/// through `ScanEvent.degraded`. Planning includes only selected findings,
/// expands each finding into one operation per path, never emits an operation
/// for a denylisted path, and throws `PlanningError` rather than producing a
/// partial plan.
public protocol GleamEngine: Sendable {
  var module: GleamModule { get }
  func scan(_ context: ScanContext) -> AsyncThrowingStream<ScanEvent, Error>
  func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan
}

/// Everything a scan needs. Engines receive the read side of the file system
/// only, which is what keeps "engines never delete" a compile time property.
public struct ScanContext: Sendable {
  public let sessionID: UUID
  public let fileSystem: any FileSystemReading
  public let rules: RuleCatalog
  public let settings: Settings
  public let hasFullDiskAccess: Bool

  public init(
    sessionID: UUID,
    fileSystem: any FileSystemReading,
    rules: RuleCatalog,
    settings: Settings,
    hasFullDiskAccess: Bool
  ) {
    self.sessionID = sessionID
    self.fileSystem = fileSystem
    self.rules = rules
    self.settings = settings
    self.hasFullDiskAccess = hasFullDiskAccess
  }
}

/// Everything planning needs. Privilege routing comes from the ownership
/// policy so app and helper cannot drift.
public struct PlanContext: Sendable {
  public let sessionID: UUID
  public let rules: RuleCatalog
  public let settings: Settings
  public let ownership: any PathOwnershipPolicy

  public init(
    sessionID: UUID,
    rules: RuleCatalog,
    settings: Settings,
    ownership: any PathOwnershipPolicy
  ) {
    self.sessionID = sessionID
    self.rules = rules
    self.settings = settings
    self.ownership = ownership
  }
}

/// One event of a scan stream. `degraded` carries a plain sentence naming
/// what was skipped, so the honest banner has real content.
public enum ScanEvent: Sendable {
  case phase(ScanPhase)
  case progress(ScanCounters)
  case finding(Finding)
  case degraded(unavailable: String)
}

public enum PlanningError: Error, Sendable, Equatable {
  case emptySelection
  case findingFromDifferentSession(UUID)
  case keptCopyMissing(findingID: UUID)
}
