import SwiftUI

public enum GleamSpring: CaseIterable, Sendable {
  case snappy
  case gentle
  case lively

  public var response: Double {
    switch self {
    case .snappy: return 0.30
    case .gentle: return 0.55
    case .lively: return 0.40
    }
  }

  public var dampingFraction: Double {
    switch self {
    case .snappy: return 0.85
    case .gentle: return 0.90
    case .lively: return 0.70
    }
  }

  /// The SwiftUI animation for this token. When Reduce Motion is on, every
  /// spring resolves to a crossfade of the standard fade duration instead.
  public func animation(reduceMotion: Bool) -> Animation {
    if reduceMotion {
      return .easeInOut(duration: 0.25)
    }
    return .spring(response: response, dampingFraction: dampingFraction)
  }
}
