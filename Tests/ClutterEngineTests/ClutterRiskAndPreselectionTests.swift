import ClutterEngine
import Foundation
import GleamCore
import Testing

/// Large and old files are the user's own documents, so they sit at review
/// risk and are never preselected. C5 makes the preselection rule binding
/// for every Clutter finding: preselected only when risk is safe.
@Suite("Clutter scan: risk and preselection")
struct ClutterRiskAndPreselectionTests {

  @Test("large file findings are review risk and never preselected")
  func largeFileFindingsAreReviewRiskAndNeverPreselected() async throws {
    let fileSystem = await ClutterTree.seeded()
    let outcome = try await runClutterScan(rules: ClutterTree.catalog(), over: fileSystem)

    let largeFindings = outcome.findings(in: .largeFile)
    #expect(!largeFindings.isEmpty)
    for finding in largeFindings {
      #expect(finding.risk == .review)
      #expect(finding.isPreselected == false)
    }
  }

  @Test("old file findings are review risk and never preselected")
  func oldFileFindingsAreReviewRiskAndNeverPreselected() async throws {
    let fileSystem = await ClutterTree.seeded()
    let outcome = try await runClutterScan(rules: ClutterTree.catalog(), over: fileSystem)

    let oldFindings = outcome.findings(in: .oldFile)
    #expect(!oldFindings.isEmpty)
    for finding in oldFindings {
      #expect(finding.risk == .review)
      #expect(finding.isPreselected == false)
    }
  }

  @Test("downloads triage findings are never preselected")
  func downloadsTriageFindingsAreNeverPreselected() async throws {
    let fileSystem = await ClutterTree.seeded()
    let outcome = try await runClutterScan(rules: ClutterTree.catalog(), over: fileSystem)

    let triageFindings = outcome.findings(in: .downloadsTriage)
    #expect(!triageFindings.isEmpty)
    for finding in triageFindings {
      #expect(finding.isPreselected == false)
    }
  }

  @Test("no clutter finding of any category is preselected unless its risk is safe")
  func nothingRiskyIsEverPreselected() async throws {
    let fileSystem = await ClutterTree.seeded()
    let outcome = try await runClutterScan(rules: ClutterTree.catalog(), over: fileSystem)

    #expect(!outcome.findings.isEmpty)
    for finding in outcome.findings where finding.isPreselected {
      #expect(finding.risk == .safe)
    }
  }
}
