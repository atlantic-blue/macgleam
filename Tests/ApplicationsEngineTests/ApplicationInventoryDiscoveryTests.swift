import ApplicationsEngine
import Foundation
import GleamCore
import Testing

/// C26's inventory guarantee and C9's shape: the inventory finds the
/// applications that are installed, names each one the way its owner would
/// recognise it, and itemises its leftovers by kind so the uninstall review
/// can group preferences, caches, containers, application support and launch
/// items.
///
/// Discovery here is the easy half. Everything this suite asserts is a
/// positive: the application is found, the leftover is attributed to it, the
/// kind and the byte total are right. The rule that decides which paths are
/// allowed to appear at all lives in the association suite, which is where
/// this slice actually earns its keep.
@Suite("Applications inventory: discovery")
struct ApplicationInventoryDiscoveryTests {

  // MARK: The applications themselves

  @Test("the inventory finds every installed application whose identity can be read")
  func inventoryFindsEveryInstalledApplication() async throws {
    let (entries, _) = try await runInventory()

    let found = Set(entries.map(\.bundleID))
    let expected = Set(ApplicationWorld.offeredApplications.compactMap(\.bundleID))
    #expect(found == expected)
  }

  @Test("an application carries its bundle identifier, name, version and install location")
  func applicationCarriesItsIdentityAndLocation() async throws {
    let (entries, _) = try await runInventory()

    for application in ApplicationWorld.offeredApplications {
      let bundleID = try #require(application.bundleID)
      let found = try #require(
        entry(for: bundleID, in: entries), "the inventory did not offer \(bundleID)")
      #expect(found.bundleID == bundleID)
      #expect(found.name == application.displayName)
      #expect(found.version == application.version)
      #expect(found.installLocation == ApplicationsFixture.path(application.bundlePath))
    }
  }

  @Test("an application installed in the user's own Applications folder is found")
  func userDomainApplicationIsFound() async throws {
    let (entries, _) = try await runInventory()

    let notes = try #require(entry(for: ApplicationWorld.notes, in: entries))
    #expect(
      notes.installLocation
        == ApplicationsFixture.path("\(ApplicationsFixture.home)/Applications/ExampleNotes.app"))
  }

  @Test("an application whose identity cannot be read is not offered and does not sink the scan")
  func unreadableApplicationIsSkippedWithoutSinkingTheScan() async throws {
    let (entries, _) = try await runInventory()

    #expect(entries.contains { $0.installLocation.lastComponent == "Broken.app" } == false)
    // The rest of the disk is still fully inventoried, which is the half that
    // matters: one unreadable bundle costs its own row and nothing else.
    #expect(entries.count == ApplicationWorld.offeredApplications.count)
  }

  @Test("an application with no leftovers at all is still listed, with none")
  func applicationWithNoLeftoversIsListedWithNone() async throws {
    let (entries, _) = try await runInventory()

    let solo = try #require(entry(for: ApplicationWorld.solo, in: entries))
    #expect(solo.leftoverPaths.isEmpty)
  }

  // MARK: The leftovers

  @Test("every leftover kind the contract names is discovered and attributed")
  func everyLeftoverKindIsDiscoveredAndAttributed() async throws {
    let (entries, _) = try await runInventory()

    let mail = try #require(entry(for: ApplicationWorld.mail, in: entries))
    let kinds = Set(mail.leftoverPaths.map(\.kind))
    #expect(
      kinds == Set(LeftoverPath.Kind.allKindsInThisSuite),
      "the mail fixture carries one leftover of every kind C9 names")
  }

  @Test("each leftover carries the kind its location gives it")
  func eachLeftoverCarriesItsKind() async throws {
    let (entries, _) = try await runInventory()

    for seeded in ApplicationWorld.leftovers where seeded.owner != nil {
      let owner = try #require(seeded.owner)
      let found = try #require(
        entry(for: owner, in: entries), "the inventory did not offer \(owner)")
      let leftover = try #require(
        found.leftoverPaths.first { $0.path == ApplicationsFixture.path(seeded.path) },
        "\(owner) was not given \(seeded.path): \(seeded.reason)")
      #expect(leftover.kind == seeded.kind)
    }
  }

  @Test("a leftover file carries its own allocated bytes")
  func leftoverFileCarriesItsAllocatedBytes() async throws {
    let (entries, fileSystem) = try await runInventory()

    let mail = try #require(entry(for: ApplicationWorld.mail, in: entries))
    let preferences = try #require(
      mail.leftoverPaths.first { $0.kind == .preferences })
    let expected = try await allocatedTotal(of: preferences.path, on: fileSystem)
    #expect(preferences.byteSize == expected)
    #expect(preferences.byteSize > 0)
  }

  @Test("a leftover directory carries its whole subtree's allocated bytes")
  func leftoverDirectoryCarriesItsSubtreeTotal() async throws {
    let (entries, fileSystem) = try await runInventory()

    let mail = try #require(entry(for: ApplicationWorld.mail, in: entries))
    let cache = try #require(mail.leftoverPaths.first { $0.kind == .cache })
    let expected = try await allocatedTotal(of: cache.path, on: fileSystem)
    #expect(cache.byteSize == expected)
    // The cache directory holds two files, so a size that only counted the
    // directory record itself would be visibly short.
    #expect(cache.byteSize > 3_000)
  }

  @Test("every leftover byte size is the allocated total of the path it names")
  func everyLeftoverByteSizeMatchesTheDisk() async throws {
    let (entries, fileSystem) = try await runInventory()
    expectCompleteInventory(entries)

    for entry in entries {
      for leftover in entry.leftoverPaths {
        let expected = try await allocatedTotal(of: leftover.path, on: fileSystem)
        #expect(
          leftover.byteSize == expected,
          "\(leftover.path.value) was reported as \(leftover.byteSize), the disk says \(expected)")
      }
    }
  }

  @Test("a launch agent and a launch daemon are told apart by where they live")
  func launchAgentAndLaunchDaemonAreToldApart() async throws {
    let (entries, _) = try await runInventory()

    let mail = try #require(entry(for: ApplicationWorld.mail, in: entries))
    let agent = try #require(mail.leftoverPaths.first { $0.kind == .launchAgent })
    let daemon = try #require(mail.leftoverPaths.first { $0.kind == .launchDaemon })
    #expect(agent.path.value.hasPrefix(ApplicationWorld.userLaunchAgents))
    #expect(daemon.path.value.hasPrefix(ApplicationWorld.systemLaunchDaemons))
  }
}

extension LeftoverPath.Kind {
  /// The seven kinds C9 names. Written as a switch rather than a list so a
  /// kind added later fails to compile until somebody decides whether the
  /// fixture should carry one.
  static var allKindsInThisSuite: [LeftoverPath.Kind] {
    let every: [LeftoverPath.Kind] = [
      .preferences, .cache, .container, .applicationSupport, .launchAgent, .launchDaemon, .log,
    ]
    for kind in every {
      switch kind {
      case .preferences, .cache, .container, .applicationSupport, .launchAgent, .launchDaemon,
        .log:
        continue
      }
    }
    return every
  }
}
