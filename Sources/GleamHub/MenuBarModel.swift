import Foundation
import GleamCore
import Observation

/// What the menu bar shows, and what it hides.
///
/// A menu bar item is read in a glance, so this is a small model with one job:
/// take a sample, honour the preferences, and answer with the lines somebody
/// can read without stopping. It holds no figure the hub does not hold, so the
/// two never disagree.
@MainActor @Observable
public final class MenuBarModel {
  public private(set) var lines: [MenuBarLine] = []
  public private(set) var lastSample: SystemStats?

  @ObservationIgnored private let stats: any SystemStatsProviding
  @ObservationIgnored private var preferences: MenuBarPreferences
  @ObservationIgnored private var samplingTask: Task<Void, Never>?

  public init(stats: any SystemStatsProviding, preferences: MenuBarPreferences) {
    self.stats = stats
    self.preferences = preferences
  }

  deinit {
    samplingTask?.cancel()
  }

  /// Starts sampling. A second call replaces the first, so a preference change
  /// that restarts the stream cannot leave two of them running.
  public func start() {
    samplingTask?.cancel()
    let stream = stats.samples()
    samplingTask = Task { [weak self] in
      for await sample in stream {
        guard let self else { return }
        await self.apply(sample)
      }
    }
  }

  public func stop() {
    samplingTask?.cancel()
    samplingTask = nil
  }

  /// A preference change takes effect on what is already on screen rather than
  /// at the next sample, because somebody who just switched a row off expects
  /// it gone now.
  public func apply(_ updated: MenuBarPreferences) {
    preferences = updated
    guard let lastSample else {
      lines = []
      return
    }
    lines = Self.lines(for: lastSample, preferences: updated)
  }

  private func apply(_ sample: SystemStats) {
    lastSample = sample
    lines = Self.lines(for: sample, preferences: preferences)
  }

  /// The lines a sample produces, in a fixed order: storage, memory, then the
  /// processor. Fixed because a menu bar that reorders itself between samples
  /// cannot be read at a glance, which is the only thing it is for.
  public nonisolated static func lines(
    for sample: SystemStats,
    preferences: MenuBarPreferences
  ) -> [MenuBarLine] {
    var lines: [MenuBarLine] = []
    if preferences.showsStorage {
      lines.append(
        MenuBarLine(
          kind: .storage,
          title: "Storage",
          value: ByteFigure.string(sample.bootVolumeAvailableBytes) + " free",
          fraction: fraction(
            of: sample.bootVolumeUsedBytes, in: sample.bootVolumeCapacityBytes),
          isAttention: fraction(
            of: sample.bootVolumeUsedBytes, in: sample.bootVolumeCapacityBytes) >= 0.9))
    }
    if preferences.showsMemory {
      lines.append(
        MenuBarLine(
          kind: .memory,
          title: "Memory",
          value: memoryValue(sample),
          fraction: nil,
          isAttention: sample.memoryPressure != .normal))
    }
    if preferences.showsProcessorLoad {
      lines.append(
        MenuBarLine(
          kind: .processor,
          title: "Processor",
          value: "\(Int((sample.processorLoadFraction * 100).rounded())) per cent",
          fraction: sample.processorLoadFraction,
          isAttention: sample.processorLoadFraction >= 0.9))
    }
    return lines
  }

  private nonisolated static func memoryValue(_ sample: SystemStats) -> String {
    switch sample.memoryPressure {
    case .normal:
      return ByteFigure.string(sample.memoryUsedBytes) + " used"
    case .warning:
      return ByteFigure.string(sample.memoryUsedBytes) + " used, under pressure"
    case .critical:
      return ByteFigure.string(sample.memoryUsedBytes) + " used, running out"
    }
  }

  private nonisolated static func fraction(of part: UInt64, in whole: UInt64) -> Double {
    guard whole > 0 else { return 0 }
    return min(max(Double(part) / Double(whole), 0), 1)
  }
}

/// One row of the menu bar popover: what it is, what it says, and whether it
/// is the reason somebody should open the app.
public struct MenuBarLine: Sendable, Equatable, Identifiable {
  public enum Kind: String, Sendable, Equatable, CaseIterable {
    case storage, memory, processor
  }

  public var id: Kind { kind }
  public let kind: Kind
  public let title: String
  public let value: String
  /// The share a bar would draw, and nil for a row that is not a share of
  /// anything.
  public let fraction: Double?
  public let isAttention: Bool

  public init(kind: Kind, title: String, value: String, fraction: Double?, isAttention: Bool) {
    self.kind = kind
    self.title = title
    self.value = value
    self.fraction = fraction
    self.isAttention = isAttention
  }
}
