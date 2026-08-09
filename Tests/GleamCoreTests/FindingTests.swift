import Foundation
import GleamCore
import Testing

@Suite("Finding")
struct FindingTests {

  static let keptPath = Fixture.path("/Users/test/Documents/original.jpg")

  static let allCategories: [FindingCategory] = [
    .userCache,
    .applicationCache,
    .log,
    .brokenDownload,
    .xcodeDerivedData,
    .simulatorCache,
    .browserCache,
    .temporaryFile,
    .mailAttachmentLocalCopy,
    .trashBin(volume: Fixture.path("/Volumes/External")),
    .largeFile,
    .oldFile,
    .downloadsTriage,
    .duplicateSet(keptPath: keptPath),
    .similarPhotoSet(keptPath: keptPath),
    .malware(signatureIdentifier: "XProtect.MACOS.EXAMPLE"),
    .adwareLaunchItem,
    .suspiciousBrowserExtension,
    .unwantedAppPath,
    .browserHistory(browser: "Safari"),
    .browserCookies(browser: "Chrome"),
    .browserSiteData(browser: "Firefox"),
    .recentItemsList,
    .wifiNetworkHistory,
    .applicationBundle(bundleID: "com.example.app"),
    .applicationLeftover(bundleID: "com.example.app"),
    .orphanedLeftover,
    .spaceLensSelection,
  ]

  @Test("every category round trips losslessly", arguments: allCategories)
  func everyCategoryRoundTrips(category: FindingCategory) throws {
    try expectLosslessRoundTrip(category)
  }

  @Test("a finding round trips losslessly with every field populated")
  func findingRoundTripsFullyPopulated() throws {
    let finding = makeFinding(
      category: .malware(signatureIdentifier: "XProtect.MACOS.EXAMPLE"),
      paths: [Fixture.path("/Library/LaunchAgents/com.adware.agent.plist")],
      byteSize: UInt64.max,
      risk: .dangerous,
      explanation: "This launch agent matches a known malware signature.",
      isPreselected: true
    )
    try expectLosslessRoundTrip(finding)
  }

  @Test("a zero byte finding round trips losslessly")
  func zeroByteFindingRoundTrips() throws {
    try expectLosslessRoundTrip(makeFinding(byteSize: 0))
  }

  @Test("a duplicate set finding keeps its kept path and members through coding")
  func duplicateSetKeepsKeptPathThroughCoding() throws {
    let member = Fixture.path("/Users/test/Downloads/copy.jpg")
    let finding = makeFinding(
      category: .duplicateSet(keptPath: Self.keptPath),
      paths: [Self.keptPath, member],
      byteSize: 2048,
      risk: .safe
    )
    let encoded = try JSONEncoder().encode(finding)
    let decoded = try JSONDecoder().decode(Finding.self, from: encoded)
    #expect(decoded == finding)
    #expect(decoded.category == .duplicateSet(keptPath: Self.keptPath))
    #expect(decoded.paths.contains(Self.keptPath))
    #expect(decoded.paths.count >= 2)
  }

  @Test("a multi path finding preserves path order through coding")
  func multiPathFindingPreservesOrder() throws {
    let paths = [
      Fixture.path("/Users/test/Library/Caches/b"),
      Fixture.path("/Users/test/Library/Caches/a"),
      Fixture.path("/Users/test/Library/Caches/c"),
    ]
    let finding = makeFinding(paths: paths)
    let encoded = try JSONEncoder().encode(finding)
    let decoded = try JSONDecoder().decode(Finding.self, from: encoded)
    #expect(decoded.paths == paths)
  }

  @Test("risk levels use their contract raw values")
  func riskLevelsUseContractRawValues() {
    #expect(RiskLevel.safe.rawValue == "safe")
    #expect(RiskLevel.review.rawValue == "review")
    #expect(RiskLevel.dangerous.rawValue == "dangerous")
  }
}
