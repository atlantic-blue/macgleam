import Foundation

public enum RiskLevel: String, Codable, Sendable, Equatable {
  case safe, review, dangerous
}

public enum FindingCategory: Codable, Sendable, Equatable, Hashable {
  // Cleanup
  case userCache, applicationCache, log, brokenDownload
  case xcodeDerivedData, simulatorCache, browserCache, temporaryFile
  case mailAttachmentLocalCopy
  case trashBin(volume: AbsolutePath)
  // Leftovers
  case largeFile, oldFile, downloadsTriage
  case duplicateSet(keptPath: AbsolutePath)
  case similarPhotoSet(keptPath: AbsolutePath)
  // Protection
  case malware(signatureIdentifier: String)
  case adwareLaunchItem, suspiciousBrowserExtension, unwantedAppPath
  // Privacy
  case browserHistory(browser: String)
  case browserCookies(browser: String)
  case browserSiteData(browser: String)
  case recentItemsList
  case wifiNetworkHistory
  // Applications
  case applicationBundle(bundleID: String)
  case applicationLeftover(bundleID: String)
  case orphanedLeftover
  // Disk Map
  case diskMapSelection
}

/// One path a finding covers, with the allocated bytes its removal reclaims:
/// the allocated size of a file, the subtree allocated total of a directory.
/// Allocated, never logical, so sparse and cloned files do not inflate the
/// promise.
public struct PathEntry: Codable, Sendable, Equatable, Hashable {
  public let path: AbsolutePath
  public let allocatedBytes: UInt64

  public init(path: AbsolutePath, allocatedBytes: UInt64) {
    self.path = path
    self.allocatedBytes = allocatedBytes
  }
}

/// The unit of user review. Everything a user can select, inspect and act on
/// is a Finding. A finding is self contained: `paths` and `byteSize` are pure
/// derivations of `entries`, so byte totals derive from the finding's own
/// entries at scan, review and plan time alike, with no stored copies and no
/// process wide cache to drift.
public struct Finding: Identifiable, Codable, Sendable, Equatable {
  public let id: UUID
  public let sessionID: UUID
  public let category: FindingCategory
  public let entries: [PathEntry]
  public let risk: RiskLevel
  public let explanation: String
  public let isPreselected: Bool

  /// Derived: the entries' paths in entry order.
  public var paths: [AbsolutePath] { entries.map(\.path) }

  /// Derived: the sum of allocatedBytes over entries.
  public var byteSize: UInt64 { entries.reduce(0) { $0 + $1.allocatedBytes } }

  public init(
    id: UUID,
    sessionID: UUID,
    category: FindingCategory,
    entries: [PathEntry],
    risk: RiskLevel,
    explanation: String,
    isPreselected: Bool
  ) {
    self.id = id
    self.sessionID = sessionID
    self.category = category
    self.entries = entries
    self.risk = risk
    self.explanation = explanation
    self.isPreselected = isPreselected
  }
}
