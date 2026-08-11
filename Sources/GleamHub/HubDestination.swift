/// Everywhere the navigation rail can take you, in rail order.
///
/// A closed set with exactly one selected at all times. There is no
/// unselected state and no separate overview screen: the app opens on the
/// first destination and the pane beside the rail always shows something.
public enum HubDestination: Hashable, Codable, Sendable, CaseIterable {
  case module(HubModule)
  case diskMap
  case settings

  /// Rail order, top to bottom. The order is part of the contract; the rail
  /// never reorders at runtime.
  public static let allCases: [HubDestination] =
    HubModule.allCases.map(HubDestination.module) + [.diskMap, .settings]

  /// The rail draws a gap between groups. Modules and the disk map are the
  /// work; settings sits apart from it.
  public var group: HubDestinationGroup {
    switch self {
    case .module, .diskMap: return .work
    case .settings: return .apart
    }
  }

  public var title: String {
    switch self {
    case .module(let module): return module.title
    case .diskMap: return "Disk Map"
    case .settings: return "Settings"
    }
  }

  /// The SF Symbol the rail draws beside the title.
  public var symbolName: String {
    switch self {
    case .module(let module): return module.symbolName
    case .diskMap: return "circle.grid.2x2"
    case .settings: return "gearshape"
    }
  }
}

public enum HubDestinationGroup: CaseIterable, Sendable, Equatable {
  case work
  case apart
}

extension HubModule {
  public var title: String {
    switch self {
    case .fullSweep: return "Full Sweep"
    case .cleanup: return "Cleanup"
    case .protection: return "Protection"
    case .performance: return "Performance"
    case .applications: return "Applications"
    case .leftovers: return "Leftovers"
    }
  }

  public var symbolName: String {
    switch self {
    case .fullSweep: return "sparkles"
    case .cleanup: return "wand.and.sparkles"
    case .protection: return "shield"
    case .performance: return "speedometer"
    case .applications: return "square.grid.2x2"
    case .leftovers: return "folder.badge.questionmark"
    }
  }

  /// One sentence saying what this module is for, shown under its heading.
  public var summarySentence: String {
    switch self {
    case .fullSweep: return "Quick maintenance that takes care of the essentials."
    case .cleanup: return "Find the junk your Mac keeps and reclaim the space."
    case .protection: return "Check for malware and clear what is tracking you."
    case .performance: return "See what is slowing the Mac down and stop it."
    case .applications: return "Update, tidy and fully remove the apps you have."
    case .leftovers: return "Duplicates, similar photos and files you forgot."
    }
  }
}
