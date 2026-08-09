import GleamDesign

/// What the orb does for a mood, as data. Views interpret this; tests assert
/// on it directly.
public enum OrbAppearance: Sendable, Equatable {
  /// Idle, full motion: breathing scale at `period` with a C2 spring.
  case breathing(spring: GleamSpring, period: Duration, sheen: OrbSheen)
  /// Reduce Motion for every mood except scanning: a static gradient whose
  /// mood changes crossfade with a C2 fade token.
  case staticGradient(sheen: OrbSheen, moodChangeFade: GleamFade)
  /// Scanning, full motion: the shimmer band orbits the orb.
  case shimmerBand
  /// Scanning under Reduce Motion: a determinate progress ring.
  case determinateRing
  /// Result, full motion: one pulse with the given spring.
  case resultPulse(spring: GleamSpring)
  /// Clean sweep, full motion: the calm lustre bloom.
  case lustreBloom
}
