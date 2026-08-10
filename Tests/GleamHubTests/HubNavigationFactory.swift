import Foundation
import GleamHub

/// Every module enabled, the common case for navigation tests.
let allModulesEnabled = Set(HubModule.allCases)

/// The spatial card layout from the contract: two columns of three flanking
/// the orb, in HubModule.allCases order. Left column top to bottom, then
/// right column top to bottom.
let leftColumnTopToBottom: [HubModule] = [.fullSweep, .cleanup, .protection]
let rightColumnTopToBottom: [HubModule] = [.performance, .applications, .leftovers]

/// The four arrow keys, for tests that walk without entering or leaving.
let arrowKeys: [HubKeyEvent] = [.arrowUp, .arrowDown, .arrowLeft, .arrowRight]

func makeNavigationState(
  position: HubNavigationState.Position = .hub(focus: .fullSweep),
  slots: [HubModule: ModuleStateSlot] = [:]
) -> HubNavigationState {
  HubNavigationState(position: position, moduleStateSlots: slots)
}

func makeSlot(_ text: String) -> ModuleStateSlot {
  ModuleStateSlot(payload: Data(text.utf8))
}

/// One distinct payload per module so a pass through check can see every slot.
func makeFullSlots() -> [HubModule: ModuleStateSlot] {
  Dictionary(
    uniqueKeysWithValues: HubModule.allCases.map { module in
      (module, makeSlot("slot payload for \(module.rawValue)"))
    }
  )
}

/// Every representable position: the six hub focuses and the six modules.
func makeAllPositions() -> [HubNavigationState.Position] {
  HubModule.allCases.map { .hub(focus: $0) } + HubModule.allCases.map { .module($0) }
}

/// Enabled set shapes the transition must be total over: nothing enabled,
/// everything enabled, and a mixed set.
func makeEnabledVariants() -> [Set<HubModule>] {
  [
    [],
    Set(HubModule.allCases),
    [.fullSweep, .protection, .leftovers],
  ]
}

func isInsideModule(_ state: HubNavigationState) -> Bool {
  if case .module = state.position { return true }
  return false
}

/// Deterministic pseudo random source so property style tests are repeatable
/// from a seed. SplitMix64 mixing, no platform randomness.
struct SeededGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var mixed = state
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
    return mixed ^ (mixed >> 31)
  }
}

/// A repeatable key sequence drawn from the given keys.
func makeKeySequence(
  seed: UInt64,
  length: Int,
  drawnFrom keys: [HubKeyEvent]
) -> [HubKeyEvent] {
  var generator = SeededGenerator(seed: seed)
  return (0..<length).map { _ in
    keys[Int(generator.next() % UInt64(keys.count))]
  }
}
