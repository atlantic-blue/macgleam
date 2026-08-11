import CleanupEngine
import Foundation
import GleamCore
import Testing

@Suite("Cleanup plan: operation kinds and totals")
struct CleanupPlanKindTests {

  private let cacheFinding = makeCleanupFinding(
    id: CleanupFixture.uuid(0xB1),
    category: .userCache,
    paths: [JunkTree.userCacheState, JunkTree.userCacheThumb],
    byteSize: 300
  )
  private let logFinding = makeCleanupFinding(
    id: CleanupFixture.uuid(0xB2),
    category: .log,
    paths: [JunkTree.sessionLog],
    byteSize: 200
  )
  private let trashBinFinding = makeCleanupFinding(
    id: CleanupFixture.uuid(0xB3),
    category: .trashBin(volume: CleanupFixture.path("/")),
    paths: [JunkTree.homeTrashNote, JunkTree.homeTrashDraft],
    byteSize: 240
  )

  @Test("trash mode plans one moveToTrash operation per selected path and no confirmation")
  func trashModePlansMoveToTrashPerPath() throws {
    let context = makePlanContext(
      rules: try JunkTree.catalog(),
      settings: makeSettings(deletionMode: .trash)
    )

    let plan = try CleanupEngine().plan(
      selection: [cacheFinding, logFinding], context: context)

    #expect(plan.operations.count == 3)
    for operation in plan.operations {
      guard case .moveToTrash = operation.kind else {
        Issue.record("expected moveToTrash, got \(operation.kind)")
        continue
      }
    }
    let targets = Set(plan.operations.compactMap(operationTarget))
    #expect(
      targets == [
        CleanupFixture.path(JunkTree.userCacheState),
        CleanupFixture.path(JunkTree.userCacheThumb),
        CleanupFixture.path(JunkTree.sessionLog),
      ])
    #expect(plan.totalBytes == 500)
    #expect(plan.permanentDeletionConfirmation == nil)
    #expect(plan.sessionID == CleanupFixture.sessionID)
  }

  @Test("every operation carries the identifier of the finding it came from")
  func operationsCarryTheirFindingIdentifier() throws {
    let context = makePlanContext(rules: try JunkTree.catalog())
    let selection = [cacheFinding, logFinding]

    let plan = try CleanupEngine().plan(selection: selection, context: context)

    for operation in plan.operations {
      let target = try #require(operationTarget(operation))
      let owner = try #require(selection.first { $0.id == operation.findingID })
      #expect(owner.paths.contains(target))
    }
  }

  @Test("permanent mode plans deletePermanently and carries a confirmation with exact counts")
  func permanentModeCarriesConfirmationWithExactCounts() throws {
    let context = makePlanContext(
      rules: try JunkTree.catalog(),
      settings: makeSettings(deletionMode: .permanent)
    )

    let plan = try CleanupEngine().plan(
      selection: [cacheFinding, logFinding], context: context)

    for operation in plan.operations {
      guard case .deletePermanently = operation.kind else {
        Issue.record("expected deletePermanently, got \(operation.kind)")
        continue
      }
    }
    let confirmation = try #require(plan.permanentDeletionConfirmation)
    #expect(confirmation.fileCount == 3)
    #expect(confirmation.byteTotal == 500)
  }

  @Test(
    "trash bin contents plan as deletePermanently even in trash mode, with a matching confirmation")
  func trashBinContentsAlwaysPlanPermanently() throws {
    let context = makePlanContext(
      rules: try JunkTree.catalog(),
      settings: makeSettings(deletionMode: .trash)
    )

    let plan = try CleanupEngine().plan(
      selection: [cacheFinding, trashBinFinding], context: context)

    let binPaths = Set(trashBinFinding.paths)
    var permanentTargets = Set<AbsolutePath>()
    var trashTargets = Set<AbsolutePath>()
    for operation in plan.operations {
      let target = try #require(operationTarget(operation))
      switch operation.kind {
      case .deletePermanently:
        permanentTargets.insert(target)
      case .moveToTrash:
        trashTargets.insert(target)
      default:
        Issue.record("unexpected operation kind \(operation.kind)")
      }
    }
    #expect(permanentTargets == binPaths)
    #expect(trashTargets == Set(cacheFinding.paths))

    let confirmation = try #require(plan.permanentDeletionConfirmation)
    #expect(confirmation.fileCount == UInt32(trashBinFinding.paths.count))
    #expect(confirmation.byteTotal == trashBinFinding.byteSize)
  }
}

@Suite("Cleanup plan: denylist and refusals")
struct CleanupPlanSafetyTests {

  @Test("a denylisted path never becomes an operation even when selected")
  func denylistedPathNeverBecomesAnOperation() throws {
    let catalog = try makeSignedCleanupCatalog(
      cleanupRules: [
        makeRule(
          identifier: "user-caches",
          category: .userCache,
          patterns: ["/Users/*/Library/Caches/com.example.app/**"]
        )
      ],
      denylist: Denylist(patterns: [
        PathPattern(pattern: "/Users/test/Library/Caches/com.example.app/images")
      ])
    )
    let hostileSelection = makeCleanupFinding(
      paths: [JunkTree.userCacheState, JunkTree.userCacheThumb],
      byteSize: 300
    )

    let plan = try CleanupEngine().plan(
      selection: [hostileSelection],
      context: makePlanContext(rules: catalog)
    )

    let targets = plan.operations.compactMap(operationTarget)
    #expect(targets == [CleanupFixture.path(JunkTree.userCacheState)])
  }

  @Test("an empty selection throws emptySelection rather than producing an empty plan")
  func emptySelectionThrows() throws {
    let context = makePlanContext(rules: try JunkTree.catalog())

    #expect(throws: PlanningError.emptySelection) {
      _ = try CleanupEngine().plan(selection: [], context: context)
    }
  }

  @Test("a finding from a different session throws rather than producing a partial plan")
  func findingFromDifferentSessionThrows() throws {
    let context = makePlanContext(
      rules: try JunkTree.catalog(),
      sessionID: CleanupFixture.sessionID
    )
    let foreign = makeCleanupFinding(sessionID: CleanupFixture.foreignSessionID)

    #expect {
      _ = try CleanupEngine().plan(selection: [foreign], context: context)
    } throws: { error in
      guard let planning = error as? PlanningError,
        case .findingFromDifferentSession = planning
      else { return false }
      return true
    }
  }

  /// C15 fixes the payload: the identifier is the offending finding's, never
  /// the session's, because a caller reconciling a refusal needs to know
  /// which finding to drop and a session identifier cannot tell them. The
  /// finding's identifier, its session and the context's session are three
  /// distinct fixture values, so this equality discriminates between them.
  @Test("the refusal names the offending finding, never the session it came from")
  func findingFromDifferentSessionNamesTheFinding() throws {
    let context = makePlanContext(
      rules: try JunkTree.catalog(),
      sessionID: CleanupFixture.sessionID
    )
    let foreign = makeCleanupFinding(
      id: CleanupFixture.uuid(0xB4),
      sessionID: CleanupFixture.foreignSessionID
    )

    #expect(throws: PlanningError.findingFromDifferentSession(foreign.id)) {
      _ = try CleanupEngine().plan(selection: [foreign], context: context)
    }
  }
}

@Suite("Cleanup plan: privilege routing")
struct CleanupPlanPrivilegeTests {

  @Test("a user domain path plans a user privilege operation")
  func userDomainPathPlansUserPrivilege() throws {
    let context = makePlanContext(
      rules: try JunkTree.catalog(),
      ownership: UserDomainPolicy()
    )

    let plan = try CleanupEngine().plan(
      selection: [makeCleanupFinding()], context: context)

    #expect(!plan.operations.isEmpty)
    for operation in plan.operations {
      #expect(operation.privilege == .user)
    }
  }

  @Test("a path the ownership policy marks systemDomain plans a root privilege operation")
  func systemDomainPathPlansRootPrivilege() throws {
    let systemPath = CleanupFixture.path(JunkTree.sessionLog)
    let context = makePlanContext(
      rules: try JunkTree.catalog(),
      ownership: SystemDomainForPathsPolicy(systemPaths: [systemPath])
    )
    let cacheFinding = makeCleanupFinding(
      id: CleanupFixture.uuid(0xB1),
      category: .userCache,
      paths: [JunkTree.userCacheState],
      byteSize: 100
    )
    let logFinding = makeCleanupFinding(
      id: CleanupFixture.uuid(0xB2),
      category: .log,
      paths: [JunkTree.sessionLog],
      byteSize: 200
    )

    let plan = try CleanupEngine().plan(
      selection: [cacheFinding, logFinding], context: context)

    for operation in plan.operations {
      let target = try #require(operationTarget(operation))
      let expected: Operation.Privilege = target == systemPath ? .root : .user
      #expect(operation.privilege == expected)
    }
  }
}
