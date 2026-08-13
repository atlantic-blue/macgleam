import Foundation

/// A path written the way somebody reads it, for a line that changes several
/// times a second.
///
/// A scan that says only how many files it has read tells you it is busy. A
/// scan that names the file tells you where it is, which is the difference
/// between waiting and knowing. The name is the informative half, so it is the
/// half that survives when the line is too long: the middle goes, never the
/// end.
public enum PathDisplay {
  /// How much of a path a caption can hold before it starts wrapping.
  public static let defaultLimit = 56

  public static func short(
    _ path: AbsolutePath,
    home: AbsolutePath,
    limit: Int = defaultLimit
  ) -> String {
    let written = underHome(path, home: home)
    guard written.count > limit else { return written }
    let components = written.split(separator: "/", omittingEmptySubsequences: false)
    guard let name = components.last.map(String.init), components.count > 1 else {
      return written
    }
    let head = String(components[0])
    let ellipsis = "…"
    let joined = "\(head)/\(ellipsis)/\(name)"
    guard joined.count > limit else { return joined }
    return "\(ellipsis)/\(name)"
  }

  /// The home directory reads as a tilde, because a path that starts with
  /// somebody's own name tells them nothing they did not know.
  private static func underHome(_ path: AbsolutePath, home: AbsolutePath) -> String {
    if path == home { return "~" }
    guard path.isDescendant(of: home) else { return path.value }
    let consumed = home.value == "/" ? 1 : home.value.count + 1
    return "~/" + String(path.value.dropFirst(consumed))
  }
}
