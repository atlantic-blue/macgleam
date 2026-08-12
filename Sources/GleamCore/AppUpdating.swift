import Foundation

/// The app's updater, behind one small surface.
///
/// It exists so the rules this app has about updating itself live here rather
/// than inside a framework's configuration. An app that can replace itself is
/// the most dangerous thing on the disk, so the rules are narrow and stated:
/// the feed is the channel's own, a check offers and never installs, and a
/// signature is checked before anything is offered at all.
///
/// Guarantees an implementation keeps:
/// - `check` looks and asks. Nothing installs without somebody saying yes.
/// - `apply` points the updater at the policy's own feed, so nothing else can
///   name one.
/// - An entry whose signature does not verify against the key in the bundle is
///   refused before it reaches a person.
public protocol AppUpdating: Sendable {
  func apply(_ policy: UpdatePolicy) async
  func check() async
  var lastCheck: Date? { get async }
}

/// The updater a build has when it has none: it says so, and it never claims
/// the app is up to date, because "no updater" and "nothing to update" are
/// different facts and only one of them is good news.
public struct UnavailableUpdater: AppUpdating {
  public init() {}

  public func apply(_ policy: UpdatePolicy) async {}

  public func check() async {}

  public var lastCheck: Date? {
    get async { nil }
  }
}
