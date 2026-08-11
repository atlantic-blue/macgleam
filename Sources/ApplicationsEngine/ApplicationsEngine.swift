import Foundation
import GleamCore

/// App inventory: every installed application, and the files a full uninstall
/// would have to take with it.
///
/// Discovery reads each bundle's own Info.plist for its identifier, name and
/// version; a bundle that will not say who it is is not offered and does not
/// sink the scan. Files are attributed by `LeftoverAssociation`, which claims a
/// path only on an exact match against an installed bundle identifier, because
/// a false association here is a stranger's file deleted by somebody else's
/// uninstall. MacGleam is never offered, and that exclusion follows the running
/// application's own identity rather than a name on the disk.
public struct ApplicationsEngine: GleamEngine {
  /// MacGleam's own bundle identifier, the same one the helper admits its
  /// client by (C31). One value, so an application cannot be excluded from the
  /// inventory and admitted by the helper under two different names.
  public static let macGleamBundleID = "com.atlanticblue.macgleam"

  public var module: GleamModule { .applications }

  private let runningApplicationBundleID: String

  public init(runningApplicationBundleID: String = ApplicationsEngine.macGleamBundleID) {
    self.runningApplicationBundleID = runningApplicationBundleID
  }

  /// Every installed application and everything attributed to it, ordered by
  /// bundle identifier, each application's leftovers ordered by path.
  public func inventory(context: ScanContext) async throws -> [AppInventoryEntry] {
    let survey = try await ApplicationSurvey.survey(context) { _ in }
    return try await survey.applications(
      fileSystem: context.fileSystem, excluding: runningApplicationBundleID)
  }

  public func scan(_ context: ScanContext) -> AsyncThrowingStream<ScanEvent, Error> {
    AsyncThrowingStream { continuation in
      let scanTask = Task {
        do {
          try await runScan(context) { continuation.yield($0) }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in scanTask.cancel() }
    }
  }

  /// An uninstall: one archive operation per selected path, the bundle and its
  /// leftovers sharing one group so the whole application restores as a unit
  /// (C26). There is no separate delete step, so no window exists where a file
  /// is gone from disk and not yet in the SafetyNet store.
  ///
  /// MacGleam is filtered here as well as at the offer, on the identity a
  /// finding claims rather than on a path, so a forged finding naming
  /// MacGleam's own bundle beside a real application plans the real one and
  /// nothing at all against MacGleam. The denylist is the codebase's precedent
  /// for holding one rule at several independent points.
  public func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan {
    guard !selection.isEmpty else { throw PlanningError.emptySelection }
    for finding in selection where finding.sessionID != context.sessionID {
      throw PlanningError.findingFromDifferentSession(finding.id)
    }
    var builder = UninstallPlanBuilder(context: context, excluding: runningApplicationBundleID)
    for finding in selection {
      builder.add(finding)
    }
    return builder.build(sessionID: context.sessionID)
  }
}

// MARK: - Scanning

extension ApplicationsEngine {
  fileprivate func runScan(
    _ context: ScanContext,
    yield: @Sendable (ScanEvent) -> Void
  ) async throws {
    yield(.phase(.indeterminate))
    for sentence in ApplicationSurvey.degradedNotices(context) {
      yield(.degraded(unavailable: sentence))
    }
    let survey = try await ApplicationSurvey.survey(context, yield: yield)
    yield(.phase(.determinate(estimatedTotalFiles: survey.counters.filesSeen)))
    let applications = try await survey.applications(
      fileSystem: context.fileSystem, excluding: runningApplicationBundleID)
    var counters = survey.counters
    for finding in Self.findings(for: applications, survey: survey, sessionID: context.sessionID) {
      try Task.checkCancellation()
      counters.itemCount += finding.itemCount
      counters.bytesReclaimable += finding.byteSize
      yield(.finding(finding))
      yield(.progress(counters))
    }
    yield(.phase(.settling))
  }

  /// One bundle finding per application, then its leftovers. An application
  /// with nothing left behind emits no leftover finding at all rather than an
  /// empty one: outside the Performance module a finding names at least one
  /// path (C5).
  private static func findings(
    for applications: [AppInventoryEntry],
    survey: ApplicationSurvey,
    sessionID: UUID
  ) -> [Finding] {
    applications.flatMap { application in
      [
        bundleFinding(
          for: application,
          allocatedBytes: survey.bundleBytes[application.installLocation] ?? 0,
          sessionID: sessionID)
      ] + leftoverFindings(for: application, sessionID: sessionID)
    }
  }

  private static func bundleFinding(
    for application: AppInventoryEntry,
    allocatedBytes: UInt64,
    sessionID: UUID
  ) -> Finding {
    Finding(
      id: UUID(),
      sessionID: sessionID,
      category: .applicationBundle(bundleID: application.bundleID),
      entries: [PathEntry(path: application.installLocation, allocatedBytes: allocatedBytes)],
      risk: .review,
      explanation: "\(application.name) is installed at "
        + "\(application.installLocation.value). Uninstalling it removes the application "
        + "itself, and every file left behind is listed beside it rather than folded "
        + "into a total.",
      isPreselected: false)
  }

  /// The attributed leftovers, in batches of at most the entry cap so one
  /// application with an enormous cache is still a list a person can read
  /// (C15).
  private static func leftoverFindings(
    for application: AppInventoryEntry,
    sessionID: UUID
  ) -> [Finding] {
    let entries = application.leftoverPaths.map {
      PathEntry(path: $0.path, allocatedBytes: $0.byteSize)
    }
    return stride(from: 0, to: entries.count, by: ScanStreamPolicy.maximumFindingEntries).map {
      start in
      Finding(
        id: UUID(),
        sessionID: sessionID,
        category: .applicationLeftover(bundleID: application.bundleID),
        entries: Array(
          entries[start..<min(start + ScanStreamPolicy.maximumFindingEntries, entries.count)]),
        risk: .review,
        explanation: "Files \(application.name) left in the usual support locations. Each "
          + "one is named \(application.bundleID) exactly; nothing that merely starts with "
          + "that identifier or contains it is claimed here.",
        isPreselected: false)
    }
  }
}
