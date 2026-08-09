/// Where the user is, and every module's preserved state.
///
/// Focus is always exactly one card when on the hub, by construction: the
/// hub case carries a non optional HubModule and no unfocused hub state is
/// representable. Values are immutable; `storingSlot` is the only operation
/// anywhere that changes `moduleStateSlots`.
public struct HubNavigationState: Codable, Sendable, Equatable {
  public enum Position: Codable, Sendable, Equatable {
    case hub(focus: HubModule)
    case module(HubModule)
  }

  public let position: Position
  public let moduleStateSlots: [HubModule: ModuleStateSlot]

  public init(position: Position, moduleStateSlots: [HubModule: ModuleStateSlot]) {
    self.position = position
    self.moduleStateSlots = moduleStateSlots
  }

  /// The hub with focus on the first card in `HubModule.allCases` order and
  /// no stored slots.
  public static let initial = HubNavigationState(
    position: .hub(focus: HubModule.allCases[0]),
    moduleStateSlots: [:]
  )

  /// A copy with that module's slot replaced and everything else identical.
  public func storingSlot(
    _ slot: ModuleStateSlot,
    for module: HubModule
  ) -> HubNavigationState {
    var slots = moduleStateSlots
    slots[module] = slot
    return HubNavigationState(position: position, moduleStateSlots: slots)
  }
}
