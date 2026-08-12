import Foundation

/// Everything the hub shell derives its presentation from. A plain value so
/// tests construct any machine condition directly.
///
/// `now` is the instant all recency wording is reckoned against. It is always
/// an input; nothing downstream of this type reads a clock.
/// `attentionReason`, when present, is one plain sentence naming the top
/// issue, suitable for display as the status line.
public struct HubMachineState: Sendable, Equatable {
  public let lastScanFinishedAt: Date?
  public let reclaimableEstimateBytes: UInt64?
  public let attentionReason: String?
  public let moduleFigures: [HubModule: String]
  public let enabledModules: Set<HubModule>
  /// What the Full Sweep is doing, and nil when it is doing nothing. It is
  /// the only input that reaches the orb's three active moods: everything
  /// else the hub knows describes a machine at rest.
  public let sweepActivity: HubSweepActivity?
  public let now: Date

  public init(
    lastScanFinishedAt: Date?,
    reclaimableEstimateBytes: UInt64?,
    attentionReason: String?,
    moduleFigures: [HubModule: String],
    enabledModules: Set<HubModule>,
    sweepActivity: HubSweepActivity? = nil,
    now: Date
  ) {
    self.lastScanFinishedAt = lastScanFinishedAt
    self.reclaimableEstimateBytes = reclaimableEstimateBytes
    self.attentionReason = attentionReason
    self.moduleFigures = moduleFigures
    self.enabledModules = enabledModules
    self.sweepActivity = sweepActivity
    self.now = now
  }
}

/// What a Full Sweep is doing, as the hub sees it.
///
/// Three states and no more, because these are exactly the three the orb has
/// moods for. A sweep that was running, found nothing and finished is a clean
/// sweep rather than a result with a zero in it: the empty answer is the good
/// one and the interface says so.
public enum HubSweepActivity: Sendable, Equatable {
  /// A sweep is running. The figure is what it has found so far, and it only
  /// ever goes up.
  case scanning(bytesReclaimable: UInt64)
  /// A sweep finished and found something.
  case result(bytesReclaimable: UInt64, issueCount: UInt32)
  /// A sweep finished and found nothing at all.
  case cleanSweep
}
