import Foundation
import GleamHub

/// Every module enabled, the common case for tests that reach past the rail.
let allModulesEnabled = Set(HubModule.allCases)

/// The rail, top to bottom, as the contract fixes it.
let railTopToBottom: [HubDestination] =
  HubModule.allCases.map(HubDestination.module) + [.spaceLens, .settings]

/// The four arrow keys, for tests that walk the rail.
let arrowKeys: [HubKeyEvent] = [.arrowUp, .arrowDown, .arrowLeft, .arrowRight]

func makeNavigationState(
  selection: HubDestination = .module(.smartCare),
  slots: [HubModule: ModuleStateSlot] = [:]
) -> HubNavigationState {
  HubNavigationState(selection: selection, moduleStateSlots: slots)
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
