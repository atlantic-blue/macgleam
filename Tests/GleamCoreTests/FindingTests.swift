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
    .diskMapSelection,
  ]

  @Test("every category round trips losslessly", arguments: allCategories)
  func everyCategoryRoundTrips(category: FindingCategory) throws {
    try expectLosslessRoundTrip(category)
  }

  @Test("a finding round trips losslessly with every field populated")
  func findingRoundTripsFullyPopulated() throws {
    let finding = makeFinding(
      category: .malware(signatureIdentifier: "XProtect.MACOS.EXAMPLE"),
      entries: [
        makeEntry("/Library/LaunchAgents/com.adware.agent.plist", allocatedBytes: UInt64.max)
      ],
      risk: .dangerous,
      explanation: "This launch agent matches a known malware signature.",
      isPreselected: true
    )
    try expectLosslessRoundTrip(finding)
    #expect(finding.byteSize == UInt64.max)
    #expect(finding.paths == [Fixture.path("/Library/LaunchAgents/com.adware.agent.plist")])
  }

  @Test("a zero byte finding round trips losslessly")
  func zeroByteFindingRoundTrips() throws {
    let finding = makeFinding(
      entries: [makeEntry("/Users/test/Library/Caches/example", allocatedBytes: 0)]
    )
    try expectLosslessRoundTrip(finding)
    #expect(finding.byteSize == 0)
  }

  @Test("a duplicate set finding keeps its kept path and members through coding")
  func duplicateSetKeepsKeptPathThroughCoding() throws {
    let member = Fixture.path("/Users/test/Downloads/copy.jpg")
    let finding = makeFinding(
      category: .duplicateSet(keptPath: Self.keptPath),
      entries: [
        PathEntry(path: Self.keptPath, allocatedBytes: 1024),
        PathEntry(path: member, allocatedBytes: 1024),
      ],
      risk: .safe
    )
    let encoded = try JSONEncoder().encode(finding)
    let decoded = try JSONDecoder().decode(Finding.self, from: encoded)
    #expect(decoded == finding)
    #expect(decoded.category == .duplicateSet(keptPath: Self.keptPath))
    #expect(decoded.paths.contains(Self.keptPath))
    #expect(decoded.entries.count >= 2)
    #expect(decoded.byteSize == 2048)
  }

  @Test("a multi path finding preserves path order through coding")
  func multiPathFindingPreservesOrder() throws {
    let entries = [
      makeEntry("/Users/test/Library/Caches/b", allocatedBytes: 10),
      makeEntry("/Users/test/Library/Caches/a", allocatedBytes: 20),
      makeEntry("/Users/test/Library/Caches/c", allocatedBytes: 30),
    ]
    let finding = makeFinding(entries: entries)
    let encoded = try JSONEncoder().encode(finding)
    let decoded = try JSONDecoder().decode(Finding.self, from: encoded)
    #expect(decoded.entries == entries)
    #expect(decoded.paths == entries.map(\.path))
  }

  @Test("paths and byte size derive from the entries and nothing else")
  func pathsAndByteSizeDeriveFromEntries() {
    let entries = [
      makeEntry("/Users/test/Documents/reports", allocatedBytes: 4_096),
      makeEntry("/Users/test/Documents/notes.txt", allocatedBytes: 1_000),
      makeEntry("/Users/test/Pictures/photo.heic", allocatedBytes: 8_000),
    ]
    let finding = makeFinding(entries: entries)
    #expect(finding.paths == entries.map(\.path))
    #expect(finding.byteSize == 13_096)
  }

  @Test("risk levels use their contract raw values")
  func riskLevelsUseContractRawValues() {
    #expect(RiskLevel.safe.rawValue == "safe")
    #expect(RiskLevel.review.rawValue == "review")
    #expect(RiskLevel.dangerous.rawValue == "dangerous")
  }
}
