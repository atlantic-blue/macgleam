import Foundation
import GleamCore
import ProtectionEngine
import Testing

/// What the Protection scan detects, and what it refuses to claim.
///
/// The honest labelling this module is sold on is a property of these tests as
/// much as of the sentences: a detection names the signature that matched, an
/// absence is reported rather than implied, and nothing is found that no rule
/// describes.
@Suite("Protection detection")
struct ProtectionDetectionTests {

  private func engine(
    matching: [String: [String]] = [
      ProtectionFixture.trojanSignature: [ProtectionFixture.trojan],
      ProtectionFixture.secondSignature: [ProtectionFixture.secondInfected],
    ],
    failing: [String] = []
  ) -> ProtectionEngine {
    ProtectionEngine(
      matcher: makeScriptedMatcher(matching: matching, failing: failing),
      ruleSources: makeRuleSources([
        ProtectionFixture.trojanSignature, ProtectionFixture.secondSignature,
      ])
    )
  }

  // MARK: - Malware

  @Test("a binary matching a signature is found, and the finding names the signature")
  func aBinaryMatchingASignatureIsFound() async throws {
    let outcome = try await runProtectionScan(engine: engine())

    #expect(
      outcome.signatureIdentifiers
        == [ProtectionFixture.trojanSignature, ProtectionFixture.secondSignature])
    let trojanCategory = FindingCategory.malware(
      signatureIdentifier: ProtectionFixture.trojanSignature)
    let trojan = try #require(outcome.findings.first { $0.category == trojanCategory })
    #expect(trojan.paths == [ProtectionFixture.path(ProtectionFixture.trojan)])
  }

  @Test("an executable nothing matches is not a detection")
  func anExecutableNothingMatchesIsNotADetection() async throws {
    let outcome = try await runProtectionScan(engine: engine())
    #expect(!outcome.everyPath.contains(ProtectionFixture.path(ProtectionFixture.cleanExecutable)))
  }

  @Test("malware is dangerous and preselected, because quarantine is reversible")
  func malwareIsDangerousAndPreselected() async throws {
    let outcome = try await runProtectionScan(engine: engine())
    let malware = outcome.findings(ofCategory: {
      if case .malware = $0 { return true }
      return false
    })
    #expect(!malware.isEmpty)
    #expect(malware.allSatisfy { $0.risk == .dangerous })
    #expect(malware.allSatisfy { $0.isPreselected })
  }

  @Test("a signature is read against what the machine can run, and the bound is said out loud")
  func signaturesAreReadAgainstExecutables() async throws {
    // The document holds the same bytes as the infected binary and is not
    // executable. A scan that read every file would report it, and the
    // difference between the two is the bound the engine documents.
    let outcome = try await runProtectionScan(
      engine: engine(matching: [
        ProtectionFixture.trojanSignature: [
          ProtectionFixture.trojan, ProtectionFixture.cleanDocument,
        ]
      ]))

    #expect(outcome.everyPath.contains(ProtectionFixture.path(ProtectionFixture.trojan)))
    #expect(!outcome.everyPath.contains(ProtectionFixture.path(ProtectionFixture.cleanDocument)))
  }

  // MARK: - A rule that will not compile

  @Test("a rule that does not compile disables itself and the rest of the scan runs")
  func aRuleThatDoesNotCompileDisablesItself() async throws {
    let outcome = try await runProtectionScan(
      engine: engine(failing: [ProtectionFixture.trojanSignature]))

    #expect(
      outcome.signatureIdentifiers == [ProtectionFixture.secondSignature],
      "the rule that compiled still ran")
    #expect(!outcome.degradedMessages.isEmpty, "and the scan said what it skipped")
    for sentence in outcome.degradedMessages {
      try expectPlainSentence(sentence)
    }
  }

  @Test("every rule failing leaves a scan that still finds the adware")
  func everyRuleFailingStillLeavesTheAdwareScan() async throws {
    let outcome = try await runProtectionScan(
      engine: engine(failing: [
        ProtectionFixture.trojanSignature, ProtectionFixture.secondSignature,
      ]))

    #expect(outcome.signatureIdentifiers.isEmpty)
    #expect(outcome.everyPath.contains(ProtectionFixture.path(ProtectionFixture.adwareAgent)))
  }

  @Test("a build with no matcher scans the adware list and says the signatures were not checked")
  func aBuildWithNoMatcherSaysSo() async throws {
    let outcome = try await runProtectionScan(engine: ProtectionEngine())

    #expect(outcome.signatureIdentifiers.isEmpty)
    #expect(outcome.everyPath.contains(ProtectionFixture.path(ProtectionFixture.adwareAgent)))
    #expect(outcome.degradedMessages.count == 1)
    let sentence = try #require(outcome.degradedMessages.first)
    try expectPlainSentence(sentence)
    #expect(
      sentence.contains("signature"),
      "an absence nobody can read is the same as an absence nobody was told about")
  }

  // MARK: - Adware

  @Test("an adware launch agent and daemon are both found as launch items")
  func adwareLaunchItemsAreFound() async throws {
    let outcome = try await runProtectionScan(engine: engine())
    let paths = Set(
      outcome.findings(ofCategory: { $0 == .adwareLaunchItem }).flatMap(\.paths))
    #expect(paths.contains(ProtectionFixture.path(ProtectionFixture.adwareAgent)))
    #expect(paths.contains(ProtectionFixture.path(ProtectionFixture.adwareDaemon)))
  }

  @Test("a browser extension on the curated list is found as an extension")
  func aBrowserExtensionIsFound() async throws {
    let outcome = try await runProtectionScan(engine: engine())
    let paths = Set(
      outcome.findings(ofCategory: { $0 == .suspiciousBrowserExtension }).flatMap(\.paths))
    #expect(paths.contains(ProtectionFixture.path(ProtectionFixture.adwareExtension)))
  }

  @Test("an unwanted application path is found as an unwanted path")
  func anUnwantedApplicationPathIsFound() async throws {
    let outcome = try await runProtectionScan(engine: engine())
    let paths = Set(outcome.findings(ofCategory: { $0 == .unwantedAppPath }).flatMap(\.paths))
    #expect(paths.contains(ProtectionFixture.path(ProtectionFixture.unwantedApplication)))
  }

  @Test("a launch agent no rule names is left alone")
  func aLaunchAgentNoRuleNamesIsLeftAlone() async throws {
    let outcome = try await runProtectionScan(engine: engine())
    #expect(!outcome.everyPath.contains(ProtectionFixture.path(ProtectionFixture.innocentAgent)))
  }

  @Test("a denylisted path is never a detection, whatever a rule says about it")
  func aDenylistedPathIsNeverADetection() async throws {
    let outcome = try await runProtectionScan(engine: engine())
    #expect(
      !outcome.everyPath.contains(ProtectionFixture.path(ProtectionFixture.denylistedAdware)),
      """
      the curated list names this one and the denylist protects it. The \
      denylist wins wherever the two disagree, which is the rule the whole \
      app is built on
      """)
  }

  @Test("every detection explains itself in a plain sentence")
  func everyDetectionExplainsItself() async throws {
    let outcome = try await runProtectionScan(engine: engine())
    #expect(!outcome.findings.isEmpty)
    for finding in outcome.findings {
      try expectPlainSentence(finding.explanation)
    }
  }

  @Test("every finding names at least one path and carries its bytes")
  func everyFindingNamesAPath() async throws {
    let outcome = try await runProtectionScan(engine: engine())
    for finding in outcome.findings {
      #expect(!finding.entries.isEmpty)
      #expect(finding.byteSize == finding.entries.reduce(UInt64(0)) { $0 + $1.allocatedBytes })
    }
  }

  // MARK: - The scan's shape

  @Test("phases advance once, in order, and never go back")
  func phasesAdvanceInOrder() async throws {
    let outcome = try await runProtectionScan(engine: engine())
    #expect(outcome.phases.count >= 2)
    guard case .indeterminate = outcome.phases.first else {
      Issue.record("a scan starts before it knows how much there is")
      return
    }
    guard case .settling = outcome.phases.last else {
      Issue.record("a scan settles at the end")
      return
    }
  }

  @Test("the counters never decrease")
  func countersNeverDecrease() async throws {
    let outcome = try await runProtectionScan(engine: engine())
    for (previous, next) in zip(outcome.counters, outcome.counters.dropFirst()) {
      #expect(next.filesSeen >= previous.filesSeen)
      #expect(next.bytesReclaimable >= previous.bytesReclaimable)
      #expect(next.itemCount >= previous.itemCount)
    }
  }

  @Test("every finding belongs to the session that asked for the scan")
  func everyFindingBelongsToTheSession() async throws {
    let outcome = try await runProtectionScan(
      engine: engine(), sessionID: ProtectionFixture.otherSessionID)
    #expect(!outcome.findings.isEmpty)
    #expect(outcome.findings.allSatisfy { $0.sessionID == ProtectionFixture.otherSessionID })
  }
}
