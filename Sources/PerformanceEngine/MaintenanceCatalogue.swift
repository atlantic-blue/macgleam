import GleamCore

/// What the Performance module says about each maintenance task: the sentence
/// describing the task, and, for a task that clears data the person can notice
/// as lost, the sentence warning them before it runs.
///
/// The warning exists exactly where `MaintenanceTask.clearsUserVisibleData` is
/// true, because the flag is the gate rather than a list of task names. A case
/// added to the enum inherits both the rule and a compile error here until
/// somebody writes its wording.
public enum MaintenanceCatalogue {
  /// Every task, in the order the review presents them, which is the order
  /// the cases are declared. Taken from `allCases` so a task added later
  /// appears without this list being remembered.
  public static let tasks: [MaintenanceTask] = MaintenanceTask.allCases

  /// What the task does, in one plain sentence. Never empty, and never a
  /// warning: what a task costs the person is `warning(for:)`, so a caller
  /// showing only the explanation cannot show a warning by accident.
  public static func explanation(for task: MaintenanceTask) -> String {
    switch task {
    case .flushDomainNameSystemCache:
      return
        "Refreshes the Domain Name System lookups this Mac uses to find websites, "
        + "which fixes a site that loads everywhere else but not here."
    case .rebuildLaunchServicesDatabase:
      return
        "Rebuilds the index macOS keeps of which app opens which kind of file, "
        + "which fixes duplicate and stale entries in the Open With menu."
    case .triggerSpotlightReindex:
      return
        "Asks Spotlight to index this Mac again, so searches find files that "
        + "have been missing from the results."
    case .purgeMemoryPressure:
      return
        "Returns inactive memory the system is still holding to the free pool, "
        + "which eases a Mac that has been awake for weeks."
    case .runPeriodicMaintenance:
      return
        "Runs the daily, weekly and monthly upkeep macOS schedules for the small "
        + "hours, which a Mac that sleeps overnight may never have run."
    }
  }

  /// What the person loses when the task runs, named in words rather than in
  /// an acronym, or nil when the task costs them nothing. Non nil exactly when
  /// `task.clearsUserVisibleData` is true: the guard is the only path to nil,
  /// so the two can never disagree.
  public static func warning(for task: MaintenanceTask) -> String? {
    guard task.clearsUserVisibleData else { return nil }
    switch task {
    case .flushDomainNameSystemCache:
      return
        "This clears the Domain Name System lookups this Mac has remembered, so the "
        + "first visit to each website afterwards takes a moment longer while its "
        + "address is found again."
    case .rebuildLaunchServicesDatabase, .triggerSpotlightReindex, .purgeMemoryPressure,
      .runPeriodicMaintenance:
      // Unreachable while these four clear nothing. Spelled out rather than
      // defaulted so that setting the flag on one of them is a decision taken
      // here, beside the sentence the person would read.
      return "This clears data you will notice as missing until the Mac builds it again."
    }
  }
}
