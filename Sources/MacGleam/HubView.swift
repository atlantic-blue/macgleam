import GleamDesign
import GleamHub
import SwiftUI

/// The hub window: the orb centre stage, the status line under it, and the
/// six module cards flanking it as a hexagon in `HubModule.allCases` order.
/// Arrow keys, Return and Escape drive HubNavigationResolver; entering a
/// module zooms its card to fill the window with the resolved appearance,
/// the hub scaling and blurring behind it.
struct HubView: View {
  let model: HubModel
  let cleanup: CleanupDependencies
  let diskMap: DiskMapDependencies
  @State private var navigation = HubNavigationState.initial
  @State private var isDiskMapOpen = false
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var zoomNamespace
  @FocusState private var hubHasKeyFocus: Bool

  private static let backgroundScaleWhileOpen: CGFloat = 0.94
  private static let backgroundBlurWhileOpen: CGFloat = 8
  private static let hexagonOffset = GleamSpacing.points(4)

  var body: some View {
    ZStack {
      hubScene
        .scaleEffect(isChromeOrModuleOpen ? Self.backgroundScaleWhileOpen : 1)
        .blur(radius: isChromeOrModuleOpen ? Self.backgroundBlurWhileOpen : 0)
      if let module = openModule {
        openModuleView(module)
      }
      if isDiskMapOpen {
        diskMapSurface
      }
    }
    .overlay(alignment: .topTrailing) {
      if !isDiskMapOpen && openModule == nil {
        diskMapControl
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(GleamColorToken.baseBackground.color(for: colorScheme))
    .focusable()
    .focused($hubHasKeyFocus)
    .focusEffectDisabled()
    .onKeyPress(.upArrow) { handle(.arrowUp) }
    .onKeyPress(.downArrow) { handle(.arrowDown) }
    .onKeyPress(.leftArrow) { handle(.arrowLeft) }
    .onKeyPress(.rightArrow) { handle(.arrowRight) }
    .onKeyPress(.return) { handle(.return) }
    .onKeyPress(.escape) { handle(.escape) }
    .onAppear { hubHasKeyFocus = true }
  }

  private var hubScene: some View {
    HStack(spacing: GleamSpacing.points(4)) {
      cardColumn(Array(model.cards.prefix(3)), pushingMiddleTowards: -1)
      statusScene
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      cardColumn(Array(model.cards.suffix(3)), pushingMiddleTowards: 1)
    }
    .padding(GleamSpacing.points(4))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var statusScene: some View {
    VStack(spacing: GleamSpacing.points(3)) {
      OrbView(mood: model.orbMood)
      Text(model.statusLine)
        .font(GleamTypeToken.body.font)
        .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
        .multilineTextAlignment(.center)
    }
  }

  /// One column of three cards. The middle card is pushed outward, away from
  /// the orb, so the six cards read as a hexagon around it.
  private func cardColumn(
    _ cards: [HubCard],
    pushingMiddleTowards side: CGFloat
  ) -> some View {
    VStack(spacing: GleamSpacing.points(3)) {
      ForEach(Array(cards.enumerated()), id: \.element.id) { row, card in
        matchedCard(card)
          .offset(x: row == 1 ? side * Self.hexagonOffset : 0)
      }
    }
    .frame(width: 220)
  }

  @ViewBuilder
  private func matchedCard(_ card: HubCard) -> some View {
    let view = HubCardView(
      card: card,
      isFocused: focusedModule == card.module,
      onEnter: { enterByClick(card.module) }
    )
    if reduceMotion {
      view
    } else if openModule == card.module {
      view.opacity(0)
    } else {
      view.matchedGeometryEffect(id: card.module, in: zoomNamespace)
    }
  }

  @ViewBuilder
  private func openModuleView(_ module: HubModule) -> some View {
    let view = moduleSurface(module)
    if reduceMotion {
      view.transition(.opacity)
    } else {
      view.matchedGeometryEffect(id: module, in: zoomNamespace)
    }
  }

  @ViewBuilder
  private func moduleSurface(_ module: HubModule) -> some View {
    if module == .cleanup {
      CleanupModuleView(model: cleanup.model, executor: cleanup.executor)
    } else {
      ModulePlaceholderView(card: card(for: module))
    }
  }

  private var openModule: HubModule? {
    if case .module(let module) = navigation.position { return module }
    return nil
  }

  private var isChromeOrModuleOpen: Bool {
    openModule != nil || isDiskMapOpen
  }

  /// Disk Map lives outside the six cards, as hub chrome: a corner
  /// control that zooms the map surface over the hub with the same zoom
  /// language the cards use.
  private var diskMapControl: some View {
    Button {
      withAnimation(zoomAnimation(for: .zoomIn)) {
        isDiskMapOpen = true
      }
    } label: {
      HStack(spacing: GleamSpacing.points(1) / 2) {
        Image(systemName: "circle.grid.2x2")
        Text("Disk Map")
      }
      .font(GleamTypeToken.caption.font)
      .foregroundStyle(GleamColorToken.textSecondary.color(for: colorScheme))
      .padding(.horizontal, GleamSpacing.points(2))
      .padding(.vertical, GleamSpacing.points(1))
      .background(
        Capsule().fill(GleamColorToken.surface.color(for: colorScheme))
      )
    }
    .buttonStyle(.plain)
    .padding(GleamSpacing.points(2))
    .help("The disk map: see where your space went.")
  }

  @ViewBuilder
  private var diskMapSurface: some View {
    let surface = DiskMapView(
      model: diskMap.model,
      executor: diskMap.executor,
      onClose: { closeDiskMap() }
    )
    if reduceMotion {
      surface.transition(.opacity)
    } else {
      surface.transition(.scale(scale: 0.94).combined(with: .opacity))
    }
  }

  private func closeDiskMap() {
    withAnimation(zoomAnimation(for: .zoomOut)) {
      isDiskMapOpen = false
    }
  }

  private var focusedModule: HubModule? {
    if case .hub(let focus) = navigation.position { return focus }
    return nil
  }

  private var enabledModules: Set<HubModule> {
    Set(model.cards.filter(\.isEnabled).map(\.module))
  }

  private func card(for module: HubModule) -> HubCard {
    model.cards.first { $0.module == module }
      ?? HubCard(module: module, figure: "", isEnabled: true)
  }

  private func handle(_ key: HubKeyEvent) -> KeyPress.Result {
    if isDiskMapOpen {
      if key == .escape { closeDiskMap() }
      return .handled
    }
    perform(
      HubNavigationResolver.transition(
        navigation,
        applying: key,
        enabledModules: enabledModules
      )
    )
    return .handled
  }

  /// Clicking a card enters it through the same resolver path as Return:
  /// focus moves to the clicked card, then a Return transition applies.
  private func enterByClick(_ module: HubModule) {
    guard case .hub = navigation.position else { return }
    let focused = HubNavigationState(
      position: .hub(focus: module),
      moduleStateSlots: navigation.moduleStateSlots
    )
    navigation = focused
    perform(
      HubNavigationResolver.transition(
        focused,
        applying: .return,
        enabledModules: enabledModules
      )
    )
  }

  private func perform(_ transition: HubNavigationTransition) {
    guard transition.next != navigation else { return }
    let animation: Animation
    if let zoom = transition.zoom {
      animation = zoomAnimation(for: zoom.direction)
    } else {
      animation = GleamSpring.snappy.animation(reduceMotion: reduceMotion)
    }
    withAnimation(animation) {
      navigation = transition.next
    }
  }

  private func zoomAnimation(for direction: HubZoomDirection) -> Animation {
    switch HubZoomResolver.appearance(for: direction, reduceMotion: reduceMotion) {
    case .matchedGeometry(let spring):
      return spring.animation(reduceMotion: false)
    case .crossfade(let fade):
      return .easeInOut(duration: seconds(of: fade.duration))
    }
  }

  private func seconds(of duration: Duration) -> Double {
    Double(duration.components.seconds)
      + Double(duration.components.attoseconds) / 1e18
  }
}
