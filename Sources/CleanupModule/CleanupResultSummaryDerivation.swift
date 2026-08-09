import Foundation
import GleamCore

extension CleanupResultSummary {
  /// Derives the result screen's content from exactly one execution report.
  /// `bytesReclaimed` equals the report's total, the per category counts sum
  /// to one entry per operation in the plan, and `categoryOutcomes` appear in
  /// the review's category order, only for categories the plan touched.
  /// Failed operations contribute their plain sentences in plan order;
  /// execution refusals surface as failure sentences after them, never a
  /// crash and never a silent drop.
  init(
    report: ExecutionReport,
    plan: OperationPlan,
    review: CleanupReviewState,
    refusals: [String]
  ) {
    let operationsByID = Dictionary(
      plan.operations.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let categoryByFindingID = Dictionary(
      review.categories.flatMap { group in group.findings.map { ($0.id, group.category) } },
      uniquingKeysWith: { first, _ in first }
    )
    var accumulator = OutcomeAccumulator()
    for entry in report.results {
      guard let operation = operationsByID[entry.operationID] else { continue }
      accumulator.record(
        entry.result,
        operation: operation,
        category: categoryByFindingID[operation.findingID]
      )
    }
    self.init(
      bytesReclaimed: report.bytesReclaimed,
      categoryOutcomes: accumulator.outcomes(
        orderedBy: review.categories.map(\.category)
      ),
      failures: accumulator.failureSentences + refusals,
      skippedDenylistedNames: accumulator.skippedNames
    )
  }
}

/// Folds one report entry at a time into per category tallies, failure
/// sentences in plan order and skipped denylisted names in plan order.
private struct OutcomeAccumulator {
  private(set) var failureSentences: [String] = []
  private(set) var skippedNames: [String] = []
  private var tallies: [FindingCategory: Tally] = [:]

  private struct Tally {
    var completed: UInt32 = 0
    var failed: UInt32 = 0
    var skipped: UInt32 = 0
    var notStarted: UInt32 = 0
    var bytesReclaimed: UInt64 = 0
  }

  mutating func record(
    _ result: OperationResult,
    operation: GleamCore.Operation,
    category: FindingCategory?
  ) {
    var tally = category.flatMap { tallies[$0] } ?? Tally()
    switch result {
    case .completed(let bytes):
      tally.completed += 1
      tally.bytesReclaimed += bytes
    case .failed(let reason):
      tally.failed += 1
      failureSentences.append(reason)
    case .skippedDenylisted:
      tally.skipped += 1
      if let name = operation.targetLastComponent {
        skippedNames.append(name)
      }
    case .notStarted:
      tally.notStarted += 1
    }
    if let category {
      tallies[category] = tally
    }
  }

  func outcomes(orderedBy order: [FindingCategory]) -> [CleanupCategoryOutcome] {
    order.compactMap { category in
      guard let tally = tallies[category] else { return nil }
      return CleanupCategoryOutcome(
        category: category,
        completedCount: tally.completed,
        failedCount: tally.failed,
        skippedCount: tally.skipped,
        notStartedCount: tally.notStarted,
        bytesReclaimed: tally.bytesReclaimed
      )
    }
  }
}

extension GleamCore.Operation {
  fileprivate var targetLastComponent: String? {
    switch kind {
    case .moveToTrash(let target), .deletePermanently(let target),
      .quarantine(let target), .archive(let target, _):
      return target.lastComponent
    case .setLaunchItemEnabled, .runMaintenance:
      return nil
    }
  }
}
