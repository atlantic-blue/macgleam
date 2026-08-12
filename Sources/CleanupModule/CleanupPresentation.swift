import Foundation
import GleamCore
import GleamHub
import Observation

/// What the cleanup pane holds that the module model does not: which review
/// categories the user folded away.
///
/// It sits here rather than in the view because the view is rebuilt every
/// time the rail comes back to Cleanup, and a folded category springing open
/// again is the user's reading position thrown away. The module model owns
/// the findings and the selection; this owns how they are shown.
@MainActor @Observable
public final class CleanupPresentation: ModuleStatePreserving {
  public private(set) var collapsedCategories: Set<FindingCategory> = []

  public init() {}

  public func isCollapsed(_ category: FindingCategory) -> Bool {
    collapsedCategories.contains(category)
  }

  public func toggleCollapse(_ category: FindingCategory) {
    if collapsedCategories.contains(category) {
      collapsedCategories.remove(category)
    } else {
      collapsedCategories.insert(category)
    }
  }

  /// Always a slot, never nil: leaving with everything expanded has to
  /// overwrite the last slot, or the fold from two visits ago comes back.
  public func stateSlot() -> ModuleStateSlot? {
    guard let payload = try? JSONEncoder().encode(Array(collapsedCategories)) else { return nil }
    return ModuleStateSlot(payload: payload)
  }

  /// A payload this module cannot read leaves it exactly as it was. The rail
  /// carries opaque bytes, so nothing at compile time proves a slot came from
  /// this version of this module, and the honest answer to a slot it cannot
  /// read is to keep what the user is looking at.
  public func restoreState(from slot: ModuleStateSlot) {
    guard
      let categories = try? JSONDecoder().decode([FindingCategory].self, from: slot.payload)
    else { return }
    collapsedCategories = Set(categories)
  }
}
