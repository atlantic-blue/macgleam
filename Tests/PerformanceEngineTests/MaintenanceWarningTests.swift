import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// C7: `clearsUserVisibleData` is true for any task whose effect a user can
/// notice as lost data, and the user interface must say so before running
/// such a task. C23: the finding explanation says what will be cleared before
/// the user runs it.
///
/// The pin that matters is the correspondence, not the one example. A warning
/// that appears on every task is noise a person learns to click through, and a
/// task that gains data clearing behaviour later without gaining a sentence is
/// the failure this suite exists to catch. So the warning is asserted over
/// every case of the closed set, both ways.
@Suite("Performance maintenance: the warning before data is cleared")
struct MaintenanceWarningTests {

  @Test("a task carries a warning exactly when it clears user visible data")
  func warningPresenceTracksTheContractFlag() {
    for task in MaintenanceTask.allCases {
      #expect(
        (MaintenanceCatalogue.warning(for: task) != nil) == task.clearsUserVisibleData,
        "\(task.rawValue) disagrees with its own clearsUserVisibleData")
    }
  }

  @Test("the Domain Name System cache flush is the task that clears user visible data")
  func theFlushIsTheTaskThatClearsData() {
    let clearing = MaintenanceTask.allCases.filter(\.clearsUserVisibleData)

    #expect(clearing == [.flushDomainNameSystemCache])
  }

  @Test("the warning names what will be cleared, in words rather than an acronym")
  func theWarningNamesWhatWillBeCleared() throws {
    let warning = try #require(
      MaintenanceCatalogue.warning(for: .flushDomainNameSystemCache))

    expectPlainSentence(warning)
    #expect(
      warning.contains("Domain Name System"),
      "the sentence names the thing being cleared, as the contract names it")
    #expect(warning.contains("DNS") == false, "spell the term out")
  }

  @Test("the warning belongs to its task rather than being one sentence for all of them")
  func theWarningBelongsToItsTask() {
    let warnings = MaintenanceTask.allCases.compactMap(MaintenanceCatalogue.warning(for:))

    #expect(warnings.isEmpty == false)
    #expect(
      Set(warnings).count == warnings.count,
      "two tasks sharing a warning means the sentence describes neither")
    for task in MaintenanceTask.allCases {
      guard let warning = MaintenanceCatalogue.warning(for: task) else { continue }
      #expect(
        warning != MaintenanceCatalogue.explanation(for: task),
        "the warning says what is lost; the explanation says what the task does")
    }
  }

  @Test("the warning reaches the finding a person reads before choosing the task")
  func theWarningReachesTheFinding() async throws {
    let outcome = try await runPerformanceScan()
    let finding = try #require(
      outcome.maintenanceFinding(for: .flushDomainNameSystemCache))
    let warning = try #require(
      MaintenanceCatalogue.warning(for: .flushDomainNameSystemCache))

    #expect(
      finding.explanation.contains(warning),
      "the review screen shows the finding, so the sentence has to be in it")
  }

  @Test("a task that clears nothing carries no warning at all")
  func aTaskThatClearsNothingCarriesNoWarning() async throws {
    let outcome = try await runPerformanceScan()
    let harmless = MaintenanceTask.allCases.filter { $0.clearsUserVisibleData == false }
    let everyWarning = MaintenanceTask.allCases.compactMap(MaintenanceCatalogue.warning(for:))

    #expect(harmless.isEmpty == false)
    for task in harmless {
      #expect(MaintenanceCatalogue.warning(for: task) == nil)
      let finding = try #require(outcome.maintenanceFinding(for: task))
      for warning in everyWarning {
        #expect(
          finding.explanation.contains(warning) == false,
          "\(task.rawValue) clears nothing, so it must not borrow another task's warning")
      }
    }
  }

  @Test("a task that clears user visible data is never preselected")
  func aDataClearingTaskIsNeverPreselected() async throws {
    let outcome = try await runPerformanceScan()

    for finding in outcome.maintenanceFindings {
      guard let task = maintenanceTask(of: finding), task.clearsUserVisibleData else { continue }
      #expect(
        finding.isPreselected == false,
        "preselected work runs without being chosen, which is the one thing the warning prevents")
    }
  }
}
