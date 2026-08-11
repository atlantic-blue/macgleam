import CoreGraphics

public enum GleamSpacing: Sendable {
  /// The grid unit. Always 8.
  public static let unit: CGFloat = 8

  /// Returns count multiplied by the grid unit. Traps on negative counts.
  public static func points(_ count: Int) -> CGFloat {
    precondition(count >= 0, "Spacing is a non negative multiple of the 8 point grid.")
    return CGFloat(count) * unit
  }

  /// Returns count multiplied by half the grid unit. Traps on negative counts.
  ///
  /// Layout distances stay on the full grid. Padding inside a card or a
  /// control sits on this half step, which is where the specification places
  /// its 20 and 4 point insets.
  public static func half(_ count: Int) -> CGFloat {
    precondition(count >= 0, "Spacing is a non negative multiple of the 4 point half step.")
    return CGFloat(count) * unit / 2
  }
}
