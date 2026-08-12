import CleanupModule
import DiskMapModule
import GleamDesign
import GleamHub
import SwiftUI

/// The window: the navigation rail down the left, the selected destination's
/// pane filling the rest, and a status bar along the bottom of that pane.
///
/// There is no top bar. The app's name and its settings both live in the
/// rail, so a bar carrying them again said everything twice.
///
/// Every key press resolves through HubKeyResolver. Up and down move the
/// rail. Return runs the primary control of the pane on screen, and escape
/// backs out of a drilled in level of the map. Anything the shell cannot
/// act on it leaves alone, so the press reaches the machine and the user
/// gets the answer a key with nothing behind it should get.
struct AppShellView: View {
  let model: HubModel
  let cleanup: CleanupDependencies
  let diskMap: DiskMapDependencies
  let protection: ProtectionDependencies
  let fullSweep: FullSweepDependencies
  @State private var navigation: HubNavigationState
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @FocusState private var railHasKeyFocus: Bool

  init(
    model: HubModel,
    cleanup: CleanupDependencies,
    diskMap: DiskMapDependencies,
    protection: ProtectionDependencies,
    fullSweep: FullSweepDependencies,
    initialSelection: HubDestination = HubNavigationState.initial.selection
  ) {
    self.model = model
    self.cleanup = cleanup
    self.diskMap = diskMap
    self.protection = protection
    self.fullSweep = fullSweep
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
          model: cleanup.model,
          executor: cleanup.executor,
          presentation: cleanup.presentation,
          idlePane: content)
      case .module(.fullSweep) where content.action != nil:
        FullSweepModuleView(model: fullSweep.model, idlePane: content)
      case .module(.protection) where content.action != nil:
        ProtectionModuleView(
          model: protection.model, safetyNet: protection.safetyNet, idlePane: content)
      case .diskMap:
        DiskMapView(
          model: diskMap.model, executor: diskMap.executor, idlePane: content)
      default:
        ModulePaneView(pane: content, onActivate: { primaryAction?() })
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

  /// Every move goes through here, whether it came from the pointer or from
  /// an arrow key, so a module's state is put away and handed back exactly
  /// once per move and neither path can forget half of the round trip.
  private func select(_ destination: HubDestination) {
    guard destination != navigation.selection else { return }
    let next = ModuleStateExchange.navigate(
      navigation, to: destination, preservers: preservers)
    withAnimation(GleamSpring.snappy.animation(reduceMotion: reduceMotion)) {
      navigation = next
    }
  }

  /// The modules that keep anything worth carrying across a move. A module
  /// missing from here preserves nothing, which is the honest answer for the
  /// five that are not built yet.
  private var preservers: [HubModule: any ModuleStatePreserving] {
    [.cleanup: cleanup.presentation]
  }

  private func handle(_ key: HubKeyEvent) -> KeyPress.Result {
    switch HubKeyResolver.outcome(navigation, applying: key, pane: paneCapabilities) {
    case .moved(let next):
      select(next.selection)
      return .handled
    case .acted(let intent):
      run(intent)
      return .handled
    case .ignored:
      return .ignored
    }
  }

  /// What the pane on screen can be asked to do. Both facts come from the
  /// same properties that carry out the work, so the shell cannot claim a
  /// key it has nothing to run.
  private var paneCapabilities: HubPaneCapabilities {
    HubPaneCapabilities(
      hasPrimaryAction: primaryAction != nil,
      hasDismissal: dismissAction != nil
    )
  }

  private func run(_ intent: HubIntent) {
    switch intent {
    case .activatePrimaryAction:
      primaryAction?()
    case .dismiss:
      dismissAction?()
    }
  }

  /// What the pane's primary control does right now, and nil when it draws
  /// none. This mirrors `paneSurface`: a module that is not built shows a
  /// note rather than a control, and once a module is working it has put up
  /// its own screens, which own their own keys. So the shell offers the
  /// entry action and nothing else.
  private var primaryAction: (() -> Void)? {
    switch navigation.selection {
    case .module(.cleanup) where pane.action != nil:
      guard case .idle = cleanup.model.state else { return nil }
      return { cleanup.model.startScan() }
    case .module(.fullSweep) where pane.action != nil:
      guard case .idle = fullSweep.model.state else { return nil }
      return { fullSweep.model.startSweep() }
    case .module(.protection) where pane.action != nil:
      guard case .idle = protection.model.state else { return nil }
      return { protection.model.startScan() }
    case .diskMap:
      guard case .idle = diskMap.model.state else { return nil }
      return { diskMap.model.startMapping(volume: DiskMapView.defaultVolume) }
    default:
      return nil
    }
  }

  /// Escape backs out one level of the map, which is exactly what the
  /// breadcrumb's own chevron does and destroys nothing. It is the only
  /// dismissal in the shell: stopping a running scan throws the work away,
  /// and a key pressed by accident is no place for that.
  private var dismissAction: (() -> Void)? {
    guard navigation.selection == .diskMap else { return nil }
    let map: DiskMapState
    switch diskMap.model.state {
    case .mapping(let state), .browsing(let state):
      map = state
    default:
      return nil
    }
    guard map.focusPath != map.volume else { return nil }
    return { drillOutOfMap() }
  }

  private func drillOutOfMap() {
    withAnimation(DiskMapZoom.animation(for: .zoomOut, reduceMotion: reduceMotion)) {
      _ = diskMap.model.drillOut()
    }
  }
}
