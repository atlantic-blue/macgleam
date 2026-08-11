import ApplicationsEngine
import Foundation
import GleamCore
import Testing

/// The fixture disk, checked against its own table.
///
/// Every other suite in this target reads its expected answers out of
/// `ApplicationWorld`, so a fixture that quietly stopped seeding a path would
/// turn an adversarial test into a test of nothing: the association rule
/// cannot falsely claim a file that was never written. These tests exist to
/// make that failure loud, and they are the one suite here that has nothing to
/// say about the engine.
@Suite("Applications inventory: the fixture disk itself")
struct ApplicationWorldFixtureTests {

  @Test("every application bundle in the table is on the disk with a readable Info.plist")
  func everyApplicationIsOnTheDisk() async throws {
    let fileSystem = try await ApplicationWorld.seeded()

    for application in ApplicationWorld.installedApplications {
      #expect(await fileSystem.exists(ApplicationsFixture.path(application.bundlePath)))
      let data = try await fileSystem.readData(
        at: ApplicationsFixture.path(application.infoPlistPath), maxBytes: 1_000_000)
      guard application.plistIsMalformed == false else {
        #expect(
          (try? PropertyListSerialization.propertyList(from: data, format: nil)) == nil,
          "the broken bundle must not be readable, that is its whole job")
        continue
      }
      let parsed =
        try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
      #expect(parsed?["CFBundleIdentifier"] as? String == application.bundleID)
      #expect(parsed?["CFBundleName"] as? String == application.displayName)
      #expect(parsed?["CFBundleShortVersionString"] as? String == application.version)
    }
  }

  @Test("every candidate leftover in the table is on the disk in the shape the table gives it")
  func everyLeftoverIsOnTheDisk() async throws {
    let fileSystem = try await ApplicationWorld.seeded()

    for leftover in ApplicationWorld.everyLeftover {
      let path = ApplicationsFixture.path(leftover.path)
      let record = try await fileSystem.metadata(at: path)
      #expect(
        record.isDirectory == leftover.shape.isDirectory, "\(leftover.path): \(leftover.reason)")
      let total = try await allocatedTotal(of: path, on: fileSystem)
      #expect(total > 0)
    }
  }

  @Test("the table's unowned paths are real files, not typing mistakes")
  func unownedPathsAreRealFiles() async throws {
    let fileSystem = try await ApplicationWorld.seeded()

    // A path that belongs to nobody only proves something when it is
    // genuinely there to be claimed.
    #expect(ApplicationWorld.unattributablePaths.count >= 8)
    for path in ApplicationWorld.unattributablePaths {
      #expect(await fileSystem.exists(path), "\(path.value) was never seeded")
    }
  }

  @Test("the table gives one application a leftover of every kind the contract names")
  func oneApplicationCarriesEveryKind() {
    let kinds = Set(ApplicationWorld.expectedLeftovers(of: ApplicationWorld.mail).map(\.kind))
    #expect(kinds == Set(LeftoverPath.Kind.allKindsInThisSuite))
  }

  @Test("the running application's identifier is a real prefix of its neighbour's")
  func siblingIdentifierIsAPrefixOfTheRunningApplications() {
    #expect(
      ApplicationWorld.runningApplicationPrefixSibling.hasPrefix(
        ApplicationWorld.runningApplication))
    #expect(
      ApplicationWorld.runningApplicationPrefixSibling != ApplicationWorld.runningApplication)
  }

  @Test("the colliding identifiers really do collide")
  func collidingIdentifiersCollide() {
    #expect(ApplicationWorld.mailer.hasPrefix(ApplicationWorld.mail))
    #expect(ApplicationWorld.mailHelper.hasPrefix(ApplicationWorld.mail + "."))
    #expect(ApplicationWorld.mailPro.hasPrefix(ApplicationWorld.mail + "-"))
    #expect(
      ApplicationWorld.installedApplications.contains { $0.bundleID == ApplicationWorld.ghost }
        == false)
  }
}
