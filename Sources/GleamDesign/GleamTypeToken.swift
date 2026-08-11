import CoreGraphics
import SwiftUI

/// The eight text roles. Each carries its own size, weight, tracking and line
/// height, so a view applies a role and never restates a number.
///
/// The specification names Inter and JetBrains Mono. It says why: a web page
/// cannot use SF Pro. A native app can, and SF Pro is what Inter was standing
/// in for, so the roles resolve to the system faces.
public enum GleamTypeToken: CaseIterable, Sendable {
  case display
  case heading
  case title
  case headline
  case label
  case body
  case caption
  case mono

  public var size: CGFloat {
    switch self {
    case .display: return 56
    case .heading: return 34
    case .title: return 22
    case .headline: return 15
    case .label: return 14
    case .body: return 13
    case .caption: return 11
    case .mono: return 12
    }
  }

  public var weight: Font.Weight {
    switch self {
    case .display: return .bold
    case .heading, .title, .headline: return .semibold
    case .label, .caption: return .medium
    case .body, .mono: return .regular
    }
  }

  /// Letter spacing in points. The specification tightens only the two
  /// largest roles, as a display face wants and a reading size does not.
  public var tracking: CGFloat {
    switch self {
    case .display: return -0.02 * size
    case .heading, .title: return -0.01 * size
    case .headline, .label, .body, .caption, .mono: return 0
    }
  }

  /// The gap SwiftUI adds between lines, which is the specified line height
  /// less the point size.
  public var lineSpacing: CGFloat {
    lineHeight - size
  }

  private var lineHeight: CGFloat {
    switch self {
    case .display: return 64
    case .heading: return 40
    case .title: return 28
    case .headline, .label: return 20
    case .body: return 18
    case .caption: return 14
    case .mono: return 16
    }
  }

  public var font: Font {
    if self == .mono {
      return .system(size: size, weight: weight, design: .monospaced)
    }
    return .system(size: size, weight: weight)
  }
}

extension View {
  /// Applies a text role whole: its face, its tracking and its line height.
  public func gleamType(_ role: GleamTypeToken) -> some View {
    font(role.font)
      .tracking(role.tracking)
      .lineSpacing(role.lineSpacing)
  }
}
