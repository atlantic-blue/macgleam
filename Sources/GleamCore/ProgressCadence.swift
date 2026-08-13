import Foundation

/// How often a walk reports where it has got to.
///
/// A progress event does not stop at the engine. It crosses the stream to the
/// module, which redraws the interface, so one event per file makes drawing
/// the count the most expensive thing the scan does, and on a home directory
/// of a few hundred thousand files it takes the whole machine down with it.
///
/// So a walk reports every `step` files and once more when it finishes. The
/// last report is the one somebody is left looking at, and it carries the true
/// figure: a cadence may drop a report, never the final one.
public enum ProgressCadence {
  /// Chosen so a walk of a million files reports about four thousand times
  /// rather than a million, which is still far more often than an eye can
  /// follow, and small enough that a slow disk does not leave the count
  /// visibly frozen.
  public static let step: UInt64 = 256

  /// A gate counts the reports a walk makes, and a walk makes some that are
  /// not on the step: the one at the end, and one for each finding it emits.
  /// A scan of a large tree emits a few hundred findings, so this is wide
  /// enough that findings never trip the gate and narrow enough that a return
  /// to one report per file misses it by two orders of magnitude.
  public static let allowedExtraReports = 512

  /// Whether a walk that has seen this many files should report now.
  public static func reports(filesSeen: UInt64) -> Bool {
    filesSeen % step == 0
  }
}
