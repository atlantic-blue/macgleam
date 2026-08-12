import Foundation

/// Which appcast a build watches.
///
/// Two channels and no more: the stable one everybody gets, and a beta one
/// somebody opts into. They are separate feeds rather than one feed with a
/// flag, so a beta entry cannot reach a stable installation through a mistake
/// in a filter.
public enum UpdateChannel: String, Codable, Sendable, CaseIterable, Equatable {
  case stable
  case beta

  /// The appcast this channel reads. One of exactly three outbound endpoints
  /// in the whole app, beside the rules channel and licence activation.
  public var appcastURL: URL {
    switch self {
    case .stable:
      return URL(string: "https://updates.macgleam.app/appcast.xml")!
    case .beta:
      return URL(string: "https://updates.macgleam.app/appcast-beta.xml")!
    }
  }

  /// What the Settings row says. The beta line says what it costs, because
  /// somebody switching to it is agreeing to run software that has had less
  /// use, and a row that only said "beta" would not have told them.
  public var explanation: String {
    switch self {
    case .stable:
      return "Updates that have been through a beta first."
    case .beta:
      return "Updates as they are built. They arrive sooner and have had less use."
    }
  }
}

/// Everything an update check needs to be decided without a framework in the
/// room, so the choices this app makes about updating are testable.
///
/// Guarantees:
/// - The feed is the channel's own and nothing else can name one.
/// - An update is offered and never installed unasked: this app changes
///   nothing about itself without somebody saying yes.
/// - The signature is checked by the framework against the embedded public
///   key, so an appcast entry that was tampered with is refused before it is
///   ever offered.
public struct UpdatePolicy: Sendable, Equatable {
  public let channel: UpdateChannel
  /// Whether the app may look for updates by itself. Looking is not
  /// installing: a check that found something still asks.
  public let checksAutomatically: Bool
  /// How long between automatic checks, in seconds. Daily by default, which
  /// is often enough for a security fix to travel and rare enough that nobody
  /// notices it happening.
  public let checkInterval: TimeInterval

  public static let dailyInterval: TimeInterval = 24 * 60 * 60

  public init(
    channel: UpdateChannel = .stable,
    checksAutomatically: Bool = true,
    checkInterval: TimeInterval = UpdatePolicy.dailyInterval
  ) {
    self.channel = channel
    self.checksAutomatically = checksAutomatically
    // Anything under an hour is a poll rather than a check, and a build that
    // asked the server every minute would be a build somebody would block.
    self.checkInterval = max(checkInterval, 60 * 60)
  }

  public var feedURL: URL { channel.appcastURL }
}
