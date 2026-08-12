import Foundation

/// Storage, memory and processor figures for the menu bar scene and the hub's
/// live figures.
///
/// Guarantees:
/// - `samples` streams at a cadence suitable for a glanceable display and
///   never blocks the main actor.
/// - Storage figures agree with `VolumeInfo` for the boot volume, so the menu
///   bar and the Disk Map never show contradictory numbers for the same volume
///   at the same instant of sampling.
/// - Memory pressure buckets match the platform's own notion, so nothing
///   invents a fourth state.
public protocol SystemStatsProviding: Sendable {
  func samples() -> AsyncStream<SystemStats>
}

public struct SystemStats: Sendable, Equatable {
  public enum MemoryPressure: String, Sendable, Equatable, CaseIterable {
    case normal, warning, critical
  }

  public let bootVolumeCapacityBytes: UInt64
  public let bootVolumeAvailableBytes: UInt64
  public let memoryPressure: MemoryPressure
  public let memoryUsedBytes: UInt64
  public let processorLoadFraction: Double
  public let sampledAt: Date

  public init(
    bootVolumeCapacityBytes: UInt64,
    bootVolumeAvailableBytes: UInt64,
    memoryPressure: MemoryPressure,
    memoryUsedBytes: UInt64,
    processorLoadFraction: Double,
    sampledAt: Date
  ) {
    self.bootVolumeCapacityBytes = bootVolumeCapacityBytes
    self.bootVolumeAvailableBytes = bootVolumeAvailableBytes
    self.memoryPressure = memoryPressure
    self.memoryUsedBytes = memoryUsedBytes
    // A fraction, always, so nothing downstream has to know whether it was
    // handed a percentage or a per core figure.
    self.processorLoadFraction = min(max(processorLoadFraction, 0), 1)
    self.sampledAt = sampledAt
  }

  /// What the boot volume has used, derived rather than sampled separately so
  /// the two figures cannot drift apart between readings.
  public var bootVolumeUsedBytes: UInt64 {
    bootVolumeCapacityBytes >= bootVolumeAvailableBytes
      ? bootVolumeCapacityBytes - bootVolumeAvailableBytes : 0
  }
}
