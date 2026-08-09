/// The orb's surface tint. Exactly two cases and neither is the dangerous
/// colour: an alarmed orb is unrepresentable by construction.
public enum OrbSheen: String, Sendable, Equatable {
  case iridescent
  case warmedToReview
}
