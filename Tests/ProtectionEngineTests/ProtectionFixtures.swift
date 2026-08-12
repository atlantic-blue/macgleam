import CryptoKit
import Foundation
import GleamCore
import ProtectionEngine
import Testing
import os

/// Deterministic fixtures for the Protection detection scan. Nothing here
/// reads a clock, compiles a real rule, or touches the machine the suite runs
/// on: the disk is an in memory file system and the signature matcher is a
/// table of scripted answers.
enum ProtectionFixture {

  static let sessionID = uuid(0xC1)
  static let otherSessionID = uuid(0xC2)

  /// Signing seed owned by this suite alone. The production rules key never
  /// appears here.
  static let signingKeySeed = Data((0..<32).map { UInt8(truncatingIfNeeded: 0x77 &+ $0 &* 3) })

  static let home = "/Users/gleam"

  // MARK: The malware the fixture disk holds

  static let trojanSignature = "MACOS.GENIEO.A"
  static let secondSignature = "MACOS.PIRRIT.B"
  static let trojan = "\(home)/Downloads/Installer.app/Contents/MacOS/Installer"
  static let secondInfected = "/Applications/Unwanted.app/Contents/MacOS/Unwanted"

  /// An executable nothing matches, so "found the infected one" is not
  /// satisfied by an engine that reports every executable it sees.
  static let cleanExecutable = "\(home)/Tools/build.sh"
  /// A document holding the same bytes as the infected binary. Signatures are
  /// read against what the machine can run, and this is the file that makes
  /// that bound visible rather than assumed.
  static let cleanDocument = "\(home)/Documents/notes.txt"

  // MARK: The adware the curated list names

  static let adwareAgent = "\(home)/Library/LaunchAgents/com.adware.helper.plist"
  static let adwareDaemon = "/Library/LaunchDaemons/com.adware.updater.plist"
  static let extensionDirectory =
    "\(home)/Library/Application Support/Google/Chrome/Default/Extensions/badextension"
  static let adwareExtension = "\(extensionDirectory)/manifest.json"
  static let unwantedApplication = "/Applications/Unwanted.app/Contents/Info.plist"

  /// A launch agent that is nobody's business but its owner's.
  static let innocentAgent = "\(home)/Library/LaunchAgents/com.example.backup.plist"

  static let denylistedAdware = "/System/Library/LaunchDaemons/com.adware.protected.plist"

  static func uuid(_ suffix: UInt8) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000000%02X", suffix))!
  }

  static func path(_ value: String) -> AbsolutePath {
    AbsolutePath(normalising: value)
  }

  static func contents(_ seed: UInt8, length: Int = 512) -> Data {
    Data((0..<length).map { UInt8((Int($0) + Int(seed)) % 251) })
  }
}

// MARK: - The curated adware list

func makeAdwareRules() -> [AdwareRule] {
  [
    AdwareRule(
      identifier: "com.adware.helper",
      kind: .launchAgent,
      pathPatterns: [PathPattern(pattern: ProtectionFixture.adwareAgent)],
      explanation: ""
    ),
    AdwareRule(
      identifier: "com.adware.updater",
      kind: .launchDaemon,
      pathPatterns: [
        PathPattern(pattern: "/Library/LaunchDaemons/com.adware.updater.plist"),
        PathPattern(pattern: "/System/Library/LaunchDaemons/com.adware.protected.plist"),
      ],
      explanation: ""
    ),
    AdwareRule(
      identifier: "badextension",
      kind: .browserExtension,
      pathPatterns: [PathPattern(pattern: ProtectionFixture.extensionDirectory)],
      explanation: ""
    ),
    AdwareRule(
      identifier: "Unwanted",
      kind: .applicationPath,
      pathPatterns: [PathPattern(pattern: "/Applications/Unwanted.app")],
      explanation: "Unwanted was installed alongside something else and shows advertisements."
    ),
  ]
}

func makeSignedProtectionCatalog(
  adwareRules: [AdwareRule] = makeAdwareRules(),
  blocking patterns: [String] = ["/System"]
) throws -> RuleCatalog {
  let key = try Curve25519.Signing.PrivateKey(rawRepresentation: ProtectionFixture.signingKeySeed)
  let unsigned = RuleCatalog(
    version: RuleCatalogVersion(value: 1),
    signature: Data(),
    cleanupRules: [],
    adwareRules: adwareRules,
    denylist: Denylist(patterns: patterns.map { PathPattern(pattern: $0) })
  )
  return RuleCatalog(
    version: unsigned.version,
    signature: try key.signature(for: unsigned.canonicalContentEncoding()),
    cleanupRules: unsigned.cleanupRules,
    adwareRules: unsigned.adwareRules,
    denylist: unsigned.denylist
  )
}

// MARK: - The signature matcher

/// A matcher with scripted answers: which sources compile, and which files
/// each compiled source matches.
///
/// It reads every file it is asked about through the reading side it is
/// handed, so a test that scripts a match for a file the walk never offered
/// still proves nothing, and a matcher handed a mutating file system would not
/// compile.
final class ScriptedYaraMatcher: YaraScanning, @unchecked Sendable {
  /// Rule identifiers whose source does not compile.
  private let failingSources: Set<String>
  /// Rule source identifier to the paths it matches.
  private let matches: [String: Set<String>]
  /// Which source each compiled set came from. A compiled set matches its own
  /// rules and no others, the way a real one does, so a source that failed to
  /// compile cannot match through a set that succeeded.
  private let state = OSAllocatedUnfairLock(initialState: [Int: String]())

  init(failingSources: Set<String>, matches: [String: Set<String>]) {
    self.failingSources = failingSources
    self.matches = matches
  }

  func compile(rulesSource: String) throws -> CompiledYaraRules {
    guard !failingSources.contains(rulesSource) else {
      throw YaraError.compileFailed(
        ruleIdentifier: rulesSource, description: "the fixture refuses this source")
    }
    let handle = state.withLock { compiled -> Int in
      let handle = compiled.count + 1
      compiled[handle] = rulesSource
      return handle
    }
    return CompiledYaraRules(ruleCount: handle)
  }

  func match(
    file: AbsolutePath,
    against rules: CompiledYaraRules,
    fileSystem: any FileSystemReading
  ) async throws -> [YaraMatch] {
    // Read it the way a real matcher does, so a path the walk never offered
    // cannot be matched from a table alone.
    guard (try? await fileSystem.metadata(at: file)) != nil else {
      throw YaraError.fileUnreadable(file)
    }
    guard let source = state.withLock({ $0[rules.ruleCount] }),
      matches[source]?.contains(file.value) == true
    else { return [] }
    return [YaraMatch(ruleIdentifier: source)]
  }
}

/// Sources named for the signatures they carry, which is what the scripted
/// matcher keys its answers on.
func makeRuleSources(_ identifiers: [String]) -> [YaraRuleSource] {
  identifiers.map { YaraRuleSource(identifier: $0, source: $0) }
}

func makeScriptedMatcher(
  matching: [String: [String]] = [
    ProtectionFixture.trojanSignature: [ProtectionFixture.trojan],
    ProtectionFixture.secondSignature: [ProtectionFixture.secondInfected],
  ],
  failing: [String] = []
) -> ScriptedYaraMatcher {
  ScriptedYaraMatcher(
    failingSources: Set(failing),
    matches: matching.mapValues(Set.init)
  )
}

// MARK: - The fixture disk

func makeProtectionDisk() async -> InMemoryFileSystem {
  let fileSystem = InMemoryFileSystem()
  for directory in [
    "/Applications", "/Applications/Unwanted.app", "/Applications/Unwanted.app/Contents",
    "/Applications/Unwanted.app/Contents/MacOS", "/Library", "/Library/LaunchDaemons",
    "/System", "/System/Library", "/System/Library/LaunchDaemons",
    "\(ProtectionFixture.home)", "\(ProtectionFixture.home)/Downloads",
    "\(ProtectionFixture.home)/Downloads/Installer.app",
    "\(ProtectionFixture.home)/Downloads/Installer.app/Contents",
    "\(ProtectionFixture.home)/Downloads/Installer.app/Contents/MacOS",
    "\(ProtectionFixture.home)/Documents", "\(ProtectionFixture.home)/Tools",
    "\(ProtectionFixture.home)/Library", "\(ProtectionFixture.home)/Library/LaunchAgents",
    ProtectionFixture.extensionDirectory,
  ] {
    await fileSystem.seedDirectory(at: ProtectionFixture.path(directory))
  }
  await fileSystem.seedFile(
    at: ProtectionFixture.path(ProtectionFixture.trojan),
    contents: ProtectionFixture.contents(1, length: 4_096),
    isExecutable: true)
  await fileSystem.seedFile(
    at: ProtectionFixture.path(ProtectionFixture.secondInfected),
    contents: ProtectionFixture.contents(2, length: 2_048),
    isExecutable: true)
  await fileSystem.seedFile(
    at: ProtectionFixture.path(ProtectionFixture.cleanExecutable),
    contents: ProtectionFixture.contents(3, length: 1_024),
    isExecutable: true)
  await fileSystem.seedFile(
    at: ProtectionFixture.path(ProtectionFixture.cleanDocument),
    contents: ProtectionFixture.contents(1, length: 4_096))
  for adware in [
    ProtectionFixture.adwareAgent, ProtectionFixture.adwareDaemon,
    ProtectionFixture.adwareExtension, ProtectionFixture.unwantedApplication,
    ProtectionFixture.innocentAgent, ProtectionFixture.denylistedAdware,
  ] {
    await fileSystem.seedFile(
      at: ProtectionFixture.path(adware), contents: ProtectionFixture.contents(4, length: 512))
  }
  return fileSystem
}

func makeProtectionScanContext(
  over fileSystem: InMemoryFileSystem,
  rules: RuleCatalog,
  hasFullDiskAccess: Bool = true,
  sessionID: UUID = ProtectionFixture.sessionID
) -> ScanContext {
  ScanContext(
    sessionID: sessionID,
    fileSystem: fileSystem,
    rules: rules,
    settings: makeProtectionSettings(),
    hasFullDiskAccess: hasFullDiskAccess
  )
}

func makeProtectionPlanContext(
  rules: RuleCatalog,
  deletionMode: Settings.DeletionMode = .trash,
  sessionID: UUID = ProtectionFixture.sessionID
) -> PlanContext {
  PlanContext(
    sessionID: sessionID,
    rules: rules,
    settings: makeProtectionSettings(deletionMode: deletionMode),
    ownership: ProtectionOwnershipPolicy()
  )
}

func makeProtectionSettings(deletionMode: Settings.DeletionMode = .trash) -> Settings {
  Settings(
    deletionMode: deletionMode,
    largeFileThresholdBytes: 1_073_741_824,
    oldFileThresholdDays: 180,
    menuBar: MenuBarPreferences(showsStorage: true, showsMemory: true, showsProcessorLoad: true),
    motion: MotionPreferences(reduceMotionOverride: nil)
  )
}

/// The fixture home is the user's; everything else is the system's.
struct ProtectionOwnershipPolicy: PathOwnershipPolicy {
  func ownership(of path: AbsolutePath, environment: OwnershipEnvironment) -> PathOwnership {
    let home = ProtectionFixture.path(ProtectionFixture.home)
    return path == home || path.isDescendant(of: home) ? .userDomain : .systemDomain
  }
}

// MARK: - Running a scan

struct ProtectionScanOutcome: Sendable {
  var findings: [Finding] = []
  var phases: [ScanPhase] = []
  var counters: [ScanCounters] = []
  var degradedMessages: [String] = []

  var everyPath: Set<AbsolutePath> {
    Set(findings.flatMap(\.entries).map(\.path))
  }

  func findings(ofCategory predicate: (FindingCategory) -> Bool) -> [Finding] {
    findings.filter { predicate($0.category) }
  }

  var signatureIdentifiers: Set<String> {
    Set(
      findings.compactMap { finding in
        guard case .malware(let identifier) = finding.category else { return nil }
        return identifier
      })
  }
}

func runProtectionScan(
  engine: ProtectionEngine,
  over fileSystem: InMemoryFileSystem? = nil,
  rules: RuleCatalog? = nil,
  sessionID: UUID = ProtectionFixture.sessionID
) async throws -> ProtectionScanOutcome {
  let disk: InMemoryFileSystem
  if let fileSystem {
    disk = fileSystem
  } else {
    disk = await makeProtectionDisk()
  }
  let catalog: RuleCatalog
  if let rules {
    catalog = rules
  } else {
    catalog = try makeSignedProtectionCatalog()
  }
  let context = makeProtectionScanContext(over: disk, rules: catalog, sessionID: sessionID)
  var outcome = ProtectionScanOutcome()
  for try await event in engine.scan(context) {
    switch event {
    case .phase(let phase): outcome.phases.append(phase)
    case .progress(let counters): outcome.counters.append(counters)
    case .finding(let finding): outcome.findings.append(finding)
    case .degraded(let sentence): outcome.degradedMessages.append(sentence)
    }
  }
  return outcome
}

func expectPlainSentence(
  _ sentence: String,
  sourceLocation: SourceLocation = #_sourceLocation
) throws {
  #expect(!sentence.isEmpty, sourceLocation: sourceLocation)
  #expect(sentence.hasSuffix("."), sourceLocation: sourceLocation)
  #expect(!sentence.contains("Error"), sourceLocation: sourceLocation)
  #expect(!sentence.contains("nil"), sourceLocation: sourceLocation)
}
