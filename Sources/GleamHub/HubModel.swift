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
  public private(set) var cards: [HubCard]

  public init(state: HubMachineState) {
    orbMood = Self.mood(for: state)
    statusLine = Self.statusLine(for: state)
    cards = Self.cards(for: state)
  }

  public func apply(_ state: HubMachineState) {
    orbMood = Self.mood(for: state)
    statusLine = Self.statusLine(for: state)
    cards = Self.cards(for: state)
  }

  /// `idleAttention` exactly when an attention reason is present,
  /// `idleHealthy` otherwise. The other moods become reachable when Smart
  /// Care wires in.
  public nonisolated static func mood(for state: HubMachineState) -> OrbMood {
    if state.attentionReason != nil {
      return .idleAttention
    }
    return .idleHealthy
  }

  /// Never empty. With an attention reason it is exactly that sentence.
  /// Otherwise it names the last scan recency and the reclaimable estimate;
  /// before any scan exists it invites the first one.
  public nonisolated static func statusLine(for state: HubMachineState) -> String {
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
  /// module missing from `cardFigures` gets an empty figure.
  public nonisolated static func cards(for state: HubMachineState) -> [HubCard] {
    HubModule.allCases.map { module in
      HubCard(
        module: module,
        figure: state.cardFigures[module] ?? "",
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
