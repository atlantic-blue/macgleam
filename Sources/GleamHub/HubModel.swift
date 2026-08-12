import Foundation
import Observation

/// The hub view model, on the macOS 14 Observation framework. The SwiftUI hub
/// renders this and adds no state of its own.
///
/// Derivation is pure and total: no timers, no clock reads, no hidden state.
/// `HubMachineState.now` is the only time source. `apply` is the only
/// mutation path, and after it every published property equals the pure
/// function of the applied state.
@MainActor @Observable
public final class HubModel {
  public private(set) var orbMood: OrbMood
  public private(set) var statusLine: String
  public private(set) var summaries: [HubModuleSummary]

  public init(state: HubMachineState) {
    orbMood = Self.mood(for: state)
    statusLine = Self.statusLine(for: state)
    summaries = Self.summaries(for: state)
  }

  public func apply(_ state: HubMachineState) {
    orbMood = Self.mood(for: state)
    statusLine = Self.statusLine(for: state)
    summaries = Self.summaries(for: state)
  }

  /// A sweep in progress decides the mood while it runs, because that is the
  /// one thing happening. With no sweep it is `idleAttention` exactly when an
  /// attention reason is present and `idleHealthy` otherwise.
  public nonisolated static func mood(for state: HubMachineState) -> OrbMood {
    switch state.sweepActivity {
    case .scanning:
      return .scanning
    case .result:
      return .result
    case .cleanSweep:
      return .cleanSweep
    case nil:
      break
    }
    if state.attentionReason != nil {
      return .idleAttention
    }
    return .idleHealthy
  }

  /// Never empty. With an attention reason it is exactly that sentence.
  /// Otherwise it names the last scan recency and the reclaimable estimate;
  /// before any scan exists it invites the first one.
  public nonisolated static func statusLine(for state: HubMachineState) -> String {
    switch state.sweepActivity {
    case .scanning(let bytes):
      guard bytes > 0 else { return "Checking your Mac." }
      return "Checking your Mac. \(byteFigure(bytes)) so far."
    case .result(let bytes, let issues):
      let things = issues == 1 ? "1 thing" : "\(issues) things"
      return "\(things) to deal with, \(byteFigure(bytes)) reclaimable."
    case .cleanSweep:
      return "Nothing to do. Your Mac is in good shape."
    case nil:
      break
    }
    if let attentionReason = state.attentionReason {
      return attentionReason
    }
    guard let lastScanFinishedAt = state.lastScanFinishedAt else {
      return "Run your first scan to see what your Mac can reclaim."
    }
    let recency = recencyPhrase(from: lastScanFinishedAt, to: state.now)
    guard let estimateBytes = state.reclaimableEstimateBytes else {
      return "Last scan \(recency)."
    }
    return "Last scan \(recency). \(byteFigure(estimateBytes)) reclaimable."
  }

  /// Always exactly six entries, one per HubModule, in `allCases` order. A
  /// module missing from `moduleFigures` gets an empty figure.
  public nonisolated static func summaries(for state: HubMachineState) -> [HubModuleSummary] {
    HubModule.allCases.map { module in
      HubModuleSummary(
        module: module,
        figure: state.moduleFigures[module] ?? "",
        isEnabled: state.enabledModules.contains(module)
      )
    }
  }

  private nonisolated static func recencyPhrase(from finishedAt: Date, to now: Date) -> String {
    let seconds = now.timeIntervalSince(finishedAt)
    if seconds < 60 {
      return "moments ago"
    }
    let minutes = Int(seconds / 60)
    if minutes < 60 {
      return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
    }
    let hours = minutes / 60
    if hours < 24 {
      return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
    }
    let days = hours / 24
    return days == 1 ? "1 day ago" : "\(days) days ago"
  }

  private nonisolated static func byteFigure(_ bytes: UInt64) -> String {
    let units = ["KB", "MB", "GB", "TB", "PB"]
    if bytes < 1000 {
      return bytes == 1 ? "1 byte" : "\(bytes) bytes"
    }
    var value = Double(bytes)
    var unitIndex = -1
    while value >= 1000, unitIndex < units.count - 1 {
      value /= 1000
      unitIndex += 1
    }
    let tenths = (value * 10).rounded() / 10
    if tenths == tenths.rounded() {
      return "\(Int(tenths)) \(units[unitIndex])"
    }
    return "\(tenths) \(units[unitIndex])"
  }
}
