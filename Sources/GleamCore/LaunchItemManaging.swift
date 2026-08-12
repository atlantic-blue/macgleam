import Foundation

/// Inventory and state changes for login and background items, per owning app.
///
/// Guarantees:
/// - `list` attributes every item to its owning app where the owner is
///   resolvable, with the item's kind, scope, current enabled state and the
///   path that can be revealed in Finder. An item whose owner cannot be
///   resolved is still listed.
/// - `setEnabled` disables or enables, never deletes, and returns the change
///   it made, recording the prior state so re enabling is one click and
///   survives relaunch.
/// - User scope items change in process; system scope items route through the
///   helper. The caller does not choose: the implementation routes by the
///   scope it reads from the current inventory, so a stale caller cannot
///   decide which side of the privileged boundary a change lands on.
/// - Every change is attributable, and the type system is what makes it so.
///   The requirement below carries no attribution default and
///   `ChangeAttribution` has no case meaning none, so nothing holding this
///   protocol, the executor above all, can make a change without saying which
///   plan operation it is running.
/// - Changing an item that is not in the current inventory throws
///   `itemNotFound` and changes nothing.
public protocol LaunchItemManaging: Sendable {
  func list() async throws -> [LaunchItem]
  func setEnabled(
    _ enabled: Bool,
    item: LaunchItemID,
    attribution: ChangeAttribution
  ) async throws -> LaunchItemChange
}

/// The inventory source. Reads registrations and their current state and
/// mutates nothing, which is why listing is a separate protocol from changing:
/// a type that can only list cannot be handed to anything that changes an
/// item, and handing one to a scan is what makes "listing login items cannot
/// change one" a fact about the types rather than a promise.
public protocol LaunchItemEnumerating: Sendable {
  func items() async throws -> [LaunchItem]
}

/// The in process side, for user scope items only. It takes no attribution:
/// nothing privileged happens here and no log outside this process records it,
/// so the attribution the manager was given is dropped on this path
/// deliberately, which is why it is absent from the signature rather than
/// ignored in the body. It performs the change and nothing else; the record of
/// what the item was is the manager's to mint, from the inventory it has just
/// read and the clock it was built with.
public protocol UserScopeLaunchItemChanging: Sendable {
  func setEnabled(_ enabled: Bool, item: LaunchItemID) async throws
}

/// The privileged side, for system scope items only. It sends C30's
/// `setLaunchItemEnabled` to the helper and maps the reply onto this file's
/// failures. It is the only place in the app that can change a system scope
/// registration. The change it returns is the one the helper made and reported
/// back, so its instant is the helper's rather than this process's.
///
/// It carries the attribution across the boundary rather than dropping it, and
/// the parameter has no default, so a privileged change nobody asked for
/// cannot be written. The helper echoes the attribution's correlation
/// identifier, which is how a refusal reconciles to the plan operation or to
/// the direct change that caused it.
public protocol PrivilegedLaunchItemChanging: Sendable {
  func setLaunchItemEnabled(
    _ enabled: Bool,
    item: LaunchItemID,
    attribution: ChangeAttribution
  ) async throws -> LaunchItemChange
}

/// The two sides one implementation needs to serve user scope items: it lists
/// what is there and it changes what a person asked to change. Written as the
/// composition rather than as a third protocol so that the inventory stays
/// usable on its own, and so a type that only enumerates cannot stand in here.
public typealias LaunchItemSourcing = LaunchItemEnumerating & UserScopeLaunchItemChanging

/// The inventory boundary, under the name the Performance module uses for it.
public typealias LaunchItemInventorying = LaunchItemEnumerating

/// The record store boundary, under the name the Performance module uses for
/// it.
public typealias LaunchItemChangeStoring = LaunchItemChangeRecording

/// The store of prior state. Lives beside the SafetyNet manifest, so it
/// survives relaunch.
///
/// Guarantees:
/// - `record` is append only. Nothing is deleted or rewritten, so a change
///   somebody later reverses leaves both records and the state before the
///   first of them is still readable.
/// - `recordedChanges` returns that history in the order it was written, so a
///   row can say what MacGleam changed and when, and re enabling can restore
///   what the item was before MacGleam first touched it rather than blindly
///   enabling it.
/// - A missing or corrupt store reads as empty and never as a crash. Losing
///   the records loses the convenience, never the items, which the inventory
///   always reports live.
public protocol LaunchItemChangeRecording: Sendable {
  func record(_ change: LaunchItemChange) async throws
  func recordedChanges() async throws -> [LaunchItemChange]
}

/// What the privileged side refuses or fails with, in the app's own words. The
/// helper's refusal vocabulary stays in GleamHelperCore; this is what survives
/// the crossing, which is why nothing here names a helper refusal.
public enum PrivilegedLaunchItemFailure: Error, Sendable, Equatable {
  /// The privileged side could not resolve the item to anything on the
  /// machine, so it refused rather than guessing. This is the one failure that
  /// means the item is gone, and C24 maps it onto `itemNotFound`: the person is
  /// told that rather than shown a protocol error.
  case itemUnresolvable
  /// Refused or failed for a reason that is not the item being gone, in a
  /// sentence that names no path.
  case refused(reason: String)
}

/// What a change can fail with. Two cases, because two things are worth
/// telling apart: the item is gone, or the change did not take effect. Every
/// other distinction, whether the helper refused, was unreachable or was never
/// installed, is the same fact to the person reading the row and arrives as a
/// plain sentence.
public enum LaunchItemError: Error, Sendable, Equatable {
  /// The item is not on the machine any more. On the system scope path this is
  /// the privileged side failing to resolve it, mapped on.
  case itemNotFound(item: LaunchItemID)
  /// The change did not take effect, with a plain sentence saying why that
  /// names no path.
  case changeFailed(reason: String)
}
