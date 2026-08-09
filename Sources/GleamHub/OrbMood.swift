/// The orb's five moods. Closed from the start so the appearance mapping is
/// total. s0b reaches only the two idle moods through HubModel; the rest
/// become reachable when Smart Care wires in, by extending the derivation
/// inputs, never by adding cases.
public enum OrbMood: String, CaseIterable, Sendable, Equatable {
  case idleHealthy
  case idleAttention
  case scanning
  case result
  case cleanSweep
}
