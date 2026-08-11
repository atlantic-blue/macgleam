import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// C24's first guarantee: `list` attributes every item to its owning app where
/// the owner is resolvable, with the item's kind, scope and current enabled
/// state, and the path that can be revealed in Finder. C23 turns that
/// inventory into findings, and the C5 amendment says those findings name no
/// path: a Performance finding that carried one would be a removal waiting to
/// be planned.
///
/// The rule this suite exists to defend on the honesty side: an item whose
/// owning app cannot be worked out is still listed, and labelled as unknown.
/// Hiding it would leave the one item most worth looking at off the screen,
/// and inventing a plausible owner for it would be worse.
@Suite("Performance login items: the inventory")
struct LaunchItemInventoryTests {

  // MARK: What the scan lists

  @Test("the scan lists one finding per registered login item, in the machine's order")
  func scanListsOneFindingPerItem() async throws {
    let world = LaunchItemWorld()

    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)

    #expect(outcome.launchItems == LaunchItemFixture.items(LaunchItemFixture.inventory))
  }

  @Test("every login item finding carries the item it is offering and the scope it lives in")
  func everyFindingCarriesItsItemAndScope() async throws {
    let world = LaunchItemWorld()

    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)

    for item in LaunchItemFixture.inventory {
      let finding = try #require(
        outcome.launchItemFinding(for: item.identifier), "no finding listed \(item.label)")
      #expect(finding.category == .launchItem(item: item.identifier, scope: item.scope))
    }
  }

  @Test("the scan lists login items and maintenance tasks in the one run")
  func scanListsBothHalvesOfTheModule() async throws {
    let world = LaunchItemWorld()

    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)

    #expect(Set(outcome.maintenanceTasks) == Set(MaintenanceTask.allCases))
    #expect(outcome.launchItemFindings.count == LaunchItemFixture.inventory.count)
  }

  @Test("two scans of the same machine list the same items with the same words")
  func inventoryIsDeterministic() async throws {
    let world = LaunchItemWorld()

    let first = try await runPerformanceScan(inventory: world.inventoryOnly)
    let second = try await runPerformanceScan(inventory: world.inventoryOnly)

    #expect(first.launchItems == second.launchItems)
    for item in LaunchItemFixture.inventory {
      let left = try #require(first.launchItemFinding(for: item.identifier))
      let right = try #require(second.launchItemFinding(for: item.identifier))
      #expect(left.explanation == right.explanation)
      #expect(left.risk == right.risk)
      #expect(left.isPreselected == right.isPreselected)
    }
  }

  @Test("the scan reads the inventory through a value that cannot change a login item")
  func scanNeedsOnlyTheInventorySide() async throws {
    let world = LaunchItemWorld()
    let inventoryOnly = world.inventoryOnly

    // PerformanceEngine takes `any LaunchItemInventorying`, so this
    // construction compiling is the property under test: nothing in the scan
    // path can demand the side that changes an item.
    #expect(!((inventoryOnly as Any) is any LaunchItemSourcing))
    let outcome = try await runPerformanceScan(inventory: inventoryOnly)

    #expect(outcome.launchItemFindings.isEmpty == false)
    #expect(world.source.sawNoAttempt, "a scan changed \(world.source.attempts)")
  }

  @Test("an engine with no login item source offers the maintenance tasks and no login items")
  func anEngineWithNoSourceOffersMaintenanceOnly() async throws {
    let outcome = try await runPerformanceScan()

    #expect(Set(outcome.maintenanceTasks) == Set(MaintenanceTask.allCases))
    #expect(outcome.launchItemFindings.isEmpty)
  }

  @Test("an inventory that cannot be read degrades the scan rather than failing it")
  func anUnreadableInventoryDegradesTheScan() async throws {
    let source = FakeLaunchItemSource(listingFailure: .theInventoryCouldNotBeRead)

    let outcome = try await runPerformanceScan(
      inventory: InventoryOnlyLaunchItems(backing: source))

    #expect(
      Set(outcome.maintenanceTasks) == Set(MaintenanceTask.allCases),
      "one half being unreadable must not take the other half down with it")
    #expect(outcome.launchItemFindings.isEmpty)
    let notice = try #require(
      outcome.degradedMessages.first, "C15: what was skipped is reported as a plain sentence")
    expectPlainSentence(notice)
  }

  // MARK: Attribution to the owning app

  @Test("a login item is attributed to the application that registered it")
  func itemsAreAttributedToTheirOwningApp() async throws {
    let world = LaunchItemWorld()

    let listed = try await world.manager.list()

    let expected = LaunchItemFixture.notesHelper
    let notes = try #require(listed.first { $0.identifier == expected.identifier })
    #expect(notes.owningAppName == "Example Notes")
    #expect(notes.owningAppBundleID == "com.example.notes")
    #expect(LaunchItemPresentation.ownerLabel(for: notes) == "Example Notes")
  }

  @Test("an item whose owning application cannot be determined is listed rather than hidden")
  func anOwnerlessItemIsStillListed() async throws {
    let world = LaunchItemWorld()

    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)

    let finding = try #require(
      outcome.launchItemFinding(for: LaunchItemFixture.ownerlessAgent.identifier),
      "the item with no resolvable owner is the one most worth reading, so it is never hidden")
    let stray = LaunchItemFixture.ownerlessAgent
    #expect(finding.category == .launchItem(item: stray.identifier, scope: stray.scope))
  }

  @Test("an item with no resolvable owner is labelled honestly rather than guessed at")
  func anOwnerlessItemIsLabelledHonestly() {
    let label = LaunchItemPresentation.ownerLabel(for: LaunchItemFixture.ownerlessAgent)

    #expect(label == LaunchItemPresentation.unknownOwnerLabel)
    #expect(label.isEmpty == false)
    #expect(label.contains("nil") == false)
    #expect(label.contains("Optional(") == false)
    #expect(
      LaunchItemFixture.inventory.compactMap(\.owningAppName).contains(label) == false,
      "an unknown owner is never labelled with somebody else's app name")
  }

  @Test("an item known only by its bundle identifier is labelled with the identifier")
  func anItemKnownOnlyByBundleIdentifierSaysSo() {
    let label = LaunchItemPresentation.ownerLabel(for: LaunchItemFixture.telemetryDaemon)

    #expect(label.contains("com.example.telemetry"))
    #expect(label != LaunchItemPresentation.unknownOwnerLabel)
  }

  @Test("every login item explains itself in a plain sentence naming the item and its owner")
  func everyItemExplainsItselfInPlainWords() async throws {
    let world = LaunchItemWorld()

    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)

    for item in LaunchItemFixture.inventory {
      let finding = try #require(outcome.launchItemFinding(for: item.identifier))
      expectPlainSentence(finding.explanation)
      #expect(finding.explanation.contains(item.label), "the row names the registration")
      #expect(
        finding.explanation.contains(LaunchItemPresentation.ownerLabel(for: item)),
        "the row says which app this belongs to, or says it is not known")
      #expect(finding.explanation == LaunchItemPresentation.explanation(for: item))
    }
  }

  // MARK: Risk, preselection and the pathless rule

  @Test("every login item finding is risk review")
  func loginItemFindingsAreRiskReview() async throws {
    let world = LaunchItemWorld()

    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)

    #expect(outcome.launchItemFindings.isEmpty == false)
    #expect(outcome.launchItemFindings.allSatisfy { $0.risk == .review })
  }

  @Test("no login item finding is preselected")
  func loginItemFindingsAreNeverPreselected() async throws {
    let world = LaunchItemWorld()

    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)

    #expect(
      outcome.launchItemFindings.allSatisfy { $0.isPreselected == false },
      "C5: only a safe finding may be preselected, and what starts at login is the person's call")
  }

  @Test("no login item finding names a file path")
  func loginItemFindingsNameNoPath() async throws {
    let world = LaunchItemWorld()

    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)

    for finding in outcome.launchItemFindings {
      #expect(
        finding.entries.isEmpty,
        "C5 as amended: a Performance finding names no path, so there is none to turn into a removal"
      )
      #expect(finding.paths.isEmpty)
      #expect(
        finding.byteSize == 0,
        "zero here is exact: turning an item off reclaims nothing, it is not an unknown")
    }
  }

  @Test("the scan counts each login item as one item, because the finding is its own item")
  func eachLoginItemCountsAsOneItem() async throws {
    let world = LaunchItemWorld()

    let outcome = try await runPerformanceScan(inventory: world.inventoryOnly)

    let final = try #require(outcome.counters.last)
    #expect(
      final.itemCount == UInt32(outcome.findings.count),
      "C4: every Performance finding carries no entries, so each counts as exactly one item")
    #expect(final.itemCount >= UInt32(LaunchItemFixture.inventory.count))
    #expect(final.bytesReclaimable == 0)
  }

  // MARK: The item that has gone

  @Test("an item the app cannot resolve is refused by name rather than guessed at")
  func anUnresolvableItemIsRefusedByName() async throws {
    let world = LaunchItemWorld()

    await #expect(throws: LaunchItemError.itemNotFound(item: LaunchItemFixture.ghostUserItem)) {
      _ = try await world.manager.setEnabled(false, item: LaunchItemFixture.ghostUserItem)
    }

    #expect(world.source.sawNoAttempt, "an item that is not there is never changed on a guess")
    #expect(world.privileged.sawNothing)
    #expect(try await world.store.recordedChanges().isEmpty)
  }

  @Test("an item that has gone leaves every other item exactly as it was")
  func anUnresolvableItemChangesNothingElse() async throws {
    let world = LaunchItemWorld()

    _ = try? await world.manager.setEnabled(false, item: LaunchItemFixture.ghostUserItem)

    #expect(world.source.currentItems == LaunchItemFixture.inventory)
  }
}
