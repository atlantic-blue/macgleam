import ApplicationsEngine
import Foundation
import GleamCore
import Testing

/// The mechanics every engine shares (C4, C15) as the Applications engine
/// meets them, plus the C5 rule for the two categories this engine emits.
///
/// C5 states the pathless exception over the Performance module and nowhere
/// else: "No category of any other module is pathless." `applicationBundle`
/// and `applicationLeftover` are Applications categories, so both carry
/// entries, and an empty one would be a row somebody is asked to approve with
/// nothing named inside it.
@Suite("Applications scan: session mechanics and the entries rule")
struct ApplicationScanMechanicsTests {

  @Test("the engine declares the applications module")
  func engineDeclaresTheApplicationsModule() {
    #expect(ApplicationsEngine().module == .applications)
  }

  // MARK: The C5 entries rule

  @Test("every Applications finding names at least one path")
  func everyApplicationsFindingNamesAPath() async throws {
    let outcome = try await runApplicationsScan()
    expectCompleteScan(outcome)

    #expect(outcome.findings.isEmpty == false)
    for finding in outcome.findings {
      switch finding.category {
      case .applicationBundle(let bundleID):
        #expect(
          finding.entries.isEmpty == false,
          "the bundle finding for \(bundleID) named no path")
      case .applicationLeftover(let bundleID):
        #expect(
          finding.entries.isEmpty == false,
          "the leftover finding for \(bundleID) named no path")
      default:
        Issue.record("the Applications scan emitted a category from another module")
      }
    }
  }

  @Test("a finding's paths and byte total derive from its own entries")
  func findingTotalsDeriveFromItsEntries() async throws {
    let outcome = try await runApplicationsScan()
    expectCompleteScan(outcome)

    for finding in outcome.findings {
      #expect(finding.paths == finding.entries.map(\.path))
      #expect(finding.byteSize == finding.entries.reduce(UInt64(0)) { $0 + $1.allocatedBytes })
      #expect(finding.byteSize > 0)
    }
  }

  @Test("an application is never preselected and never offered as safe")
  func applicationsAreNeverPreselectedAndNeverSafe() async throws {
    let outcome = try await runApplicationsScan()
    expectCompleteScan(outcome)

    for finding in outcome.findings {
      // Removing somebody's application is always a decision they make with
      // the row open. Preselecting one would carry it into a plan nobody read.
      #expect(finding.isPreselected == false)
      #expect(finding.risk != .safe)
    }
  }

  @Test("every finding carries a plain sentence")
  func everyFindingCarriesAPlainSentence() async throws {
    let outcome = try await runApplicationsScan()
    expectCompleteScan(outcome)

    for finding in outcome.findings {
      expectPlainSentence(finding.explanation)
    }
  }

  @Test("a bundle finding's explanation names the application a person would recognise")
  func bundleFindingExplanationNamesTheApplication() async throws {
    let outcome = try await runApplicationsScan()
    expectCompleteScan(outcome)

    let finding = try #require(
      outcome.bundleFindings.first { applicationBundleID(of: $0) == ApplicationWorld.mail })
    #expect(finding.explanation.contains("Example Mail"))
  }

  // MARK: The session

  @Test("every finding rides the session the context named")
  func everyFindingRidesTheContextSession() async throws {
    let outcome = try await runApplicationsScan(sessionID: ApplicationsFixture.otherSessionID)
    expectCompleteScan(outcome)

    #expect(outcome.findings.isEmpty == false)
    for finding in outcome.findings {
      #expect(finding.sessionID == ApplicationsFixture.otherSessionID)
    }
  }

  @Test("phases only ever advance, start indeterminate and end settling")
  func phasesOnlyAdvance() async throws {
    let outcome = try await runApplicationsScan()
    expectCompleteScan(outcome)

    let ordinals = outcome.phases.map(phaseOrdinal)
    #expect(zip(ordinals, ordinals.dropFirst()).allSatisfy { $0 <= $1 })
    #expect(outcome.phases.first == .indeterminate)
    #expect(outcome.phases.last == .settling)
  }

  @Test("counters only count up and the final ones account for every entry emitted")
  func countersOnlyCountUpAndAccountForEveryEntry() async throws {
    let outcome = try await runApplicationsScan()
    expectCompleteScan(outcome)

    #expect(outcome.counters.isEmpty == false)
    #expect(countersAreMonotonic(outcome.counters))
    let final = try #require(outcome.counters.last)
    #expect(final.itemCount == UInt32(outcome.entryCount))
    #expect(final.bytesReclaimable == outcome.reclaimableByteTotal)
    #expect(final.filesSeen > 0)
  }

  @Test("the whole scan completes against a value that conforms to the reading side only")
  func scanNeedsOnlyTheReadingSide() async throws {
    let fileSystem = try await ApplicationWorld.seeded()
    let readingOnly = ReadingOnlyFileSystem(backing: fileSystem)
    #expect(!((readingOnly as Any) is any FileSystemMutating))

    // ScanContext.fileSystem is typed `any FileSystemReading`, so this
    // construction compiling is the property under test: nothing in the
    // discovery path can demand the mutating side.
    let context = ScanContext(
      sessionID: ApplicationsFixture.sessionID,
      fileSystem: readingOnly,
      rules: try makeSignedApplicationsCatalog(),
      settings: makeApplicationsSettings(),
      hasFullDiskAccess: true
    )
    let outcome = try await collectScan(ApplicationsEngine().scan(context))
    #expect(outcome.findings.isEmpty == false)
    let entries = try await ApplicationsEngine().inventory(context: context)
    #expect(entries.isEmpty == false)
  }

  // MARK: Cancellation

  @Test("cancelling the consuming task ends the scan promptly with only well formed findings")
  func cancellingTheScanEndsItPromptly() async throws {
    let fileSystem = try await ApplicationWorld.seeded()
    let context = makeScanContext(
      over: fileSystem, rules: try makeSignedApplicationsCatalog())
    let engine = ApplicationsEngine()

    let (firstEventSeen, firstEventContinuation) = AsyncStream.makeStream(of: Void.self)
    let consumer = Task { () -> [Finding] in
      var received: [Finding] = []
      do {
        for try await event in engine.scan(context) {
          firstEventContinuation.yield(())
          if case .finding(let finding) = event {
            received.append(finding)
          }
        }
      } catch {}
      firstEventContinuation.finish()
      return received
    }

    // The control: the same scan, run to completion, finds the fixture disk.
    // Without it a cancellation test passes against an engine that never had
    // anything to cancel.
    expectCompleteScan(try await collectScan(engine.scan(context)))

    var iterator = firstEventSeen.makeAsyncIterator()
    _ = await iterator.next()
    consumer.cancel()

    let endedPromptly = await completesPromptly {
      _ = await consumer.value
    }
    #expect(endedPromptly)

    for finding in await consumer.value {
      #expect(finding.entries.isEmpty == false)
      #expect(finding.explanation.isEmpty == false)
      #expect(applicationBundleID(of: finding) != ApplicationsEngine.macGleamBundleID)
    }
  }

  @Test("cancelling an inventory ends it promptly and leaves the disk exactly as it was")
  func cancellingTheInventoryEndsItPromptly() async throws {
    let fileSystem = try await ApplicationWorld.seeded()
    let context = makeScanContext(
      over: fileSystem, rules: try makeSignedApplicationsCatalog())

    // The control, as above: uncancelled, this inventory finds the disk.
    expectCompleteInventory(try await ApplicationsEngine().inventory(context: context))

    let consumer = Task {
      _ = try? await ApplicationsEngine().inventory(context: context)
    }
    consumer.cancel()

    let endedPromptly = await completesPromptly {
      await consumer.value
    }
    #expect(endedPromptly)

    // Read only by type, so this is belt and braces: every seeded path is
    // still where the fixture put it.
    for leftover in ApplicationWorld.everyLeftover {
      #expect(await fileSystem.exists(ApplicationsFixture.path(leftover.path)))
    }
    for application in ApplicationWorld.installedApplications {
      #expect(await fileSystem.exists(ApplicationsFixture.path(application.infoPlistPath)))
    }
  }
}
