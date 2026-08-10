/// The outcome of one key press: the next state, plus what the open pane is
/// being asked to do. `intent` is nil for every selection move and every key
/// the rail ignores.
public struct HubNavigationTransition: Sendable, Equatable {
  public let next: HubNavigationState
  public let intent: HubIntent?

  public init(next: HubNavigationState, intent: HubIntent?) {
    self.next = next
    self.intent = intent
  }
}

/// What a key press asks of the pane. The rail owns the selection; anything
/// beyond moving it belongs to whatever is on screen, so the resolver names
/// the intent and the pane decides what it means.
public enum HubIntent: String, CaseIterable, Sendable, Equatable {
  /// Run the pane's primary action: the scan, the clean, the check.
  case activatePrimaryAction
  /// Back out of whatever the pane has open: a drill down, a confirmation,
  /// a running scan.
  case dismiss
}
