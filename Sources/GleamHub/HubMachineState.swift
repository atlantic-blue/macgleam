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
  public let cardFigures: [HubModule: String]
  public let enabledModules: Set<HubModule>
  public let now: Date

  public init(
    lastScanFinishedAt: Date?,
    reclaimableEstimateBytes: UInt64?,
    attentionReason: String?,
    cardFigures: [HubModule: String],
    enabledModules: Set<HubModule>,
    now: Date
  ) {
    self.lastScanFinishedAt = lastScanFinishedAt
    self.reclaimableEstimateBytes = reclaimableEstimateBytes
    self.attentionReason = attentionReason
    self.cardFigures = cardFigures
    self.enabledModules = enabledModules
    self.now = now
  }
}
