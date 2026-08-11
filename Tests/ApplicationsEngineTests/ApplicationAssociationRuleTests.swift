import ApplicationsEngine
import Foundation
import GleamCore
import Testing

/// C9's association rule, which is the whole reason this slice exists.
///
/// "Discovery never includes a path outside the recognised leftover locations
/// for the bundle identifier; a false association here becomes a deleted
/// stranger's file, so the association rule is conservative and its tests are
/// adversarial."
///
/// So every test here asserts attribution exactly. Not that a plausible file
/// turned up, which any rule loose enough to be wrong would also satisfy, but
/// that this path went to this application and to no other, and that the paths
/// belonging to nobody went nowhere. The fixture is built so that each wrong
/// rule somebody might reach for fails a different test: a prefix match fails
/// the mailer test, a substring match fails the backup file test, a vendor
/// prefix match fails the group container test, and a rule that never asks
/// whether the owner is installed fails the removed application test.
@Suite("Applications inventory: the association rule")
struct ApplicationAssociationRuleTests {

  // MARK: The whole table at once

  @Test("every application is given exactly the leftovers that are its own")
  func everyApplicationIsGivenExactlyItsOwnLeftovers() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    for entry in entries {
      #expect(
        leftoverPaths(of: entry) == ApplicationWorld.expectedLeftoverPaths(of: entry.bundleID),
        "\(entry.bundleID) was given the wrong set of leftovers")
    }
  }

  @Test("no path that belongs to nobody is attributed to any application")
  func noUnattributablePathIsEverAttributed() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    let attributed = everyAttributedPath(in: entries)
    let falselyClaimed = attributed.intersection(ApplicationWorld.unattributablePaths)
    #expect(
      falselyClaimed.isEmpty,
      """
      these paths belong to nobody and were claimed anyway: \
      \(falselyClaimed.map(\.value).sorted().joined(separator: ", "))
      """)
  }

  @Test("no path is claimed by two applications at once")
  func noPathIsClaimedTwice() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    var claimants: [AbsolutePath: [String]] = [:]
    for entry in entries {
      for leftover in entry.leftoverPaths {
        claimants[leftover.path, default: []].append(entry.bundleID)
      }
    }
    let shared = claimants.filter { $0.value.count > 1 }
    #expect(
      shared.isEmpty,
      """
      a leftover with two owners is a file one uninstall takes from the other: \
      \(shared.map { "\($0.key.value) -> \($0.value.sorted())" }.sorted().joined(separator: ", "))
      """)
  }

  // MARK: Colliding bundle identifier prefixes

  @Test("an application never claims a file belonging to one whose identifier extends its own")
  func shorterIdentifierNeverClaimsTheLongerOnesFiles() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    let mail = try #require(entry(for: ApplicationWorld.mail, in: entries))
    let mailer = try #require(entry(for: ApplicationWorld.mailer, in: entries))

    // com.example.mail is a character by character prefix of
    // com.example.mailer. A prefix match here deletes the mailer's
    // preferences when somebody uninstalls the mail application.
    #expect(
      leftoverPaths(of: mail).isDisjoint(with: leftoverPaths(of: mailer)),
      "com.example.mail and com.example.mailer share a leftover")
    #expect(
      leftoverPaths(of: mail).contains(
        ApplicationsFixture.path("\(ApplicationWorld.preferences)/\(ApplicationWorld.mailer).plist")
      ) == false)
    #expect(
      leftoverPaths(of: mail).contains(
        ApplicationsFixture.path("\(ApplicationWorld.caches)/\(ApplicationWorld.mailer)")) == false)
  }

  @Test("the longer identifier still gets its own files")
  func longerIdentifierStillGetsItsOwnFiles() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    let mailer = try #require(entry(for: ApplicationWorld.mailer, in: entries))
    #expect(
      leftoverPaths(of: mailer)
        == ApplicationWorld.expectedLeftoverPaths(of: ApplicationWorld.mailer))
    #expect(mailer.leftoverPaths.count == 2)
  }

  @Test("a prefix under a dot separator belongs to the application that is installed under it")
  func dotSeparatedSubIdentifierBelongsToItsOwnApplication() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    let mail = try #require(entry(for: ApplicationWorld.mail, in: entries))
    let helper = try #require(entry(for: ApplicationWorld.mailHelper, in: entries))

    // The dot is the separator that looks most like ownership, which is what
    // makes it the dangerous one: com.example.mail.helper reads as a piece of
    // com.example.mail and is a separately installed application.
    let helperPreferences = ApplicationsFixture.path(
      "\(ApplicationWorld.preferences)/\(ApplicationWorld.mailHelper).plist")
    let helperDaemon = ApplicationsFixture.path(
      "\(ApplicationWorld.systemLaunchDaemons)/\(ApplicationWorld.mailHelper).plist")
    #expect(leftoverPaths(of: helper) == [helperPreferences, helperDaemon])
    #expect(leftoverPaths(of: mail).contains(helperPreferences) == false)
    #expect(leftoverPaths(of: mail).contains(helperDaemon) == false)
  }

  @Test("a prefix under a hyphen separator belongs to the application that is installed under it")
  func hyphenSeparatedIdentifierBelongsToItsOwnApplication() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    let mail = try #require(entry(for: ApplicationWorld.mail, in: entries))
    let pro = try #require(entry(for: ApplicationWorld.mailPro, in: entries))

    #expect(
      leftoverPaths(of: pro)
        == ApplicationWorld.expectedLeftoverPaths(of: ApplicationWorld.mailPro))
    #expect(leftoverPaths(of: mail).isDisjoint(with: leftoverPaths(of: pro)))
  }

  @Test("a prefix under a separator nobody installed belongs to nothing")
  func prefixUnderAnUninstalledSeparatorBelongsToNothing() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    let orphan = ApplicationsFixture.path(
      "\(ApplicationWorld.preferences)/\(ApplicationWorld.mail)_backup.plist")
    #expect(everyAttributedPath(in: entries).contains(orphan) == false)
  }

  // MARK: The shared vendor container

  @Test("a group container shared between one vendor's applications belongs to neither")
  func sharedGroupContainerBelongsToNeither() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    let shared = ApplicationsFixture.path(
      "\(ApplicationWorld.groupContainers)/\(ApplicationWorld.vendorTeam).com.example")
    let mail = try #require(entry(for: ApplicationWorld.mail, in: entries))
    let notes = try #require(entry(for: ApplicationWorld.notes, in: entries))

    // Both applications carry the com.example prefix, so a vendor level match
    // gives this directory two owners and the first uninstall takes the
    // other application's data with it.
    #expect(leftoverPaths(of: mail).contains(shared) == false)
    #expect(leftoverPaths(of: notes).contains(shared) == false)
    #expect(everyAttributedPath(in: entries).contains(shared) == false)
  }

  @Test("a group container whose name ends with one application's identifier still belongs to none")
  func groupContainerNamedAfterOneApplicationStillBelongsToNone() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    let vendorNamed = ApplicationsFixture.path(
      "\(ApplicationWorld.groupContainers)/\(ApplicationWorld.vendorTeam).\(ApplicationWorld.mail)")
    #expect(everyAttributedPath(in: entries).contains(vendorNamed) == false)
  }

  @Test("each application keeps the container that is its own")
  func eachApplicationKeepsItsOwnContainer() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    let mail = try #require(entry(for: ApplicationWorld.mail, in: entries))
    let notes = try #require(entry(for: ApplicationWorld.notes, in: entries))
    #expect(
      leftoverPaths(of: mail).contains(
        ApplicationsFixture.path("\(ApplicationWorld.containers)/\(ApplicationWorld.mail)")))
    #expect(
      leftoverPaths(of: notes).contains(
        ApplicationsFixture.path("\(ApplicationWorld.containers)/\(ApplicationWorld.notes)")))
  }

  // MARK: A name that merely contains the identifier

  @Test("a file whose name only contains the bundle identifier belongs to nothing")
  func nameContainingTheIdentifierBelongsToNothing() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    let backup = ApplicationsFixture.path(
      "\(ApplicationWorld.preferences)/backup-of-\(ApplicationWorld.mail)-settings.plist")
    let mail = try #require(entry(for: ApplicationWorld.mail, in: entries))
    #expect(leftoverPaths(of: mail).contains(backup) == false)
    #expect(everyAttributedPath(in: entries).contains(backup) == false)
  }

  @Test("a directory whose name continues past the bundle identifier belongs to nothing")
  func nameContinuingPastTheIdentifierBelongsToNothing() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    let continuation = ApplicationsFixture.path(
      "\(ApplicationWorld.applicationSupport)/\(ApplicationWorld.notes)y")
    let notes = try #require(entry(for: ApplicationWorld.notes, in: entries))
    #expect(leftoverPaths(of: notes).contains(continuation) == false)
    #expect(everyAttributedPath(in: entries).contains(continuation) == false)
  }

  // MARK: An application that is not installed

  @Test("a file belonging to an application that is not installed belongs to nothing")
  func fileOfAnUninstalledApplicationBelongsToNothing() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    let ghostPreferences = ApplicationsFixture.path(
      "\(ApplicationWorld.preferences)/\(ApplicationWorld.ghost).plist")
    let ghostLog = ApplicationsFixture.path(
      "\(ApplicationWorld.logs)/\(ApplicationWorld.ghost).log")

    // Both files are real, in recognised locations, and named for a bundle
    // identifier. The only thing wrong with them is that com.ghost.removed is
    // not installed, so the inventory has nobody to give them to. Sweeping
    // them up is the leftover sweep, a later slice, and it is not this one's
    // job to guess an owner for them.
    #expect(entries.contains { $0.bundleID == ApplicationWorld.ghost } == false)
    #expect(everyAttributedPath(in: entries).contains(ghostPreferences) == false)
    #expect(everyAttributedPath(in: entries).contains(ghostLog) == false)
  }

  // MARK: Outside the recognised locations

  @Test("a directory named for an application inside a stranger's folder belongs to nothing")
  func nestedDirectoryOutsideARecognisedLocationBelongsToNothing() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    let nested = ApplicationsFixture.path(
      "\(ApplicationWorld.caches)/Vendor/\(ApplicationWorld.mail)")
    let mail = try #require(entry(for: ApplicationWorld.mail, in: entries))
    #expect(leftoverPaths(of: mail).contains(nested) == false)
    #expect(everyAttributedPath(in: entries).contains(nested) == false)
  }

  @Test("no attributed path sits outside a recognised leftover location or an install location")
  func everyAttributedPathSitsInARecognisedLocation() async throws {
    let (entries, _) = try await runInventory()
    expectCompleteInventory(entries)

    let recognised = [
      ApplicationWorld.preferences, ApplicationWorld.caches, ApplicationWorld.containers,
      ApplicationWorld.applicationSupport, ApplicationWorld.userLaunchAgents,
      ApplicationWorld.logs, ApplicationWorld.systemLaunchDaemons,
    ]
    for entry in entries {
      for leftover in entry.leftoverPaths {
        let parent = parentDirectory(of: leftover.path.value)
        #expect(
          recognised.contains(parent),
          "\(leftover.path.value) is not an immediate child of a recognised leftover location")
      }
    }
  }

  // MARK: The scan agrees with the inventory

  @Test("the scan's findings name exactly what the inventory attributed and nothing more")
  func scanFindingsAgreeWithTheInventory() async throws {
    let fileSystem = try await ApplicationWorld.seeded()
    let (entries, _) = try await runInventory(over: fileSystem)
    let outcome = try await runApplicationsScan(over: fileSystem)
    expectCompleteInventory(entries)
    expectCompleteScan(outcome)

    #expect(outcome.offeredBundleIDs == Set(entries.map(\.bundleID)))
    for entry in entries {
      #expect(outcome.entryPaths(ofBundle: entry.bundleID) == [entry.installLocation])
      #expect(outcome.entryPaths(ofLeftoversFor: entry.bundleID) == leftoverPaths(of: entry))
    }
    #expect(outcome.everyEntryPath.isDisjoint(with: ApplicationWorld.unattributablePaths))
  }
}
