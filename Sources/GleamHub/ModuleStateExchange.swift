/// One move of the rail, with the departing module's state put away and the
/// arriving module's state handed back.
///
/// This is the only place a module is asked for a slot or given one, so the
/// round trip is one rule in one function rather than a pair of calls a view
/// can forget half of. Only a module has a slot: Disk Map and Settings are
/// rail chrome, so `HubModule` has no case for them and the store has no key
/// (C39).
@MainActor
public enum ModuleStateExchange {

  /// The navigation state to hold after moving to `destination`.
  ///
  /// Moving to the destination already selected is not a move: nothing is
  /// stored, nothing is restored and the state comes back identical.
  public static func navigate(
    _ state: HubNavigationState,
    to destination: HubDestination,
    preservers: [HubModule: any ModuleStatePreserving]
  ) -> HubNavigationState {
    guard destination != state.selection else { return state }
    let stored = storing(state, preservers: preservers)
    restore(at: destination, from: stored, preservers: preservers)
    return HubNavigationState(
      selection: destination,
      moduleStateSlots: stored.moduleStateSlots
    )
  }

  private static func storing(
    _ state: HubNavigationState,
    preservers: [HubModule: any ModuleStatePreserving]
  ) -> HubNavigationState {
    guard case .module(let module) = state.selection,
      let preserver = preservers[module],
      let slot = preserver.stateSlot()
    else { return state }
    return state.storingSlot(slot, for: module)
  }

  private static func restore(
    at destination: HubDestination,
    from state: HubNavigationState,
    preservers: [HubModule: any ModuleStatePreserving]
  ) {
    guard case .module(let module) = destination,
      let preserver = preservers[module],
      let slot = state.moduleStateSlots[module]
    else { return }
    preserver.restoreState(from: slot)
  }
}
