import Foundation
import GleamHub

/// The four shapes a pane can take, named the way a person would describe one.
/// A pane either offers a primary action, or a way out, or both, or neither.
struct PaneShape: Sendable, CustomStringConvertible {
  let name: String
  let capabilities: HubPaneCapabilities

  var description: String { name }
}

let paneShapes: [PaneShape] = [
  PaneShape(
    name: "neither",
    capabilities: HubPaneCapabilities(hasPrimaryAction: false, hasDismissal: false)
  ),
  PaneShape(
    name: "primary action only",
    capabilities: HubPaneCapabilities(hasPrimaryAction: true, hasDismissal: false)
  ),
  PaneShape(
    name: "dismissal only",
    capabilities: HubPaneCapabilities(hasPrimaryAction: false, hasDismissal: true)
  ),
  PaneShape(
    name: "both",
    capabilities: HubPaneCapabilities(hasPrimaryAction: true, hasDismissal: true)
  ),
]

/// One cell of the matrix: where the person is, what they pressed, and what the
/// open pane can do about it.
struct KeyScenario: Sendable, CustomStringConvertible {
  let destination: HubDestination
  let key: HubKeyEvent
  let shape: PaneShape

  var capabilities: HubPaneCapabilities { shape.capabilities }

  /// Slots are carried so a scenario also proves nothing touches them.
  var state: HubNavigationState {
    makeNavigationState(selection: destination, slots: makeFullSlots())
  }

  var description: String { "\(destination.title) / \(key.rawValue) / \(shape.name)" }
}

/// Every destination in the rail, every key, every pane shape. Both ends of the
/// rail are in here because `railTopToBottom` is the whole rail.
let everyKeyScenario: [KeyScenario] = railTopToBottom.flatMap { destination in
  HubKeyEvent.allCases.flatMap { key in
    paneShapes.map { shape in
      KeyScenario(destination: destination, key: key, shape: shape)
    }
  }
}

extension HubPaneCapabilities {
  /// Whether the open pane can actually carry the intent out. The rail cannot
  /// know this, which is the whole reason capabilities are an input.
  func canRun(_ intent: HubIntent) -> Bool {
    switch intent {
    case .activatePrimaryAction: hasPrimaryAction
    case .dismiss: hasDismissal
    }
  }
}

/// The outcome C37 describes, worked out from rail order and the pane's shape
/// alone. This is a second reading of the contract rather than a call into the
/// resolver, so the table test compares two independent readings.
func contractedOutcome(for scenario: KeyScenario) -> HubKeyOutcome {
  switch scenario.key {
  case .arrowUp, .arrowDown:
    guard let row = railTopToBottom.firstIndex(of: scenario.destination) else { return .ignored }
    let target = scenario.key == .arrowUp ? row - 1 : row + 1
    guard railTopToBottom.indices.contains(target) else { return .ignored }
    return .moved(
      HubNavigationState(
        selection: railTopToBottom[target],
        moduleStateSlots: scenario.state.moduleStateSlots
      )
    )
  case .arrowLeft, .arrowRight:
    return .ignored
  case .return:
    return scenario.capabilities.hasPrimaryAction ? .acted(.activatePrimaryAction) : .ignored
  case .escape:
    return scenario.capabilities.hasDismissal ? .acted(.dismiss) : .ignored
  }
}
