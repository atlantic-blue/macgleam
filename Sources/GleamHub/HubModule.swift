/// The six hub cards in their fixed hexagonal order. The order of `allCases`
/// is the layout order and is part of the contract; the hub never reorders at
/// runtime. Disk Map and Settings are hub chrome, not cards.
public enum HubModule: String, CaseIterable, Codable, Sendable, Equatable {
  case fullSweep
  case cleanup
  case protection
  case performance
  case applications
  case leftovers
}
