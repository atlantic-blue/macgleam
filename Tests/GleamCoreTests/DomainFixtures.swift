import Foundation
import GleamCore
import Testing

/// Foundation exports NSOperation as `Operation`; this pins the unqualified
/// name to the domain type under test for the whole module.
typealias Operation = GleamCore.Operation

/// Deterministic fixtures for the GleamCore domain model tests. Every date is
/// fixed, every identifier is fixed, and nothing reads the wall clock, so a
/// failing test reproduces byte for byte.
enum Fixture {

  static let referenceDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
  static let laterDate = Date(timeIntervalSinceReferenceDate: 700_000_500)
  static let farFutureDate = Date(timeIntervalSinceReferenceDate: 4_000_000_000)
  static let thirtyDays: TimeInterval = 30 * 24 * 60 * 60

  static let sessionID = uuid(0x01)
  static let planID = uuid(0x02)
  static let findingID = uuid(0x03)
  static let groupID = uuid(0x04)

  static let signatureBytes = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01])
  static let attributeBytes = Data([0x71, 0x2F, 0x30])

  static func uuid(_ suffix: UInt8) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000000%02X", suffix))!
  }

  static func path(_ value: String) -> AbsolutePath {
    AbsolutePath(normalising: value)
  }
}

// MARK: - Factories

func makeScanCounters(
  filesSeen: UInt64 = 100,
  bytesReclaimable: UInt64 = 4096,
  itemCount: UInt32 = 5
) -> ScanCounters {
  ScanCounters(
    filesSeen: filesSeen,
    bytesReclaimable: bytesReclaimable,
    itemCount: itemCount
  )
}

func makeScanSession(
  module: GleamModule = .cleanup,
  finishedAt: Date? = nil,
  state: ScanSession.State = .running,
  counters: ScanCounters = makeScanCounters()
) -> ScanSession {
  ScanSession(
    id: Fixture.sessionID,
    module: module,
    startedAt: Fixture.referenceDate,
    finishedAt: finishedAt,
    state: state,
    counters: counters
  )
}

func makeEntry(_ path: String, allocatedBytes: UInt64) -> PathEntry {
  PathEntry(path: Fixture.path(path), allocatedBytes: allocatedBytes)
}

func makeFinding(
  id: UUID = Fixture.findingID,
  category: FindingCategory = .userCache,
  entries: [PathEntry] = [makeEntry("/Users/test/Library/Caches/example", allocatedBytes: 1024)],
  risk: RiskLevel = .safe,
  explanation: String = "This cache is safe to remove and the app rebuilds it.",
  isPreselected: Bool = false
) -> Finding {
  Finding(
    id: id,
    sessionID: Fixture.sessionID,
    category: category,
    entries: entries,
    risk: risk,
    explanation: explanation,
    isPreselected: isPreselected
  )
}

func makeOperation(
  id: UUID = Fixture.uuid(0x10),
  kind: Operation.Kind = .moveToTrash(target: Fixture.path("/Users/test/Library/Caches/example")),
  privilege: Operation.Privilege = .user
) -> Operation {
  Operation(id: id, findingID: Fixture.findingID, kind: kind, privilege: privilege)
}

func makeOperationPlan(
  operations: [Operation],
  totalBytes: UInt64 = 1024,
  confirmation: PermanentDeletionConfirmation? = nil
) -> OperationPlan {
  OperationPlan(
    id: Fixture.planID,
    sessionID: Fixture.sessionID,
    operations: operations,
    totalBytes: totalBytes,
    permanentDeletionConfirmation: confirmation
  )
}

func makeMetadataSnapshot(
  posixPermissions: UInt16 = 0o644,
  ownerAccountName: String? = "test",
  extendedAttributes: [String: Data] = ["com.apple.quarantine": Fixture.attributeBytes],
  created: Date? = Fixture.referenceDate,
  modified: Date? = Fixture.laterDate
) -> FileMetadataSnapshot {
  FileMetadataSnapshot(
    posixPermissions: posixPermissions,
    ownerAccountName: ownerAccountName,
    extendedAttributes: extendedAttributes,
    created: created,
    modified: modified
  )
}

func makeSafetyNetItem(
  source: SafetyNetItem.Source = .malwareQuarantine,
  groupID: UUID? = nil,
  metadata: FileMetadataSnapshot = makeMetadataSnapshot(),
  isRestored: Bool = false
) -> SafetyNetItem {
  SafetyNetItem(
    id: Fixture.uuid(0x20),
    originPath: Fixture.path("/Users/test/Library/example"),
    storedPath: Fixture.path("/Users/test/Library/Application Support/MacGleam/SafetyNet/item"),
    source: source,
    groupID: groupID,
    metadata: metadata,
    storedAt: Fixture.referenceDate,
    expiresAt: Fixture.referenceDate.addingTimeInterval(Fixture.thirtyDays),
    isRestored: isRestored
  )
}

func makeLeftoverPath(
  path: AbsolutePath = Fixture.path("/Users/test/Library/Preferences/com.example.app.plist"),
  kind: LeftoverPath.Kind = .preferences,
  byteSize: UInt64 = 512
) -> LeftoverPath {
  LeftoverPath(path: path, kind: kind, byteSize: byteSize)
}

func makeAppInventoryEntry(
  bundleID: String = "com.example.app",
  leftoverPaths: [LeftoverPath] = [makeLeftoverPath()]
) -> AppInventoryEntry {
  AppInventoryEntry(
    bundleID: bundleID,
    name: "Example",
    version: "2.1.0",
    installLocation: Fixture.path("/Applications/Example.app"),
    leftoverPaths: leftoverPaths
  )
}

func makeDenylist(_ patterns: [String]) -> Denylist {
  Denylist(patterns: patterns.map { PathPattern(pattern: $0) })
}

func makeCleanupRule(
  identifier: String = "user-cache",
  category: FindingCategory = .userCache,
  patterns: [String] = ["/Users/*/Library/Caches/**"],
  risk: RiskLevel = .safe,
  preselectable: Bool = true
) -> CleanupRule {
  CleanupRule(
    identifier: identifier,
    category: category,
    pathPatterns: patterns.map { PathPattern(pattern: $0) },
    risk: risk,
    preselectable: preselectable,
    explanation: "Caches the system rebuilds on demand."
  )
}

func makeAdwareRule(
  identifier: String = "adware-agent",
  kind: AdwareRule.Kind = .launchAgent
) -> AdwareRule {
  AdwareRule(
    identifier: identifier,
    kind: kind,
    pathPatterns: [PathPattern(pattern: "/Library/LaunchAgents/com.adware.*")],
    explanation: "A launch agent installed by a known adware bundle."
  )
}

func makeRuleCatalog(
  version: UInt32 = 3,
  cleanupRules: [CleanupRule] = [makeCleanupRule()],
  adwareRules: [AdwareRule] = [makeAdwareRule()],
  denylist: Denylist = makeDenylist(["/System"])
) -> RuleCatalog {
  RuleCatalog(
    version: RuleCatalogVersion(value: version),
    signature: Fixture.signatureBytes,
    cleanupRules: cleanupRules,
    adwareRules: adwareRules,
    denylist: denylist
  )
}

func makeSignedLicence(
  majorVersionCeiling: UInt16 = 1
) -> SignedLicence {
  SignedLicence(
    licenceKey: "GLEAM-TEST-0001",
    issuedAt: Fixture.referenceDate,
    majorVersionCeiling: majorVersionCeiling,
    signature: Fixture.signatureBytes
  )
}

func makeSettings(
  deletionMode: Settings.DeletionMode = .trash,
  largeFileThresholdBytes: UInt64 = 1_073_741_824,
  oldFileThresholdDays: UInt32 = 180,
  reduceMotionOverride: Bool? = nil
) -> Settings {
  Settings(
    deletionMode: deletionMode,
    largeFileThresholdBytes: largeFileThresholdBytes,
    oldFileThresholdDays: oldFileThresholdDays,
    menuBar: MenuBarPreferences(showsStorage: true, showsMemory: false, showsProcessorLoad: true),
    motion: MotionPreferences(reduceMotionOverride: reduceMotionOverride)
  )
}

// MARK: - Codable round trip

/// Encodes the value to JSON, decodes it back, and expects equality. Values
/// are wrapped in an array so scalar encodings and container encodings go
/// through one helper.
func expectLosslessRoundTrip<Value: Codable & Equatable>(
  _ value: Value,
  sourceLocation: SourceLocation = #_sourceLocation
) throws {
  let encoded = try JSONEncoder().encode([value])
  let decoded = try JSONDecoder().decode([Value].self, from: encoded)
  #expect(decoded == [value], sourceLocation: sourceLocation)
}
