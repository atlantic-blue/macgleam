public enum GleamFade: CaseIterable, Sendable {
  case micro
  case standard

  public var duration: Duration {
    switch self {
    case .micro: return .milliseconds(150)
    case .standard: return .milliseconds(250)
    }
  }
}
