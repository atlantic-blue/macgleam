/// Pure mapping from a destination and the live module summaries to the pane
/// that destination shows.
///
/// Guarantees:
/// - Total: every destination returns a pane.
/// - A pane carries an action exactly when its module is enabled, and a not
///   ready note exactly when it does not. Never both, never neither.
/// - The job names come from the agreed design, so a module that has not
///   shipped still tells the truth about what it is going to do.
/// - The live figure from the module's summary appears on its first job and
///   nowhere else, so a figure is never shown twice or attributed to the
///   wrong job.
public enum ModulePaneResolver {

  public static func pane(
    for destination: HubDestination,
    summaries: [HubModuleSummary]
  ) -> ModulePane {
    switch destination {
    case .module(let module):
      return modulePane(module, summary: summaries.first { $0.module == module })
    case .diskMap:
      return ModulePane(
        title: destination.title,
        sentence: "See where the space went, folder by folder.",
        jobs: [ModulePaneJob(name: "Map a volume by folder size", symbolName: "square.grid.3x3")],
        action: ModulePaneAction(title: "Open the map"),
        notReadyNote: nil
      )
    case .settings:
      return ModulePane(
        title: destination.title,
        sentence: "How MacGleam deletes, what it watches, and how much it moves.",
        jobs: [],
        action: nil,
        notReadyNote: "Settings arrives with the modules that need it."
      )
    }
  }

  private static func modulePane(_ module: HubModule, summary: HubModuleSummary?) -> ModulePane {
    let isEnabled = summary?.isEnabled ?? false
    return ModulePane(
      title: module.title,
      sentence: module.summarySentence,
      jobs: jobs(for: module, figure: summary?.figure ?? ""),
      action: isEnabled ? ModulePaneAction(title: actionTitle(for: module)) : nil,
      notReadyNote: isEnabled ? nil : notReadyNote(for: module)
    )
  }

  /// The job list each module runs, taken from the agreed design. The first
  /// job carries the module's live figure when it has one.
  private static func jobs(for module: HubModule, figure: String) -> [ModulePaneJob] {
    let named: [(String, String)]
    switch module {
    case .fullSweep:
      named = [
        ("Deep clean", "wand.and.sparkles"),
        ("Storage deleftovers", "internaldrive"),
        ("Performance boost", "bolt"),
      ]
    case .cleanup:
      named = [
        ("System junk", "trash"),
        ("Mail attachments", "paperclip"),
        ("Trash bins", "arrow.up.bin"),
      ]
    case .protection:
      named = [
        ("Malware and adware scan", "shield.lefthalf.filled"),
        ("Privacy cleanup", "hand.raised"),
        ("Quarantine with 30 day restore", "arrow.uturn.backward"),
      ]
    case .performance:
      named = [
        ("Maintenance tasks", "wrench.and.screwdriver"),
        ("Login and background items", "power"),
        ("Live memory and processor", "gauge.with.needle"),
      ]
    case .applications:
      named = [
        ("Full uninstall with leftovers", "trash.square"),
        ("Leftover sweep", "shippingbox"),
      ]
    case .leftovers:
      named = [
        ("Duplicates", "doc.on.doc"),
        ("Similar photos", "photo.stack"),
        ("Large and old files", "clock.arrow.circlepath"),
        ("Downloads triage", "arrow.down.circle"),
      ]
    }
    return named.enumerated().map { position, job in
      ModulePaneJob(name: job.0, symbolName: job.1, detail: position == 0 ? figure : "")
    }
  }

  private static func actionTitle(for module: HubModule) -> String {
    switch module {
    case .fullSweep: return "Run Full Sweep"
    case .cleanup: return "Scan"
    case .protection: return "Check"
    case .performance: return "Scan"
    case .applications: return "Scan"
    case .leftovers: return "Scan"
    }
  }

  private static func notReadyNote(for module: HubModule) -> String {
    "\(module.title) is not built yet. Nothing here will run."
  }
}
