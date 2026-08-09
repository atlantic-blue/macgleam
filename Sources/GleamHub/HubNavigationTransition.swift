/// The outcome of one key press: the next state, plus the zoom the view
/// must perform when a module boundary was crossed. `zoom` is non nil
/// exactly when `next` is on the other side of a module boundary from the
/// input state: nil for every focus move and every ignored key.
public struct HubNavigationTransition: Sendable, Equatable {
  public let next: HubNavigationState
  public let zoom: HubZoom?

  public init(next: HubNavigationState, zoom: HubZoom?) {
    self.next = next
    self.zoom = zoom
  }
}

/// A matched geometry zoom, as data: which module and which way. Views
/// interpret it; its animation resolves through HubZoomResolver.
public struct HubZoom: Sendable, Equatable {
  public let module: HubModule
  public let direction: HubZoomDirection

  public init(module: HubModule, direction: HubZoomDirection) {
    self.module = module
    self.direction = direction
  }
}

public enum HubZoomDirection: String, CaseIterable, Sendable, Equatable {
  case zoomIn
  case zoomOut
}
