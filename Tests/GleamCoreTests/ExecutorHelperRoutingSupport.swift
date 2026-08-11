import Foundation
import GleamCore
import Testing
import os

/// Support for the s3b half of the C17 tests: the executor with a helper on
/// the other side of the privileged boundary.
///
/// The executor cannot see C30's message set. GleamHelperCore depends on
/// GleamCore, so the dependency cannot run the other way, and the executor
/// would have to know the wire contract to speak it. So the executor is
/// given a `PrivilegedOperationPerforming` declared in GleamCore, and the
/// component that turns an operation into a C30 request and validates the
/// reply lives on the far side of that protocol, in GleamHelperClient, where
/// the message set is visible. These tests pin the routing decision, which is
/// the executor's own; the reply validation is pinned against the real client
/// in GleamHelperClientTests.
///
/// The performer here is a recorder, never a stand in for the helper's
/// judgement: it answers what the test scripted and reports what crossed the
/// boundary. Nothing in this file decides whether an operation should have
/// been sent, which is the whole thing under test.

/// One operation as the executor handed it over. The plan identifier travels
/// with it because C30 requires every mutating request to name the plan and
/// the operation it belongs to, so the helper's log and the app's report
/// reconcile one to one.
struct PrivilegedHandover: Sendable, Equatable {
  let operationID: UUID
  let planID: UUID
  let kind: ExecutorOperation.Kind
}

/// Records every operation the executor routes to the helper and answers with
/// the result the test scripted for it, defaulting to a completion that
/// reclaims nothing.
final class RecordingPrivilegedPerformer: PrivilegedOperationPerforming {
  private struct State {
    var handovers: [PrivilegedHandover] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())
  private let scripted: [UUID: OperationResult]
  private let fallback: OperationResult

  init(
    results: [UUID: OperationResult] = [:],
    otherwise fallback: OperationResult = .completed(bytesReclaimed: 0)
  ) {
    self.scripted = results
    self.fallback = fallback
  }

  var handovers: [PrivilegedHandover] {
    state.withLock { $0.handovers }
  }

  var handedOverOperationIDs: [UUID] {
    handovers.map(\.operationID)
  }

  var sawNothing: Bool {
    handovers.isEmpty
  }

  func perform(_ operation: ExecutorOperation, planID: UUID) async -> OperationResult {
    state.withLock {
      $0.handovers.append(
        PrivilegedHandover(operationID: operation.id, planID: planID, kind: operation.kind))
    }
    return scripted[operation.id] ?? fallback
  }
}

/// The construction surface the s3b tests demand of the C17 executor: the
/// existing surface plus one privileged performer, defaulted to none so every
/// s1e call site keeps compiling and keeps its meaning. No helper means the
/// executor still refuses a system domain operation with
/// `helperUnavailable`, which is what the s1e tests already pin.
func executorMakeWithHelper(
  fileSystem: any FileSystem,
  denylist: Denylist,
  helper: (any PrivilegedOperationPerforming)?,
  isCancelled: @escaping @Sendable () -> Bool = { false }
) -> PlanExecutor {
  PlanExecutor(
    fileSystem: fileSystem,
    denylist: denylist,
    helper: helper,
    ownershipPolicy: ExecutorLibraryOwnershipPolicy(),
    environment: ExecutorFixture.environment,
    now: { ExecutorFixture.executionInstant },
    isCancelled: isCancelled
  )
}

/// A reason string a user can read: words, not a diagnostic dump. Every
/// failure the executor and the helper client produce goes through this, so
/// "plain sentence" is a checked property rather than a hope.
func expectPlainSentence(
  _ reason: String?,
  sourceLocation: SourceLocation = #_sourceLocation
) throws {
  let sentence = try #require(reason, sourceLocation: sourceLocation)
  #expect(sentence.isEmpty == false, sourceLocation: sourceLocation)
  #expect(sentence.contains(" "), "a sentence has words", sourceLocation: sourceLocation)
  #expect(
    sentence.contains("Error Domain=") == false,
    "a raw NSError description is not a sentence a user can read",
    sourceLocation: sourceLocation)
  #expect(sentence.contains("NSError") == false, sourceLocation: sourceLocation)
  #expect(sentence.contains("Optional(") == false, sourceLocation: sourceLocation)
}
