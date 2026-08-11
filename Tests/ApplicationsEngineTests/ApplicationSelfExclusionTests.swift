import ApplicationsEngine
import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// C26: "The running app's own bundle and MacGleam itself are never offered
/// for uninstall."
///
/// The identifier this suite excludes is never written out as a literal. It
/// comes from `ApplicationsEngine.macGleamBundleID`, the fixture builds
/// MacGleam's bundle and MacGleam's leftovers from that same value, and one
/// test pins that value against the identity the helper already admits
/// clients under (C31, `ExpectedClientIdentity.macGleamApp`). So the suite
/// cannot pass because a string in the test happens to match a string in the
/// engine: change either one alone and this fails.
@Suite("Applications inventory: MacGleam is never offered")
struct ApplicationSelfExclusionTests {

  @Test("the identifier the engine excludes is the running application's own")
  func excludedIdentifierIsTheRunningApplications() {
    // The one pin that makes every other test in this suite mean something.
    // C31 already carries MacGleam's bundle identifier as the identity the
    // privileged helper admits its client under, and there is exactly one
    // running application in this codebase, so the two cannot legitimately
    // differ.
    #expect(
      ApplicationsEngine.macGleamBundleID == ExpectedClientIdentity.macGleamApp.bundleIdentifier)
    #expect(ApplicationsEngine.macGleamBundleID.isEmpty == false)
  }

  @Test("MacGleam's own bundle sits on the fixture disk")
  func macGleamIsActuallyInstalledInTheFixture() async throws {
    let fileSystem = try await ApplicationWorld.seeded()

    // Absence is only evidence when the thing was there to find. Every other
    // test in this suite rests on this one.
    #expect(await fileSystem.exists(ApplicationsFixture.path("/Applications/MacGleam.app")))
    for leftover in ApplicationWorld.runningApplicationLeftovers {
      #expect(await fileSystem.exists(ApplicationsFixture.path(leftover.path)))
    }
  }

  @Test("the inventory never offers MacGleam, whatever else it finds")
  func inventoryNeverOffersMacGleam() async throws {
    let (entries, _) = try await runInventory()

    #expect(entries.isEmpty == false, "an empty inventory would pass this by accident")
    #expect(entries.contains { $0.bundleID == ApplicationsEngine.macGleamBundleID } == false)
    #expect(
      entries.contains { $0.installLocation.lastComponent == "MacGleam.app" } == false)
  }

  @Test("no application is given MacGleam's own leftovers")
  func nobodyIsGivenMacGleamsLeftovers() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    let ownPaths = Set(
      ApplicationWorld.runningApplicationLeftovers.map { ApplicationsFixture.path($0.path) })
    let claimed = everyAttributedPath(in: entries).intersection(ownPaths)
    #expect(
      claimed.isEmpty,
      """
      MacGleam's own files were offered for removal under another application: \
      \(claimed.map(\.value).sorted().joined(separator: ", "))
      """)
  }

  @Test("the scan never emits a finding naming MacGleam")
  func scanNeverEmitsAFindingNamingMacGleam() async throws {
    let outcome = try await runApplicationsScan()

    #expect(outcome.findings.isEmpty == false, "an empty scan would pass this by accident")
    #expect(outcome.offeredBundleIDs.contains(ApplicationsEngine.macGleamBundleID) == false)
    let ownPaths = Set(
      ApplicationWorld.runningApplicationLeftovers.map { ApplicationsFixture.path($0.path) })
    #expect(outcome.everyEntryPath.isDisjoint(with: ownPaths))
    #expect(
      outcome.everyEntryPath.contains(ApplicationsFixture.path("/Applications/MacGleam.app"))
        == false)
  }

  @Test("the exclusion follows the running application's identity, not a name on the disk")
  func exclusionFollowsTheInjectedIdentity() async throws {
    let fileSystem = try await ApplicationWorld.seeded()
    let engine = ApplicationsEngine(runningApplicationBundleID: ApplicationWorld.mail)

    let (entries, _) = try await runInventory(over: fileSystem, engine: engine)

    // Told it is running as com.example.mail, the engine refuses to offer
    // com.example.mail and refuses to hand its files to anybody else. That is
    // the rule under test: the exclusion is over the identity the engine was
    // given, so it cannot be a hardcoded name that happens to match.
    #expect(entries.contains { $0.bundleID == ApplicationWorld.mail } == false)
    let mailPaths = ApplicationWorld.expectedLeftoverPaths(of: ApplicationWorld.mail)
    #expect(everyAttributedPath(in: entries).isDisjoint(with: mailPaths))
    // Everything else on the disk is still offered, so the exclusion is one
    // application wide rather than a scan that gave up.
    #expect(entries.contains { $0.bundleID == ApplicationWorld.mailer })
    #expect(entries.contains { $0.bundleID == ApplicationWorld.mailHelper })
  }

  @Test("an application whose identifier begins with MacGleam's own is still offered")
  func prefixSiblingOfTheRunningApplicationIsStillOffered() async throws {
    let (entries, _) = try await runInventory()

    // Excluding MacGleam by prefix rather than by identity would take this
    // application away from the person who installed it, and would take its
    // preferences with it when they never asked.
    let sibling = try #require(
      entry(for: ApplicationWorld.runningApplicationPrefixSibling, in: entries),
      "an application whose identifier merely begins with MacGleam's was hidden")
    #expect(
      leftoverPaths(of: sibling)
        == ApplicationWorld.expectedLeftoverPaths(
          of: ApplicationWorld.runningApplicationPrefixSibling))
  }
}
