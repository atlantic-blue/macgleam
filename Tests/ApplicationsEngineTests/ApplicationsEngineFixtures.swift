import ApplicationsEngine
import CryptoKit
import Foundation
import GleamCore
import Testing

/// Deterministic fixtures for the Applications inventory (C26 inventory half,
/// C9). Nothing here reads a wall clock, looks at the real /Applications,
/// asks the workspace what is running, or touches the machine the suite runs
/// on. Every path, identifier, byte length and instant is fixed in this file,
/// and the whole fixture disk is an in memory file system handed to the engine
/// through the reading side alone.
enum ApplicationsFixture {

  static let sessionID = uuid(0xA1)
  static let otherSessionID = uuid(0xA2)

  static let home = "/Users/gleam"
  static let userLibrary = "\(home)/Library"

  static let createdDate = Date(timeIntervalSinceReferenceDate: 780_000_000)
  static let modifiedDate = Date(timeIntervalSinceReferenceDate: 780_500_000)

  /// Signing seed owned by this suite alone. The production rules key never
  /// appears here.
  static let signingKeySeed = Data((0..<32).map { UInt8(truncatingIfNeeded: 0x3B &+ $0 &* 5) })

  static func uuid(_ suffix: UInt8) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000000%02X", suffix))!
  }

  static func path(_ value: String) -> AbsolutePath {
    AbsolutePath(normalising: value)
  }

  static func contents(_ seed: UInt8, length: Int) -> Data {
    Data((0..<length).map { UInt8((Int($0) + Int(seed)) % 251) })
  }
}

// MARK: - Signed catalogue

func makeSignedApplicationsCatalog(
  version: UInt32 = 1,
  blocking patterns: [String] = []
) throws -> RuleCatalog {
  let key = try Curve25519.Signing.PrivateKey(
    rawRepresentation: ApplicationsFixture.signingKeySeed)
  let unsigned = RuleCatalog(
    version: RuleCatalogVersion(value: version),
    signature: Data(),
    cleanupRules: [],
    adwareRules: [],
    denylist: Denylist(patterns: patterns.map { PathPattern(pattern: $0) })
  )
  let signature = try key.signature(for: unsigned.canonicalContentEncoding())
  return RuleCatalog(
    version: unsigned.version,
    signature: signature,
    cleanupRules: unsigned.cleanupRules,
    adwareRules: unsigned.adwareRules,
    denylist: unsigned.denylist
  )
}

// MARK: - The reading only file system

/// Conforms to the reading side and nothing else. Handing this to the engine
/// is the compile time proof that discovery never needs the mutating side.
struct ReadingOnlyFileSystem: FileSystemReading {
  let backing: InMemoryFileSystem

  func enumerate(
    root: AbsolutePath,
    options: EnumerationOptions
  ) -> AsyncThrowingStream<EnumerationEvent, Error> {
    backing.enumerate(root: root, options: options)
  }

  func metadata(at path: AbsolutePath) async throws -> FileRecord {
    try await backing.metadata(at: path)
  }

  func posixPermissions(at path: AbsolutePath) async throws -> UInt16 {
    try await backing.posixPermissions(at: path)
  }

  func readData(at path: AbsolutePath, maxBytes: UInt64) async throws -> Data {
    try await backing.readData(at: path, maxBytes: maxBytes)
  }

  func extendedAttributes(at path: AbsolutePath) async throws -> [String: Data] {
    try await backing.extendedAttributes(at: path)
  }

  func exists(_ path: AbsolutePath) async -> Bool {
    await backing.exists(path)
  }

  func volumeInfo(at path: AbsolutePath) async throws -> VolumeInfo {
    try await backing.volumeInfo(at: path)
  }
}

// MARK: - Application bundles on the fixture disk

/// One application bundle as it sits on the fixture disk. `bundleID`,
/// `displayName` and `version` are what its Info.plist declares; a nil value
/// means the key is absent, and `plistIsMalformed` means the file is not a
/// property list at all.
struct SeededApplication: Sendable {
  let bundlePath: String
  let bundleID: String?
  let displayName: String?
  let version: String?
  var plistIsMalformed: Bool = false
  /// The byte length of the fake executable inside the bundle, so every
  /// bundle has a subtree total worth asserting.
  var executableLength: Int = 4_096

  var infoPlistPath: String { "\(bundlePath)/Contents/Info.plist" }
  var executablePath: String { "\(bundlePath)/Contents/MacOS/executable" }
}

/// The Info.plist bytes for a bundle, written as a real XML property list so
/// the engine parses what macOS would hand it rather than a shape invented
/// for the test.
func infoPlistData(for application: SeededApplication) throws -> Data {
  if application.plistIsMalformed {
    return Data("this file is not a property list".utf8)
  }
  var keys: [String: Any] = [:]
  if let bundleID = application.bundleID {
    keys["CFBundleIdentifier"] = bundleID
  }
  if let displayName = application.displayName {
    keys["CFBundleName"] = displayName
  }
  if let version = application.version {
    keys["CFBundleShortVersionString"] = version
  }
  keys["CFBundlePackageType"] = "APPL"
  return try PropertyListSerialization.data(
    fromPropertyList: keys, format: .xml, options: 0)
}

// MARK: - Leftovers on the fixture disk

enum SeededShape: Sendable {
  case file(length: Int)
  case directory(fileLengths: [Int])

  var isDirectory: Bool {
    if case .directory = self { return true }
    return false
  }
}

/// One candidate leftover on the fixture disk, with the answer the
/// association rule must give for it. `owner` is nil when the correct answer
/// is that the path belongs to nothing: no application may claim it, and it
/// is the case a false association turns into somebody else's deleted file.
struct SeededLeftover: Sendable {
  let path: String
  let kind: LeftoverPath.Kind
  let owner: String?
  let shape: SeededShape
  /// Why this path answers the way it does, so a failure reads as the rule it
  /// broke rather than as a path mismatch.
  let reason: String
}

// MARK: - The fixture world

/// The adversarial fixture disk. Nine application bundles and thirty two
/// candidate leftovers chosen so that every wrong association rule anybody
/// might write produces a wrong answer somewhere in this table: a prefix
/// match claims the mailer's files for the mail application, a substring match
/// claims a backup file, a vendor prefix match claims a shared group
/// container, and a rule that forgets to check whether the owner is installed
/// at all claims files belonging to an application that was removed long ago.
enum ApplicationWorld {

  // MARK: Identifiers

  static let mail = "com.example.mail"
  static let mailer = "com.example.mailer"
  static let mailHelper = "com.example.mail.helper"
  static let mailPro = "com.example.mail-pro"
  static let notes = "com.example.notes"
  static let solo = "com.example.solo"
  static let ghost = "com.ghost.removed"
  static let vendorTeam = "ABCDE12345"

  /// MacGleam's own identifier, read from the engine rather than written out
  /// here, so nothing in this suite can agree with a literal instead of with
  /// the running application.
  static var runningApplication: String { ApplicationsEngine.macGleamBundleID }

  /// An identifier that begins with the running application's own and
  /// continues without a separator. A rule that excludes MacGleam by prefix
  /// rather than by identity would hide this application from its owner.
  static var runningApplicationPrefixSibling: String { runningApplication + "er" }

  // MARK: Locations

  static let preferences = "\(ApplicationsFixture.userLibrary)/Preferences"
  static let caches = "\(ApplicationsFixture.userLibrary)/Caches"
  static let containers = "\(ApplicationsFixture.userLibrary)/Containers"
  static let groupContainers = "\(ApplicationsFixture.userLibrary)/Group Containers"
  static let applicationSupport = "\(ApplicationsFixture.userLibrary)/Application Support"
  static let userLaunchAgents = "\(ApplicationsFixture.userLibrary)/LaunchAgents"
  static let logs = "\(ApplicationsFixture.userLibrary)/Logs"
  static let systemLaunchDaemons = "/Library/LaunchDaemons"

  /// The leftover locations that sit outside the user's own home. These are
  /// the ones a scan without Full Disk Access cannot read, and the degraded
  /// notice has to name them.
  static let systemDomainLocations = [systemLaunchDaemons]

  // MARK: Applications

  static var installedApplications: [SeededApplication] {
    [
      SeededApplication(
        bundlePath: "/Applications/ExampleMail.app",
        bundleID: mail,
        displayName: "Example Mail",
        version: "3.2.1"
      ),
      SeededApplication(
        bundlePath: "/Applications/ExampleMailer.app",
        bundleID: mailer,
        displayName: "Example Mailer",
        version: "1.0.4",
        executableLength: 2_048
      ),
      SeededApplication(
        bundlePath: "/Applications/ExampleMailHelper.app",
        bundleID: mailHelper,
        displayName: "Example Mail Helper",
        version: "1.1",
        executableLength: 1_024
      ),
      SeededApplication(
        bundlePath: "/Applications/ExampleMailPro.app",
        bundleID: mailPro,
        displayName: "Example Mail Pro",
        version: "4.0",
        executableLength: 8_192
      ),
      SeededApplication(
        bundlePath: "\(ApplicationsFixture.home)/Applications/ExampleNotes.app",
        bundleID: notes,
        displayName: "Example Notes",
        version: "2.0"
      ),
      SeededApplication(
        bundlePath: "/Applications/ExampleSolo.app",
        bundleID: solo,
        displayName: "Example Solo",
        version: "0.1"
      ),
      SeededApplication(
        bundlePath: "/Applications/MacGleam.app",
        bundleID: runningApplication,
        displayName: "MacGleam",
        version: "1.0"
      ),
      SeededApplication(
        bundlePath: "/Applications/MacGleamer.app",
        bundleID: runningApplicationPrefixSibling,
        displayName: "MacGleamer",
        version: "0.9"
      ),
      SeededApplication(
        bundlePath: "/Applications/Broken.app",
        bundleID: nil,
        displayName: nil,
        version: nil,
        plistIsMalformed: true
      ),
    ]
  }

  /// The applications the inventory is expected to offer, which is every
  /// bundle on the fixture disk except the running application and the one
  /// whose identity cannot be read.
  static var offeredApplications: [SeededApplication] {
    installedApplications.filter { application in
      application.bundleID != nil
        && application.plistIsMalformed == false
        && application.bundleID != runningApplication
    }
  }

  static func application(_ bundleID: String) -> SeededApplication {
    installedApplications.first { $0.bundleID == bundleID }!
  }

  // MARK: Leftovers, and the answer for each

  static var leftovers: [SeededLeftover] {
    [
      // Every kind C9 names, all seven, on the one application.
      SeededLeftover(
        path: "\(preferences)/\(mail).plist",
        kind: .preferences,
        owner: mail,
        shape: .file(length: 512),
        reason: "the preference file is named exactly for the bundle identifier"
      ),
      SeededLeftover(
        path: "\(caches)/\(mail)",
        kind: .cache,
        owner: mail,
        shape: .directory(fileLengths: [1_024, 2_048]),
        reason: "the cache directory is named exactly for the bundle identifier"
      ),
      SeededLeftover(
        path: "\(containers)/\(mail)",
        kind: .container,
        owner: mail,
        shape: .directory(fileLengths: [4_096]),
        reason: "the container is named exactly for the bundle identifier"
      ),
      SeededLeftover(
        path: "\(applicationSupport)/\(mail)",
        kind: .applicationSupport,
        owner: mail,
        shape: .directory(fileLengths: [256, 512]),
        reason: "the application support directory is named exactly for the bundle identifier"
      ),
      SeededLeftover(
        path: "\(userLaunchAgents)/\(mail).plist",
        kind: .launchAgent,
        owner: mail,
        shape: .file(length: 384),
        reason: "the launch agent is named exactly for the bundle identifier"
      ),
      SeededLeftover(
        path: "\(systemLaunchDaemons)/\(mail).plist",
        kind: .launchDaemon,
        owner: mail,
        shape: .file(length: 448),
        reason: "the launch daemon is named exactly for the bundle identifier"
      ),
      SeededLeftover(
        path: "\(logs)/\(mail).log",
        kind: .log,
        owner: mail,
        shape: .file(length: 640),
        reason: "the log file is named exactly for the bundle identifier"
      ),

      // The colliding prefix, with no separator between them. Both
      // applications are installed and each owns its own files.
      SeededLeftover(
        path: "\(preferences)/\(mailer).plist",
        kind: .preferences,
        owner: mailer,
        shape: .file(length: 576),
        reason: "com.example.mail is a prefix of com.example.mailer and claims nothing of it"
      ),
      SeededLeftover(
        path: "\(caches)/\(mailer)",
        kind: .cache,
        owner: mailer,
        shape: .directory(fileLengths: [768]),
        reason: "com.example.mail is a prefix of com.example.mailer and claims nothing of it"
      ),

      // The colliding prefix with a dot separator. A sub identifier looks
      // like it belongs to the shorter application and does not: it is its
      // own installed application and owns its own files.
      SeededLeftover(
        path: "\(preferences)/\(mailHelper).plist",
        kind: .preferences,
        owner: mailHelper,
        shape: .file(length: 320),
        reason: "com.example.mail.helper is installed in its own right, so its files are its own"
      ),
      SeededLeftover(
        path: "\(systemLaunchDaemons)/\(mailHelper).plist",
        kind: .launchDaemon,
        owner: mailHelper,
        shape: .file(length: 288),
        reason: "com.example.mail.helper is installed in its own right, so its daemon is its own"
      ),

      // The colliding prefix with a hyphen separator, also installed.
      SeededLeftover(
        path: "\(preferences)/\(mailPro).plist",
        kind: .preferences,
        owner: mailPro,
        shape: .file(length: 704),
        reason: "com.example.mail-pro is a separate application with a separate identifier"
      ),
      SeededLeftover(
        path: "\(applicationSupport)/\(mailPro)",
        kind: .applicationSupport,
        owner: mailPro,
        shape: .directory(fileLengths: [1_536]),
        reason: "com.example.mail-pro is a separate application with a separate identifier"
      ),

      // A second vendor application, so the shared container below has two
      // plausible claimants rather than one.
      SeededLeftover(
        path: "\(containers)/\(notes)",
        kind: .container,
        owner: notes,
        shape: .directory(fileLengths: [2_560]),
        reason: "the container is named exactly for the bundle identifier"
      ),
      SeededLeftover(
        path: "\(applicationSupport)/\(notes)",
        kind: .applicationSupport,
        owner: notes,
        shape: .directory(fileLengths: [128]),
        reason: "the application support directory is named exactly for the bundle identifier"
      ),
      SeededLeftover(
        path: "\(logs)/\(notes)",
        kind: .log,
        owner: notes,
        shape: .directory(fileLengths: [192]),
        reason: "the log directory is named exactly for the bundle identifier"
      ),

      // The running application's neighbour, whose identifier begins with
      // MacGleam's own. It is somebody else's application and is offered.
      SeededLeftover(
        path: "\(preferences)/\(runningApplicationPrefixSibling).plist",
        kind: .preferences,
        owner: runningApplicationPrefixSibling,
        shape: .file(length: 224),
        reason: "an identifier that begins with MacGleam's own is a different application"
      ),

      // MARK: The paths that belong to nothing

      SeededLeftover(
        path: "\(preferences)/\(mail)_backup.plist",
        kind: .preferences,
        owner: nil,
        shape: .file(length: 800),
        reason: "the bundle identifier is a prefix here, under a separator nobody installed"
      ),
      SeededLeftover(
        path: "\(preferences)/backup-of-\(mail)-settings.plist",
        kind: .preferences,
        owner: nil,
        shape: .file(length: 832),
        reason: "the bundle identifier appears inside the name and does not name the file"
      ),
      SeededLeftover(
        path: "\(preferences)/\(ghost).plist",
        kind: .preferences,
        owner: nil,
        shape: .file(length: 864),
        reason: "the application this file belongs to is not installed"
      ),
      SeededLeftover(
        path: "\(logs)/\(ghost).log",
        kind: .log,
        owner: nil,
        shape: .file(length: 896),
        reason: "the application this file belongs to is not installed"
      ),
      SeededLeftover(
        path: "\(groupContainers)/\(vendorTeam).com.example",
        kind: .container,
        owner: nil,
        shape: .directory(fileLengths: [3_072]),
        reason: "a group container is shared between the vendor's applications and is nobody's"
      ),
      SeededLeftover(
        path: "\(groupContainers)/\(vendorTeam).\(mail)",
        kind: .container,
        owner: nil,
        shape: .directory(fileLengths: [3_584]),
        reason: "a group container named after one application is still shared and still nobody's"
      ),
      SeededLeftover(
        path: "\(caches)/Vendor/\(mail)",
        kind: .cache,
        owner: nil,
        shape: .directory(fileLengths: [1_280]),
        reason: "the directory sits inside a stranger's folder, not in a recognised location"
      ),
      SeededLeftover(
        path: "\(applicationSupport)/\(notes)y",
        kind: .applicationSupport,
        owner: nil,
        shape: .directory(fileLengths: [96]),
        reason: "the name continues past the bundle identifier and nobody installed it"
      ),
    ]
  }

  /// The running application's own leftovers. They exist on the fixture disk,
  /// so "MacGleam is never offered" is a statement about files that are
  /// actually there, and no other application may claim them either.
  static var runningApplicationLeftovers: [SeededLeftover] {
    [
      SeededLeftover(
        path: "\(preferences)/\(runningApplication).plist",
        kind: .preferences,
        owner: nil,
        shape: .file(length: 160),
        reason: "MacGleam is never offered for uninstall, so its own files are nobody's to remove"
      ),
      SeededLeftover(
        path: "\(caches)/\(runningApplication)",
        kind: .cache,
        owner: nil,
        shape: .directory(fileLengths: [320]),
        reason: "MacGleam is never offered for uninstall, so its own files are nobody's to remove"
      ),
    ]
  }

  static var everyLeftover: [SeededLeftover] {
    leftovers + runningApplicationLeftovers
  }

  /// Every path the inventory must attribute to nothing, whatever else it
  /// finds. One false association here is the deleted stranger's file C9 is
  /// written to prevent.
  static var unattributablePaths: Set<AbsolutePath> {
    Set(
      everyLeftover
        .filter { $0.owner == nil }
        .map { ApplicationsFixture.path($0.path) })
  }

  /// The leftovers one application owns, as the inventory must itemise them.
  static func expectedLeftovers(of bundleID: String) -> [SeededLeftover] {
    everyLeftover.filter { $0.owner == bundleID }
  }

  static func expectedLeftoverPaths(of bundleID: String) -> Set<AbsolutePath> {
    Set(expectedLeftovers(of: bundleID).map { ApplicationsFixture.path($0.path) })
  }

  /// The same table with the system domain removed, which is what a scan
  /// without Full Disk Access can see.
  static func expectedLeftoverPathsWithoutFullDiskAccess(
    of bundleID: String
  ) -> Set<AbsolutePath> {
    Set(
      expectedLeftovers(of: bundleID)
        .filter { leftover in
          systemDomainLocations.allSatisfy { !leftover.path.hasPrefix("\($0)/") }
        }
        .map { ApplicationsFixture.path($0.path) })
  }

  // MARK: Seeding

  /// Builds the fixture disk. Every directory a leftover or a bundle implies
  /// is created, and the recognised locations exist even when nothing in them
  /// belongs to anybody, so an empty location is a real answer rather than a
  /// missing directory.
  static func seeded(
    applications: [SeededApplication]? = nil,
    leftovers seededLeftovers: [SeededLeftover]? = nil
  ) async throws -> InMemoryFileSystem {
    let fileSystem = InMemoryFileSystem()
    var seededDirectories = Set<String>()
    var seedByte: UInt8 = 1

    func ensureDirectory(_ directory: String) async {
      var current = ""
      for component in directory.split(separator: "/") {
        current += "/\(component)"
        if seededDirectories.insert(current).inserted {
          await fileSystem.seedDirectory(at: ApplicationsFixture.path(current))
        }
      }
    }

    func seedFile(_ path: String, length: Int) async {
      await ensureDirectory(parentDirectory(of: path))
      await fileSystem.seedFile(
        at: ApplicationsFixture.path(path),
        contents: ApplicationsFixture.contents(seedByte, length: length),
        isExecutable: false,
        created: ApplicationsFixture.createdDate,
        modified: ApplicationsFixture.modifiedDate,
        lastOpened: nil,
        extendedAttributes: [:]
      )
      seedByte &+= 1
    }

    for location in [
      "/Applications", "\(ApplicationsFixture.home)/Applications", preferences, caches,
      containers, groupContainers, applicationSupport, userLaunchAgents, logs,
      systemLaunchDaemons,
    ] {
      await ensureDirectory(location)
    }

    for application in applications ?? installedApplications {
      await ensureDirectory("\(application.bundlePath)/Contents/MacOS")
      let plist = try infoPlistData(for: application)
      await fileSystem.seedFile(
        at: ApplicationsFixture.path(application.infoPlistPath),
        contents: plist,
        isExecutable: false,
        created: ApplicationsFixture.createdDate,
        modified: ApplicationsFixture.modifiedDate,
        lastOpened: nil,
        extendedAttributes: [:]
      )
      await seedFile(application.executablePath, length: application.executableLength)
    }

    for leftover in seededLeftovers ?? everyLeftover {
      switch leftover.shape {
      case .file(let length):
        await seedFile(leftover.path, length: length)
      case .directory(let fileLengths):
        await ensureDirectory(leftover.path)
        for (index, length) in fileLengths.enumerated() {
          await seedFile("\(leftover.path)/entry-\(index).bin", length: length)
        }
      }
    }

    return fileSystem
  }
}

/// The directory a path sits in, as a string, so seeding can create it.
func parentDirectory(of path: String) -> String {
  path.split(separator: "/").dropLast().reduce(into: "") { $0 += "/\($1)" }
}

// MARK: - Byte totals

/// The allocated total for a leftover path, read from the file system rather
/// than written down: a file's own allocated bytes, and for a directory the
/// allocated total of its whole subtree including its own record, which is
/// the same arithmetic C5 states for a directory entry.
func allocatedTotal(
  of path: AbsolutePath,
  on fileSystem: InMemoryFileSystem
) async throws -> UInt64 {
  let record = try await fileSystem.metadata(at: path)
  guard record.isDirectory else { return record.allocatedBytes }
  var total = record.allocatedBytes
  var options = EnumerationOptions.default
  options.includesHiddenFiles = true
  options.descendsIntoPackages = true
  for try await event in fileSystem.enumerate(root: path, options: options) {
    if case .record(let child) = event {
      total += child.allocatedBytes
    }
  }
  return total
}

// MARK: - Contexts

func makeApplicationsSettings(
  deletionMode: Settings.DeletionMode = .trash
) -> Settings {
  Settings(
    deletionMode: deletionMode,
    largeFileThresholdBytes: 1_073_741_824,
    oldFileThresholdDays: 180,
    menuBar: MenuBarPreferences(showsStorage: true, showsMemory: true, showsProcessorLoad: true),
    motion: MotionPreferences(reduceMotionOverride: nil)
  )
}

/// Every context wraps the fixture disk in the reading only value, so the
/// whole suite rests on the compile time property that discovery cannot
/// mutate anything.
func makeScanContext(
  over fileSystem: InMemoryFileSystem,
  rules: RuleCatalog,
  settings: Settings = makeApplicationsSettings(),
  hasFullDiskAccess: Bool = true,
  sessionID: UUID = ApplicationsFixture.sessionID
) -> ScanContext {
  ScanContext(
    sessionID: sessionID,
    fileSystem: ReadingOnlyFileSystem(backing: fileSystem),
    rules: rules,
    settings: settings,
    hasFullDiskAccess: hasFullDiskAccess
  )
}

// MARK: - Running the inventory

/// The whole journey in a line: seed the adversarial disk, run the inventory
/// over it, and hand back both so byte totals can be read from the same file
/// system the answer came from.
func runInventory(
  over fileSystem: InMemoryFileSystem? = nil,
  engine: ApplicationsEngine = ApplicationsEngine(),
  hasFullDiskAccess: Bool = true,
  sessionID: UUID = ApplicationsFixture.sessionID
) async throws -> (entries: [AppInventoryEntry], fileSystem: InMemoryFileSystem) {
  let disk: InMemoryFileSystem
  if let fileSystem {
    disk = fileSystem
  } else {
    disk = try await ApplicationWorld.seeded()
  }
  let context = makeScanContext(
    over: disk,
    rules: try makeSignedApplicationsCatalog(),
    hasFullDiskAccess: hasFullDiskAccess,
    sessionID: sessionID
  )
  return (try await engine.inventory(context: context), disk)
}

func entry(
  for bundleID: String,
  in entries: [AppInventoryEntry]
) -> AppInventoryEntry? {
  entries.first { $0.bundleID == bundleID }
}

func leftoverPaths(of entry: AppInventoryEntry) -> Set<AbsolutePath> {
  Set(entry.leftoverPaths.map(\.path))
}

/// Every path the whole inventory attributes to anybody, the bundles
/// included. The association rule's safety property is stated over this set:
/// nothing in it may be a path that belongs to nobody.
func everyAttributedPath(in entries: [AppInventoryEntry]) -> Set<AbsolutePath> {
  var paths = Set<AbsolutePath>()
  for entry in entries {
    paths.insert(entry.installLocation)
    paths.formUnion(entry.leftoverPaths.map(\.path))
  }
  return paths
}

// MARK: - Running the scan

struct ScanOutcome: Sendable {
  var orderedEvents: [ScanEvent] = []
  var findings: [Finding] = []
  var phases: [ScanPhase] = []
  var counters: [ScanCounters] = []
  var degradedMessages: [String] = []

  var bundleFindings: [Finding] {
    findings.filter {
      if case .applicationBundle = $0.category { return true }
      return false
    }
  }

  var leftoverFindings: [Finding] {
    findings.filter {
      if case .applicationLeftover = $0.category { return true }
      return false
    }
  }

  /// The union of a category's entries across every finding that carries it.
  /// C15 forbids reading a category's whole path list off any single finding,
  /// so every assertion in this suite unions rather than indexing.
  func entryPaths(ofBundle bundleID: String) -> Set<AbsolutePath> {
    Set(
      bundleFindings
        .filter { applicationBundleID(of: $0) == bundleID }
        .flatMap(\.entries)
        .map(\.path))
  }

  func entryPaths(ofLeftoversFor bundleID: String) -> Set<AbsolutePath> {
    Set(
      leftoverFindings
        .filter { applicationBundleID(of: $0) == bundleID }
        .flatMap(\.entries)
        .map(\.path))
  }

  var everyEntryPath: Set<AbsolutePath> {
    Set(findings.flatMap(\.entries).map(\.path))
  }

  var entryCount: Int {
    findings.reduce(0) { $0 + $1.entries.count }
  }

  var reclaimableByteTotal: UInt64 {
    findings.reduce(UInt64(0)) { $0 + $1.byteSize }
  }

  var offeredBundleIDs: Set<String> {
    Set(findings.compactMap(applicationBundleID(of:)))
  }
}

func applicationBundleID(of finding: Finding) -> String? {
  switch finding.category {
  case .applicationBundle(let bundleID): return bundleID
  case .applicationLeftover(let bundleID): return bundleID
  default: return nil
  }
}

func collectScan(
  _ stream: AsyncThrowingStream<ScanEvent, Error>
) async throws -> ScanOutcome {
  var outcome = ScanOutcome()
  for try await event in stream {
    outcome.orderedEvents.append(event)
    switch event {
    case .phase(let phase):
      outcome.phases.append(phase)
    case .progress(let counters):
      outcome.counters.append(counters)
    case .finding(let finding):
      outcome.findings.append(finding)
    case .degraded(let unavailable):
      outcome.degradedMessages.append(unavailable)
    }
  }
  return outcome
}

func runApplicationsScan(
  over fileSystem: InMemoryFileSystem? = nil,
  engine: ApplicationsEngine = ApplicationsEngine(),
  hasFullDiskAccess: Bool = true,
  sessionID: UUID = ApplicationsFixture.sessionID
) async throws -> ScanOutcome {
  let disk: InMemoryFileSystem
  if let fileSystem {
    disk = fileSystem
  } else {
    disk = try await ApplicationWorld.seeded()
  }
  let context = makeScanContext(
    over: disk,
    rules: try makeSignedApplicationsCatalog(),
    hasFullDiskAccess: hasFullDiskAccess,
    sessionID: sessionID
  )
  return try await collectScan(engine.scan(context))
}

// MARK: - Non vacuity

/// Fails unless the inventory actually found the fixture disk.
///
/// Every negative in this target ("no application claimed this file") is
/// satisfied by an engine that finds nothing at all, and an adversarial suite
/// that goes green because the scan came back empty has tested nothing while
/// reading as though it tested everything. So each of those tests starts here.
func expectCompleteInventory(
  _ entries: [AppInventoryEntry],
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(
    Set(entries.map(\.bundleID))
      == Set(ApplicationWorld.offeredApplications.compactMap(\.bundleID)),
    "the inventory did not find the fixture disk, so nothing below this line proves anything",
    sourceLocation: sourceLocation)
  #expect(
    entries.contains { $0.leftoverPaths.isEmpty == false },
    "no application was given a single leftover",
    sourceLocation: sourceLocation)
}

/// The same guard for the streaming side.
func expectCompleteScan(
  _ outcome: ScanOutcome,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(
    outcome.offeredBundleIDs == Set(ApplicationWorld.offeredApplications.compactMap(\.bundleID)),
    "the scan did not find the fixture disk, so nothing below this line proves anything",
    sourceLocation: sourceLocation)
  #expect(
    outcome.everyEntryPath.isEmpty == false,
    "the scan named no path at all",
    sourceLocation: sourceLocation)
}

// MARK: - Assertion helpers

func phaseOrdinal(_ phase: ScanPhase) -> Int {
  switch phase {
  case .indeterminate: return 0
  case .determinate: return 1
  case .settling: return 2
  }
}

func countersAreMonotonic(_ counters: [ScanCounters]) -> Bool {
  zip(counters, counters.dropFirst()).allSatisfy { previous, next in
    previous.filesSeen <= next.filesSeen
      && previous.bytesReclaimable <= next.bytesReclaimable
      && previous.itemCount <= next.itemCount
  }
}

/// A sentence a person can read: words, not a diagnostic dump, and no source
/// identifier where the contract asks for plain language.
func expectPlainSentence(
  _ sentence: String,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(sentence.isEmpty == false, sourceLocation: sourceLocation)
  #expect(sentence.contains(" "), "a sentence has words", sourceLocation: sourceLocation)
  #expect(
    sentence.first?.isUppercase == true,
    "a sentence starts with a capital",
    sourceLocation: sourceLocation)
  #expect(
    sentence.hasSuffix(".") || sentence.hasSuffix("?"),
    "a sentence ends",
    sourceLocation: sourceLocation)
  #expect(sentence.contains("Error Domain=") == false, sourceLocation: sourceLocation)
  #expect(sentence.contains("Optional(") == false, sourceLocation: sourceLocation)
  for identifier in ["AppInventoryEntry", "leftoverPaths", "bundleID", "_"] {
    #expect(
      sentence.contains(identifier) == false,
      "a sentence for a person carries no source identifier",
      sourceLocation: sourceLocation)
  }
}

/// True when the body finishes inside the allowance. Bounds "cancellation
/// ends promptly"; the contract states no latency figure, so two seconds is
/// the generous ceiling. No assertion reads the clock.
func completesPromptly(
  within seconds: Double = 2.0,
  _ body: @escaping @Sendable () async -> Void
) async -> Bool {
  await withTaskGroup(of: Bool.self) { group in
    group.addTask {
      await body()
      return true
    }
    group.addTask {
      try? await Task.sleep(for: .seconds(seconds))
      return false
    }
    let finishedFirst = await group.next() ?? false
    group.cancelAll()
    return finishedFirst
  }
}
