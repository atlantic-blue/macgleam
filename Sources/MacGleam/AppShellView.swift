import GleamDesign
import GleamHub
import SwiftUI

/// The window: the navigation rail down the left, the selected destination's
/// pane filling the rest, and a status bar along the bottom of that pane.
///
/// There is no top bar. The app's name and its settings both live in the
/// rail, so a bar carrying them again said everything twice.
///
/// Up and down move the rail selection through HubNavigationResolver. Return
/// and escape do not move it; they carry an intent the open pane interprets.
struct AppShellView: View {
  let model: HubModel
  let cleanup: CleanupDependencies
  let diskMap: DiskMapDependencies
  @State private var navigation: HubNavigationState
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @FocusState private var railHasKeyFocus: Bool

  init(
    model: HubModel,
    cleanup: CleanupDependencies,
    diskMap: DiskMapDependencies,
    initialSelection: HubDestination = HubNavigationState.initial.selection
  ) {
    self.model = model
    self.cleanup = cleanup
    self.diskMap = diskMap
    _navigation = State(
      initialValue: HubNavigationState(selection: initialSelection, moduleStateSlots: [:]))
  }

  var body: some View {
    HStack(spacing: 0) {
      SidebarView(
        selection: navigation.selection,
        orbMood: model.orbMood,
        onSelect: { select($0) }
      )
      VStack(spacing: 0) {
        paneSurface
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        StatusBarView(statusLine: model.statusLine, mood: model.orbMood)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(GleamColorToken.baseBackground.color(for: colorScheme))
    .focusable()
    .focused($railHasKeyFocus)
    .focusEffectDisabled()
    .onKeyPress(.upArrow) { handle(.arrowUp) }
    .onKeyPress(.downArrow) { handle(.arrowDown) }
    .onKeyPress(.leftArrow) { handle(.arrowLeft) }
    .onKeyPress(.rightArrow) { handle(.arrowRight) }
    .onKeyPress(.return) { handle(.return) }
    .onKeyPress(.escape) { handle(.escape) }
    .onAppear { railHasKeyFocus = true }
  }

  /// A module that has shipped shows its own surface. Everything else shows
  /// the standard pane, which says what the module will do and admits when it
  /// cannot do it yet.
  @ViewBuilder
  private var paneSurface: some View {
    let content = pane
    Group {
      switch navigation.selection {
      case .module(.cleanup) where content.action != nil:
        CleanupModuleView(
          model: cleanup.model, executor: cleanup.executor, idlePane: content)
      case .diskMap:
        DiskMapView(
          model: diskMap.model, executor: diskMap.executor, idlePane: content)
      default:
        ModulePaneView(pane: content, onActivate: {})
      }
    }
    .transition(paneTransition)
    .id(navigation.selection)
  }

  private var paneTransition: AnyTransition {
    if reduceMotion {
      return .opacity
    }
    return .opacity.combined(with: .offset(y: GleamSpacing.points(1)))
  }

  private var pane: ModulePane {
    ModulePaneResolver.pane(for: navigation.selection, summaries: model.summaries)
  }

  private func select(_ destination: HubDestination) {
    guard destination != navigation.selection else { return }
    withAnimation(GleamSpring.snappy.animation(reduceMotion: reduceMotion)) {
      navigation = HubNavigationState(
        selection: destination,
        moduleStateSlots: navigation.moduleStateSlots
      )
    }
  }

  private func handle(_ key: HubKeyEvent) -> KeyPress.Result {
    let transition = HubNavigationResolver.transition(navigation, applying: key)
    if transition.next != navigation {
      withAnimation(GleamSpring.snappy.animation(reduceMotion: reduceMotion)) {
        navigation = transition.next
      }
    }
    return .handled
  }
}
