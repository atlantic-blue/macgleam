/// The streaming shape every engine's scan obeys. Two numbers, both asserted
/// against by name, so a change to either is a contract change and not a
/// tuning pass.
public enum ScanStreamPolicy {
  /// The most entries any one finding a scan emits may carry.
  ///
  /// 2,000 is chosen from both ends. Memory: an entry is a path string plus a
  /// byte count, on the order of 128 bytes on a real tree, so one open batch
  /// costs roughly 256 kilobytes and a catalogue of 50 rules matching
  /// concurrently holds under 13 megabytes against a 500 megabyte ceiling.
  /// Review: 110,003 matching files become a little under sixty findings
  /// rather than five unopenable ones, and 2,000 rows is still a list a person
  /// can scroll.
  ///
  /// Set shaped categories are exempt: a duplicate set or a similar photo set
  /// is never split, because a split would leave members in a finding whose
  /// category names a kept copy it does not contain.
  public static let maximumFindingEntries = 2_000

  /// How often, in files enumerated, a category that has emitted nothing yet
  /// flushes its first partial batch.
  ///
  /// 1,000 files is tens of milliseconds of walking on any disk the app
  /// supports, which is what puts the first finding at the start of a scan
  /// rather than the end. Only the first batch of a category uses it, so a
  /// scan of two million files does not emit two thousand fragments per
  /// category.
  public static let firstFindingCheckpointFiles: UInt64 = 1_000
}
