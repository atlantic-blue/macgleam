import CoreGraphics

public enum GleamSpacing: Sendable {
  /// The grid unit. Always 8.
  public static let unit: CGFloat = 8

  /// Returns count multiplied by the grid unit. Traps on negative counts.
  public static func points(_ count: Int) -> CGFloat {
    precondition(count >= 0, "Spacing is a non negative multiple of the 8 point grid.")
    return CGFloat(count) * unit
  }
}
