import Foundation
import GleamCore

/// The root side of the maintenance tasks. Each one is a fixed tool with fixed
/// arguments, chosen by a case of the closed `MaintenanceTask` set, so the set
/// of commands this daemon can ever run is written out below in full.
enum HelperMaintenance {
  private struct Command {
    let tool: String
    let arguments: [String]
  }

  enum TaskFailure: Error, LocalizedError {
    case toolFailed(tool: String, status: Int32, output: String)

    var errorDescription: String? {
      switch self {
      case .toolFailed(let tool, let status, let output):
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let ending = detail.isEmpty ? "." : ": \(detail)"
        return "\(tool) stopped with status \(status)\(ending)"
      }
    }
  }

  static func run(_ task: MaintenanceTask) throws {
    for command in commands(for: task) {
      let outcome = try HelperProcessRunner.run(command.tool, command.arguments)
      guard outcome.succeeded else {
        throw TaskFailure.toolFailed(
          tool: command.tool, status: outcome.status, output: outcome.output)
      }
    }
  }

  private static func commands(for task: MaintenanceTask) -> [Command] {
    switch task {
    case .flushDomainNameSystemCache:
      return [
        Command(tool: "/usr/bin/dscacheutil", arguments: ["-flushcache"]),
        Command(tool: "/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"]),
      ]
    case .rebuildLaunchServicesDatabase:
      return [
        Command(
          tool: launchServicesRegister,
          arguments: ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"])
      ]
    case .triggerSpotlightReindex:
      return [Command(tool: "/usr/bin/mdutil", arguments: ["-E", "/"])]
    case .purgeMemoryPressure:
      return [Command(tool: "/usr/sbin/purge", arguments: [])]
    case .runPeriodicMaintenance:
      return [Command(tool: "/usr/sbin/periodic", arguments: ["daily", "weekly", "monthly"])]
    }
  }

  private static let launchServicesRegister =
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework"
    + "/Support/lsregister"
}
