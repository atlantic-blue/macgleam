import ApplicationsEngine
import Foundation
import GleamCore
import Testing

/// C15: "`scan` respects `context.hasFullDiskAccess`: when false the engine
/// scans what the user domain allows and reports what it skipped through
/// `ScanEvent.degraded`, so the honest banner has real content."
///
/// For this engine the protected ground is the system domain, and the fixture
/// puts two real launch daemons there. Without Full Disk Access those two
/// leftovers cannot be seen, so the honest answer is a shorter list plus a
/// sentence saying what is missing from it, never a full list that quietly
/// omits them and never a scan that throws.
@Suite("Applications scan: degraded mode without full disk access")
struct ApplicationDegradedModeTests {

  @Test("the system domain is skipped and the skip is reported by name")
  func systemDomainIsSkippedAndNamed() async throws {
    let outcome = try await runApplicationsScan(hasFullDiskAccess: false)
    expectCompleteScan(outcome)

    #expect(outcome.degradedMessages.isEmpty == false)
    for message in outcome.degradedMessages {
      expectPlainSentence(message)
    }
    let combined = outcome.degradedMessages.joined(separator: " ").lowercased()
    #expect(combined.contains("daemon"), "the notice says which leftovers were not looked at")
  }

  @Test("a scan with full disk access reports nothing degraded")
  func fullAccessScanReportsNothingDegraded() async throws {
    let outcome = try await runApplicationsScan(hasFullDiskAccess: true)
    expectCompleteScan(outcome)

    #expect(outcome.degradedMessages.isEmpty)
  }

  @Test("the user domain leftovers are still found without full disk access")
  func userDomainLeftoversAreStillFound() async throws {
    let (entries, _) = try await runInventory(hasFullDiskAccess: false)

    let mail = try #require(entry(for: ApplicationWorld.mail, in: entries))
    #expect(
      leftoverPaths(of: mail)
        == ApplicationWorld.expectedLeftoverPathsWithoutFullDiskAccess(of: ApplicationWorld.mail))
    #expect(mail.leftoverPaths.contains { $0.kind == .launchAgent })
    #expect(mail.leftoverPaths.contains { $0.kind == .launchDaemon } == false)
  }

  @Test("an application whose only visible leftover is in the user domain keeps it")
  func applicationKeepsItsVisibleLeftover() async throws {
    let (entries, _) = try await runInventory(hasFullDiskAccess: false)

    let helper = try #require(entry(for: ApplicationWorld.mailHelper, in: entries))
    #expect(
      leftoverPaths(of: helper)
        == [
          ApplicationsFixture.path(
            "\(ApplicationWorld.preferences)/\(ApplicationWorld.mailHelper).plist")
        ])
  }

  @Test("a degraded scan still offers every application and still never offers MacGleam")
  func degradedScanStillOffersEveryApplication() async throws {
    let (entries, _) = try await runInventory(hasFullDiskAccess: false)

    #expect(
      Set(entries.map(\.bundleID))
        == Set(ApplicationWorld.offeredApplications.compactMap(\.bundleID)))
    #expect(entries.contains { $0.bundleID == ApplicationsEngine.macGleamBundleID } == false)
  }

  @Test("a degraded scan completes its phases and never throws")
  func degradedScanCompletesWithoutThrowing() async throws {
    let outcome = try await runApplicationsScan(hasFullDiskAccess: false)
    expectCompleteScan(outcome)

    #expect(outcome.phases.last == .settling)
    #expect(outcome.findings.isEmpty == false)
  }

  @Test("the association rule holds under degraded mode too")
  func associationRuleHoldsUnderDegradedMode() async throws {
    let (entries, _) = try await runInventory(hasFullDiskAccess: false)
    #expect(
      Set(entries.map(\.bundleID))
        == Set(ApplicationWorld.offeredApplications.compactMap(\.bundleID)),
      "a degraded scan that found nothing would pass the rest of this by accident")

    #expect(everyAttributedPath(in: entries).isDisjoint(with: ApplicationWorld.unattributablePaths))
    for entry in entries {
      #expect(
        leftoverPaths(of: entry)
          == ApplicationWorld.expectedLeftoverPathsWithoutFullDiskAccess(of: entry.bundleID))
    }
  }
}
