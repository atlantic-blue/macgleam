/// Where the user is, and every module's preserved state.
///
/// Exactly one destination is selected at all times, by construction: the
/// selection is a non optional `HubDestination` and no unselected state is
/// representable. Values are immutable; `storingSlot` is the only operation
/// anywhere that changes `moduleStateSlots`.
public struct HubNavigationState: Codable, Sendable, Equatable {
  public let selection: HubDestination
  public let moduleStateSlots: [HubModule: ModuleStateSlot]

  public init(selection: HubDestination, moduleStateSlots: [HubModule: ModuleStateSlot]) {
    self.selection = selection
    self.moduleStateSlots = moduleStateSlots
  }

  /// The first destination in rail order, with no stored slots.
  public static let initial = HubNavigationState(
    selection: HubDestination.allCases[0],
    moduleStateSlots: [:]
  )

  /// A copy with that module's slot replaced and everything else identical.
  public func storingSlot(
    _ slot: ModuleStateSlot,
    for module: HubModule
  ) -> HubNavigationState {
    var slots = moduleStateSlots
    slots[module] = slot
    return HubNavigationState(selection: selection, moduleStateSlots: slots)
  }
}
