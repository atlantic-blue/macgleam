/// The pure key transition. The whole hub navigation behaviour is this one
/// function, driven in tests without a view.
///
/// The six cards form two columns of three flanking the orb, in
/// `HubModule.allCases` order: left column top to bottom is smartCare,
/// cleanup, protection; right column top to bottom is performance,
/// applications, myClutter. Vertical moves clamp at column ends, horizontal
/// moves swap to the same row of the other column and clamp when focus is
/// already in the pressed direction's column. Return enters only enabled
/// modules with a zoomIn; escape inside a module returns to the hub with
/// focus restored to the entered card and a zoomOut. No transition creates,
/// drops or alters a module state slot.
public enum HubNavigationResolver {
  private static let columnLength = 3
  private static let leftColumn = Array(HubModule.allCases.prefix(columnLength))
  private static let rightColumn = Array(HubModule.allCases.suffix(columnLength))

  public static func transition(
    _ state: HubNavigationState,
    applying key: HubKeyEvent,
    enabledModules: Set<HubModule>
  ) -> HubNavigationTransition {
    switch state.position {
    case .hub(let focus):
      return hubTransition(state, focus: focus, key: key, enabledModules: enabledModules)
    case .module(let module):
      return moduleTransition(state, module: module, key: key)
    }
  }

  private static func hubTransition(
    _ state: HubNavigationState,
    focus: HubModule,
    key: HubKeyEvent,
    enabledModules: Set<HubModule>
  ) -> HubNavigationTransition {
    switch key {
    case .arrowUp, .arrowDown, .arrowLeft, .arrowRight:
      return HubNavigationTransition(
        next: HubNavigationState(
          position: .hub(focus: arrowTarget(from: focus, key: key)),
          moduleStateSlots: state.moduleStateSlots
        ),
        zoom: nil
      )
    case .return:
      guard enabledModules.contains(focus) else {
        return HubNavigationTransition(next: state, zoom: nil)
      }
      return HubNavigationTransition(
        next: HubNavigationState(
          position: .module(focus),
          moduleStateSlots: state.moduleStateSlots
        ),
        zoom: HubZoom(module: focus, direction: .zoomIn)
      )
    case .escape:
      return HubNavigationTransition(next: state, zoom: nil)
    }
  }

  private static func moduleTransition(
    _ state: HubNavigationState,
    module: HubModule,
    key: HubKeyEvent
  ) -> HubNavigationTransition {
    guard key == .escape else {
      return HubNavigationTransition(next: state, zoom: nil)
    }
    return HubNavigationTransition(
      next: HubNavigationState(
        position: .hub(focus: module),
        moduleStateSlots: state.moduleStateSlots
      ),
      zoom: HubZoom(module: module, direction: .zoomOut)
    )
  }

  private static func arrowTarget(from focus: HubModule, key: HubKeyEvent) -> HubModule {
    let isLeft = leftColumn.contains(focus)
    let column = isLeft ? leftColumn : rightColumn
    guard let row = column.firstIndex(of: focus) else { return focus }
    switch key {
    case .arrowUp:
      return column[max(row - 1, 0)]
    case .arrowDown:
      return column[min(row + 1, columnLength - 1)]
    case .arrowLeft:
      return isLeft ? focus : leftColumn[row]
    case .arrowRight:
      return isLeft ? rightColumn[row] : focus
    case .return, .escape:
      return focus
    }
  }
}
