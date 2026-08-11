/// The pure key transition. The whole rail navigation behaviour is this one
/// function, driven in tests without a view.
///
/// The rail is a single column in `HubDestination.allCases` order. Up and
/// down move the selection and clamp at the ends. Left and right do nothing:
/// there is no second column, and horizontal movement belongs to whatever
/// the pane is showing. Return and escape never move the selection; they
/// carry an intent for the pane to interpret. Every destination is
/// selectable, including a module that is not built yet, because the pane is
/// where a module says it has nothing to offer. No transition creates, drops
/// or alters a module state slot.
public enum HubNavigationResolver {

  public static func transition(
    _ state: HubNavigationState,
    applying key: HubKeyEvent
  ) -> HubNavigationTransition {
    switch key {
    case .arrowUp:
      return moving(state, by: -1)
    case .arrowDown:
      return moving(state, by: 1)
    case .arrowLeft, .arrowRight:
      return HubNavigationTransition(next: state, intent: nil)
    case .return:
      return HubNavigationTransition(next: state, intent: .activatePrimaryAction)
    case .escape:
      return HubNavigationTransition(next: state, intent: .dismiss)
    }
  }

  private static func moving(_ state: HubNavigationState, by step: Int) -> HubNavigationTransition {
    let rail = HubDestination.allCases
    guard let row = rail.firstIndex(of: state.selection) else {
      return HubNavigationTransition(next: state, intent: nil)
    }
    let clamped = min(max(row + step, 0), rail.count - 1)
    return HubNavigationTransition(
      next: HubNavigationState(
        selection: rail[clamped],
        moduleStateSlots: state.moduleStateSlots
      ),
      intent: nil
    )
  }
}
