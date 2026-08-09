import Foundation

public struct SignedLicence: Codable, Sendable, Equatable {
  public let licenceKey: String
  public let issuedAt: Date
  /// The highest major version this licence unlocks. Paid major upgrades
  /// issue a new licence.
  public let majorVersionCeiling: UInt16
  /// Ed25519 over the canonical fields.
  public let signature: Data

  public init(licenceKey: String, issuedAt: Date, majorVersionCeiling: UInt16, signature: Data) {
    self.licenceKey = licenceKey
    self.issuedAt = issuedAt
    self.majorVersionCeiling = majorVersionCeiling
    self.signature = signature
  }
}

/// Where this install stands with trial and licence. Trial is 14 days from
/// first launch, full featured. Licence validation is offline.
public enum LicenceState: Codable, Sendable, Equatable {
  case trial(startedAt: Date, endsAt: Date)
  case trialExpired(endedAt: Date)
  case licensed(SignedLicence)
  case invalid(reason: String)

  /// The trial length: 14 days.
  public static let trialInterval: TimeInterval = 14 * 24 * 60 * 60

  /// A trial starting at the given date, ending exactly 14 days later.
  public static func trial(startedAt: Date) -> LicenceState {
    .trial(startedAt: startedAt, endsAt: startedAt.addingTimeInterval(trialInterval))
  }
}
