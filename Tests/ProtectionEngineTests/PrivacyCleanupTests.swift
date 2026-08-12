import Foundation
import GleamCore
import ProtectionEngine
import Testing

/// Privacy cleanup: the traces of using this Mac, one row per thing a person
/// would lose.
///
/// The distinction these exist to keep is between clearing a history and
/// clearing cookies. Both are "privacy", and one of them signs you out of
/// everything. So they are separate rows, separately ticked, each saying what
/// goes and what stays, and none of them arrives already selected.
@Suite("Privacy cleanup")
struct PrivacyCleanupTests {

  private func outcome() async throws -> ProtectionScanOutcome {
    try await runProtectionScan(engine: ProtectionEngine(), over: await makePrivacyDisk())
  }

  private func privacyFindings(in outcome: ProtectionScanOutcome) -> [Finding] {
    outcome.findings.filter { PrivacyFixture.isPrivacy($0.category) }
  }

  // MARK: - What it finds

  @Test("each browser's history, cookies and site data are three separate rows")
  func eachBrowsersTracesAreSeparateRows() async throws {
    let found = privacyFindings(in: try await outcome())
    let categories = Set(found.map(\.category))

    #expect(categories.contains(.browserHistory(browser: "Safari")))
    #expect(categories.contains(.browserCookies(browser: "Safari")))
    #expect(categories.contains(.browserSiteData(browser: "Safari")))
    #expect(categories.contains(.browserHistory(browser: "Chrome")))
    #expect(categories.contains(.browserCookies(browser: "Chrome")))
    #expect(categories.contains(.browserHistory(browser: "Firefox")))
    #expect(categories.contains(.browserCookies(browser: "Firefox")))
  }

  @Test("the traces macOS keeps itself are found and belong to no browser")
  func theTracesMacOSKeepsAreFound() async throws {
    let categories = Set(privacyFindings(in: try await outcome()).map(\.category))
    #expect(categories.contains(.recentItemsList))
    #expect(categories.contains(.wifiNetworkHistory))
  }

  @Test("a directory of site data is one row carrying its whole size")
  func aDirectoryOfSiteDataIsOneRow() async throws {
    let found = privacyFindings(in: try await outcome())
    let siteData = found.filter { $0.category == .browserSiteData(browser: "Chrome") }
    #expect(siteData.count == 1)
    let row = try #require(siteData.first)
    #expect(row.paths == [ProtectionFixture.path(PrivacyFixture.chromeLocalStorage)])
    #expect(
      row.byteSize == 3_000,
      "the row carries the bytes of everything inside it, which is what a person is deciding about")
  }

  @Test("a second profile is a second set of rows, because it is a second set of traces")
  func aSecondProfileIsASecondSetOfRows() async throws {
    let found = privacyFindings(in: try await outcome())
    let chromeHistories = found.filter { $0.category == .browserHistory(browser: "Chrome") }
    #expect(chromeHistories.count == 2)
    #expect(
      Set(chromeHistories.flatMap(\.paths)) == [
        ProtectionFixture.path(PrivacyFixture.chromeHistory),
        ProtectionFixture.path(PrivacyFixture.secondProfileHistory),
      ])
  }

  @Test("a file that is not a trace is not a privacy row")
  func aFileThatIsNotATraceIsNotAPrivacyRow() async throws {
    let paths = Set(privacyFindings(in: try await outcome()).flatMap(\.paths))
    #expect(!paths.contains(ProtectionFixture.path(PrivacyFixture.bookmarks)))
    #expect(!paths.contains(ProtectionFixture.path(PrivacyFixture.passwords)))
    #expect(!paths.contains(ProtectionFixture.path(PrivacyFixture.document)))
  }

  // MARK: - How it offers itself

  @Test("no privacy row is ever preselected")
  func noPrivacyRowIsEverPreselected() async throws {
    let found = privacyFindings(in: try await outcome())
    #expect(!found.isEmpty)
    #expect(found.allSatisfy { !$0.isPreselected })
  }

  @Test("every privacy row says what goes and what stays")
  func everyPrivacyRowSaysWhatGoesAndWhatStays() async throws {
    for finding in privacyFindings(in: try await outcome()) {
      try expectPlainSentence(finding.explanation)
      #expect(
        finding.explanation.contains("not touched") || finding.explanation.contains("stay")
          || finding.explanation.contains("nothing"),
        """
        clearing cookies signs somebody out of everything and clearing history \
        does not, so a row that does not say what survives is a row nobody can \
        decide about: "\(finding.explanation)"
        """)
    }
  }

  @Test("a browser row names its browser, so two browsers are never one decision")
  func aBrowserRowNamesItsBrowser() async throws {
    for finding in privacyFindings(in: try await outcome()) {
      switch finding.category {
      case .browserHistory(let browser), .browserCookies(let browser),
        .browserSiteData(let browser):
        #expect(!browser.isEmpty)
        #expect(finding.explanation.contains(browser))
      default:
        continue
      }
    }
  }

  // MARK: - What clearing one plans

  @Test("a privacy row is cleared permanently, because there is no trash for a history")
  func aPrivacyRowIsClearedPermanently() async throws {
    let selection = privacyFindings(in: try await outcome())
    for mode in [Settings.DeletionMode.trash, .permanent] {
      let plan = try ProtectionEngine().plan(
        selection: selection,
        context: makeProtectionPlanContext(
          rules: try makeSignedProtectionCatalog(), deletionMode: mode))

      #expect(!plan.operations.isEmpty)
      #expect(
        plan.operations.allSatisfy {
          if case .deletePermanently = $0.kind { return true }
          return false
        },
        "the deletion mode has no say: there is no meaningful trash for a database row")
    }
  }

  @Test("a privacy row is never quarantined, because keeping a copy is the opposite of the ask")
  func aPrivacyRowIsNeverQuarantined() async throws {
    let plan = try ProtectionEngine().plan(
      selection: privacyFindings(in: try await outcome()),
      context: makeProtectionPlanContext(rules: try makeSignedProtectionCatalog()))

    #expect(
      !plan.operations.contains {
        if case .quarantine = $0.kind { return true }
        return false
      })
  }

  @Test("clearing one row plans exactly that row's paths and nothing beside it")
  func clearingOneRowPlansExactlyThatRow() async throws {
    let found = privacyFindings(in: try await outcome())
    let cookies = try #require(found.first { $0.category == .browserCookies(browser: "Safari") })

    let plan = try ProtectionEngine().plan(
      selection: [cookies],
      context: makeProtectionPlanContext(rules: try makeSignedProtectionCatalog()))

    let targets = plan.operations.compactMap { operation -> AbsolutePath? in
      guard case .deletePermanently(let target) = operation.kind else { return nil }
      return target
    }
    #expect(targets == cookies.paths)
  }

  @Test("a detection beside a privacy row is still quarantined")
  func aDetectionBesideAPrivacyRowIsStillQuarantined() async throws {
    let found = privacyFindings(in: try await outcome())
    let detection = Finding(
      id: UUID(),
      sessionID: ProtectionFixture.sessionID,
      category: .adwareLaunchItem,
      entries: [
        PathEntry(path: ProtectionFixture.path(ProtectionFixture.adwareAgent), allocatedBytes: 8)
      ],
      risk: .dangerous,
      explanation: "A fixture row.",
      isPreselected: true)

    let plan = try ProtectionEngine().plan(
      selection: found + [detection],
      context: makeProtectionPlanContext(rules: try makeSignedProtectionCatalog()))

    let quarantines = plan.operations.filter {
      if case .quarantine = $0.kind { return true }
      return false
    }
    #expect(quarantines.count == 1)
    #expect(quarantines.first?.findingID == detection.id)
  }
}
