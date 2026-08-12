/// A module surface that keeps state the rail would otherwise destroy.
///
/// The rail tears the open pane down on the way out and builds a fresh one on
/// the way back, so anything the pane owns rather than the module model owns
/// is gone unless the module writes it into a slot. The rail carries bytes
/// and never reads them: what a slot means is the module's business, and so
/// is deciding that a payload it cannot decode changes nothing.
@MainActor
public protocol ModuleStatePreserving: AnyObject {
  /// The state to carry forward, or nil for a module that preserves nothing
  /// at all. Nil is a standing answer, not "nothing has changed": a module
  /// that answers a slot must answer one every time, so leaving with an empty
  /// state overwrites the last slot rather than letting a stale one return.
  func stateSlot() -> ModuleStateSlot?

  /// Take back what this module wrote on the way out. Called only when a
  /// slot exists, so an absent slot leaves the module at its own defaults.
  func restoreState(from slot: ModuleStateSlot)
}
