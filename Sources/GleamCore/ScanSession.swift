import Foundation

public enum GleamModule: String, Codable, Sendable, CaseIterable {
  case fullSweep, cleanup, protection, performance, applications, leftovers, diskMap
}

/// The live figures of one scan. `itemCount` counts path entries across the
/// findings emitted so far, not findings: a streaming scan emits a category as
/// several findings, so a count of findings would move with the engine's batch
/// size and mean nothing to the person reading the progress line.
public struct ScanCounters: Codable, Sendable, Equatable {
  public var filesSeen: UInt64
  public var bytesReclaimable: UInt64
  /// Path entries across the findings emitted so far. Rises by a finding's
  /// entry count in the same step that emits that finding.
  public var itemCount: UInt32

  public static let zero = ScanCounters(filesSeen: 0, bytesReclaimable: 0, itemCount: 0)

  public init(filesSeen: UInt64, bytesReclaimable: UInt64, itemCount: UInt32) {
    self.filesSeen = filesSeen
    self.bytesReclaimable = bytesReclaimable
    self.itemCount = itemCount
  }
}

/// Drives the three phase scan choreography. Phases only ever advance:
/// indeterminate, then determinate, then settling. An engine may skip
/// determinate on very fast scans, never go backwards.
public enum ScanPhase: Codable, Sendable, Equatable {
  case indeterminate
  case determinate(estimatedTotalFiles: UInt64)
  case settling
}

/// One scan run of one module. The unit the status scene and progress
/// choreography observe.
public struct ScanSession: Identifiable, Codable, Sendable, Equatable {
  public enum State: Codable, Sendable, Equatable {
    case running
    case completed
    case cancelled
    case failed(reason: String)
  }

  public let id: UUID
  public let module: GleamModule
  public let startedAt: Date
  public var finishedAt: Date?

  /// finishedAt is nil exactly while the state is running. Leaving the
  /// running state sets finishedAt in the same mutation; with no clock
  /// available (dates are always inputs), the fallback is startedAt, and
  /// callers holding the real finish time assign finishedAt explicitly.
  public var state: State {
    didSet {
      if state == .running {
        finishedAt = nil
      } else if oldValue == .running && finishedAt == nil {
        finishedAt = startedAt
      }
    }
  }

  /// Counters are monotonic within a session: an update never lowers any
  /// field. Assigning a lower value keeps the higher one.
  public var counters: ScanCounters {
    didSet {
      counters = ScanCounters(
        filesSeen: max(oldValue.filesSeen, counters.filesSeen),
        bytesReclaimable: max(oldValue.bytesReclaimable, counters.bytesReclaimable),
        itemCount: max(oldValue.itemCount, counters.itemCount)
      )
    }
  }

  public init(
    id: UUID,
    module: GleamModule,
    startedAt: Date,
    finishedAt: Date?,
    state: State,
    counters: ScanCounters
  ) {
    self.id = id
    self.module = module
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.state = state
    self.counters = counters
  }
}
