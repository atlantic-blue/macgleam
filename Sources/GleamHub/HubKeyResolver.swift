/// The shell's whole key decision, as one pure function: what a press does,
/// given where the rail is and what the open pane can do.
///
/// HubNavigationResolver owns the rail: it moves the selection and names the
/// intent a key carries. It cannot know whether anything is there to receive
/// that intent, because that depends on the pane on screen. This adds that
/// half, and it is the half that decides honesty. An intent nothing will run
/// is not an outcome, it is an ignored key: the press falls through and the
/// machine answers it, instead of being claimed by the rail and disappearing.
///
/// So the rule is one line. A press is claimed when it moves the rail or
/// when the pane can run its intent, and never otherwise. That includes an
/// arrow clamped at the end of the rail and the left and right arrows, which
/// the rail has never had anything to do with.
public enum HubKeyResolver {

  public static func outcome(
    _ state: HubNavigationState,
    applying key: HubKeyEvent,
    pane capabilities: HubPaneCapabilities
  ) -> HubKeyOutcome {
    let transition = HubNavigationResolver.transition(state, applying: key)
    if transition.next != state {
      return .moved(transition.next)
    }
    guard let intent = transition.intent, canRun(intent, capabilities) else {
      return .ignored
    }
    return .acted(intent)
  }

  private static func canRun(_ intent: HubIntent, _ capabilities: HubPaneCapabilities) -> Bool {
    switch intent {
    case .activatePrimaryAction:
      return capabilities.hasPrimaryAction
    case .dismiss:
      return capabilities.hasDismissal
    }
  }
}
