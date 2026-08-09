import SwiftUI

public enum GleamTypeToken: CaseIterable, Sendable {
  case display
  case title
  case body
  case caption
  case mono

  public var font: Font {
    switch self {
    case .display: return .system(size: 56, weight: .bold)
    case .title: return .system(size: 22, weight: .semibold)
    case .body: return .system(size: 13, weight: .regular)
    case .caption: return .system(size: 11, weight: .regular)
    case .mono: return .system(size: 12, weight: .regular, design: .monospaced)
    }
  }
}
