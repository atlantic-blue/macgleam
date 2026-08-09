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
  // Clutter
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
  // Space Lens
  case spaceLensSelection
}

/// The unit of user review. Everything a user can select, inspect and act on
/// is a Finding.
public struct Finding: Identifiable, Codable, Sendable, Equatable {
  public let id: UUID
  public let sessionID: UUID
  public let category: FindingCategory
  public let paths: [AbsolutePath]
  public let byteSize: UInt64
  public let risk: RiskLevel
  public let explanation: String
  public let isPreselected: Bool

  public init(
    id: UUID,
    sessionID: UUID,
    category: FindingCategory,
    paths: [AbsolutePath],
    byteSize: UInt64,
    risk: RiskLevel,
    explanation: String,
    isPreselected: Bool
  ) {
    self.id = id
    self.sessionID = sessionID
    self.category = category
    self.paths = paths
    self.byteSize = byteSize
    self.risk = risk
    self.explanation = explanation
    self.isPreselected = isPreselected
  }
}
