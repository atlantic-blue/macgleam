import Foundation
import GleamCore

/// The root side of a system scope launch item change.
///
/// Disabling never deletes: `launchctl disable` writes the item into launchd's
/// disabled set and leaves the property list where it is, so re enabling is
/// the same command with the other verb and nothing has to be reconstructed.
///
/// The prior state is read before the change and returned with it. It is read
/// rather than assumed: an item already disabled by something else must not
/// come back enabled because MacGleam was the one that turned it off.
enum HelperLaunchItems {
  enum ChangeFailure: Error, LocalizedError {
    case priorStateUnreadable(String)
    case changeFailed(status: Int32, output: String)

    var errorDescription: String? {
      switch self {
      case .priorStateUnreadable(let detail):
        return
          "launchd would not say whether the item is enabled, so nothing was changed: \(detail)"
      case .changeFailed(let status, let output):
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let ending = detail.isEmpty ? "." : ": \(detail)"
        return "launchctl stopped with status \(status)\(ending)"
      }
    }
  }

  static func setEnabled(
    _ enabled: Bool,
    item: LaunchItemID,
    now: Date
  ) throws -> LaunchItemChange {
    let previousEnabled = try isEnabled(item)
    let outcome = try HelperProcessRunner.run(
      launchControl, [enabled ? "enable" : "disable", "system/\(item.value)"])
    guard outcome.succeeded else {
      throw ChangeFailure.changeFailed(status: outcome.status, output: outcome.output)
    }
    return LaunchItemChange(
      item: item,
      previousEnabled: previousEnabled,
      newEnabled: enabled,
      changedAt: now
    )
  }

  /// An item is enabled unless launchd's disabled set says otherwise, which is
  /// launchd's own rule: the set records only what has been turned off.
  static func isEnabled(_ item: LaunchItemID) throws -> Bool {
    let outcome = try HelperProcessRunner.run(launchControl, ["print-disabled", "system"])
    guard outcome.succeeded else {
      throw ChangeFailure.priorStateUnreadable(
        "launchctl print-disabled stopped with status \(outcome.status)")
    }
    guard let line = disabledLine(for: item, in: outcome.output) else { return true }
    return !line.contains("true") && !line.contains("disabled")
  }

  private static func disabledLine(for item: LaunchItemID, in output: String) -> String? {
    let quoted = "\"\(item.value)\""
    return output.split(separator: "\n").map(String.init).first { $0.contains(quoted) }
  }

  private static let launchControl = "/bin/launchctl"
}
