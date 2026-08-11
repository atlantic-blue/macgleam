/// What one key press actually does.
///
/// Three things can happen and no more. "Claimed, but nothing happened" is
/// not one of them: a press is claimed only when it moves the rail or asks
/// the pane to do something the pane can do. That leaves the swallowed key
/// unrepresentable rather than merely discouraged.
public enum HubKeyOutcome: Sendable, Equatable {
  /// The rail moved. A selection move never carries an intent.
  case moved(HubNavigationState)
  /// The selection stands and the open pane is asked to do this.
  case acted(HubIntent)
  /// There is nothing to do, so the press is left unclaimed and whatever
  /// sits behind the shell answers it.
  case ignored

  /// True exactly when the press does something. A view returns
  /// `KeyPress.Result.handled` for this and `.ignored` otherwise.
  public var isHandled: Bool {
    if case .ignored = self { return false }
    return true
  }

  /// The intent the pane is being asked to run, or nil when there is none.
  public var intent: HubIntent? {
    guard case .acted(let intent) = self else { return nil }
    return intent
  }

  /// Where the rail sits after the press: the moved state, or the state
  /// that went in, unchanged.
  public func nextState(from state: HubNavigationState) -> HubNavigationState {
    guard case .moved(let next) = self else { return state }
    return next
  }
}

/// What the pane in front of the user can do, reduced to the two facts the
/// shell needs to decide a key.
///
/// The shell derives these from the same source the pane renders from, so a
/// capability is present exactly when there is a control on screen and
/// running it does something.
public struct HubPaneCapabilities: Sendable, Equatable {
  /// The pane draws a primary control and pressing it does work: the scan,
  /// the map, the check. False for a module that is not built yet.
  public let hasPrimaryAction: Bool
  /// The pane has something to back out of, and backing out destroys
  /// nothing: a drilled in level, a sheet. Stopping running work is not a
  /// dismissal, so it never sets this.
  public let hasDismissal: Bool

  public init(hasPrimaryAction: Bool, hasDismissal: Bool) {
    self.hasPrimaryAction = hasPrimaryAction
    self.hasDismissal = hasDismissal
  }
}
