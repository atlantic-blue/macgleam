import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// Fixtures for C31's destination stage: the check that says where the helper
/// may be asked to write, as opposed to what it may be asked to touch.
///
/// Every value here is fixed. Nothing reads a wall clock, nothing opens a
/// connection, nothing touches a disk, so a failing case reproduces exactly.
enum ArchiveFixture {

  // MARK: Identifiers

  /// The item the archive requests in these tests belong to. The store mints
  /// it before it asks, and it is the last component of the payload path and
  /// the correlation identifier of every reply (C18, C30).
  static let itemID = HelperFixture.uuid(0x10)
  /// A second item, for the case where the path names one archive and the
  /// request names another.
  static let otherItemID = HelperFixture.uuid(0x11)

  // MARK: The legitimate store

  /// `HelperFixture.safetyNetStore` is the store directory the app places
  /// inside the connecting user's home. C18 names the payload path
  /// `payloads/<item identifier>` under it, and the helper chooses none of it.
  static let payloadsDirectory = path(HelperFixture.safetyNetStore.value + "/payloads")

  /// The one destination the contract admits for `itemID`.
  static let legitimatePayload = payload(for: itemID)

  static func payload(for itemID: UUID, in directory: AbsolutePath = payloadsDirectory)
    -> AbsolutePath
  {
    path(directory.value + "/" + itemID.uuidString)
  }

  /// Absolute paths built the way the fixtures build them. Kept separate from
  /// `HelperFixture.path` only so this file reads on its own.
  static func path(_ value: String) -> AbsolutePath {
    AbsolutePath(normalising: value)
  }

  // MARK: Requests

  static func archive(
    target: AbsolutePath = HelperFixture.systemAllowedTarget,
    to storedPath: AbsolutePath,
    itemID: UUID = ArchiveFixture.itemID
  ) -> HelperRequest {
    .archiveIntoSafetyNet(target: target, storedPath: storedPath, itemID: itemID)
  }

  static func describe(_ storedPath: AbsolutePath, itemID: UUID = ArchiveFixture.itemID)
    -> HelperRequest
  {
    .describeArchived(storedPath: storedPath, itemID: itemID)
  }

  static func restore(_ storedPath: AbsolutePath, itemID: UUID = ArchiveFixture.itemID)
    -> HelperRequest
  {
    .restoreArchived(storedPath: storedPath, itemID: itemID)
  }

  static func discard(_ storedPath: AbsolutePath, itemID: UUID = ArchiveFixture.itemID)
    -> HelperRequest
  {
    .discardArchived(storedPath: storedPath, itemID: itemID)
  }

  /// Every request in C30's archive family naming one stored path. The
  /// destination stage is stated for the family rather than for the archive
  /// alone, and `discardArchived` is the one that deletes, so a path check
  /// missing there is an arbitrary root delete rather than an arbitrary root
  /// write.
  static func wholeFamily(naming storedPath: AbsolutePath, itemID: UUID = ArchiveFixture.itemID)
    -> [HelperRequest]
  {
    [
      archive(to: storedPath, itemID: itemID),
      describe(storedPath, itemID: itemID),
      restore(storedPath, itemID: itemID),
      discard(storedPath, itemID: itemID),
    ]
  }
}

// MARK: - What the helper can see while it decides

/// The file system facts C31's destination stage needs, and no others. The
/// stage asks two questions of a path: does this directory already exist, and
/// is this component a symbolic link. Both are answered from a fixed table
/// here, so the stage is exercised with no disk, no temporary directory and no
/// daemon.
///
/// The double answers about the path itself and follows nothing, which is the
/// only way an answer about a symbolic link means anything.
struct HelperPathTable: HelperPathInspecting {
  var existingDirectories: Set<String>
  var symbolicLinks: Set<String> = []

  func directoryExists(at path: AbsolutePath) -> Bool {
    existingDirectories.contains(path.value)
  }

  func isSymbolicLink(at path: AbsolutePath) -> Bool {
    symbolicLinks.contains(path.value)
  }

  func markingSymbolicLink(at path: AbsolutePath) -> HelperPathTable {
    var copy = self
    copy.symbolicLinks.insert(path.value)
    return copy
  }

  func removingDirectory(at path: AbsolutePath) -> HelperPathTable {
    var copy = self
    copy.existingDirectories.remove(path.value)
    return copy
  }

  /// The world these tests decide in. It holds the legitimate store, and it
  /// also holds an existing, plain directory as the parent of every attack
  /// destination in the sweep.
  ///
  /// That second half is the point. If an attack path's parent were absent,
  /// the destination stage could refuse it under the parent rule and the sweep
  /// would go green with the home and shape rules never written.
  /// `everyRefusedDestinationHasAnExistingPlainParent` holds the fixture to it.
  static let standard = HelperPathTable(existingDirectories: Set(directories))

  static let directories: [String] = [
    "/",
    "/Applications",
    "/Applications/payloads",
    "/Library",
    "/Library/LaunchAgents",
    "/Library/LaunchDaemons",
    "/Library/LaunchDaemons/payloads",
    "/Users",
    "/Users/julian",
    "/Users/julian/Blocked",
    "/Users/julian/Blocked/payloads",
    "/Users/julian/Library",
    "/Users/julian/Library/Application Support",
    "/Users/julian/Library/Application Support/MacGleam",
    "/Users/julian/Library/Application Support/MacGleam/SafetyNet",
    "/Users/julian/Library/Application Support/MacGleam/SafetyNet/Xpayloads",
    "/Users/julian/Library/Application Support/MacGleam/SafetyNet/payloads",
    "/Users/julian/Library/Application Support/MacGleam/SafetyNet/payloads/"
      + ArchiveFixture.itemID.uuidString,
    "/Users/julian/Library/Application Support/MacGleam/SafetyNet/payloadsElsewhere",
    "/Users/julian/Library/LaunchAgents",
    "/Users/julian2",
    "/Users/julian2/Library",
    "/Users/julian2/Library/Application Support",
    "/Users/julian2/Library/Application Support/MacGleam",
    "/Users/julian2/Library/Application Support/MacGleam/SafetyNet",
    "/Users/julian2/Library/Application Support/MacGleam/SafetyNet/payloads",
    "/Users/julianne",
    "/Users/julianne/Library",
    "/Users/julianne/Library/Application Support",
    "/Users/julianne/Library/Application Support/MacGleam",
    "/Users/julianne/Library/Application Support/MacGleam/SafetyNet",
    "/Users/julianne/Library/Application Support/MacGleam/SafetyNet/payloads",
  ]
}

// MARK: - One destination and the rule that refuses it

/// A stored path the destination stage must refuse, carried with the clause it
/// offends so a failure names the rule rather than a path.
struct ArchiveDestinationCase: Sendable, CustomStringConvertible {
  let rule: String
  let storedPath: AbsolutePath
  /// The directory the destination sits in, which the fixture keeps present
  /// and plain so the refusal cannot come from the parent rule instead.
  let parent: AbsolutePath

  var description: String { "\(rule): \(storedPath.value)" }

  init(_ rule: String, _ storedPath: String, parent: String) {
    self.rule = rule
    self.storedPath = ArchiveFixture.path(storedPath)
    self.parent = ArchiveFixture.path(parent)
  }
}

extension ArchiveDestinationCase {

  static let store = HelperFixture.safetyNetStore.value
  static let payloads = ArchiveFixture.payloadsDirectory.value
  static let item = ArchiveFixture.itemID.uuidString
  static let otherItem = ArchiveFixture.otherItemID.uuidString

  /// Destinations outside the connecting user's home. Each is somewhere a
  /// root daemon writing a file would matter, and none of them is on the
  /// baseline denylist, which is exactly why the target denylist cannot stand
  /// in for this stage.
  static let outsideTheUsersHome: [ArchiveDestinationCase] = [
    ArchiveDestinationCase(
      "a launch daemon directory, where a written file runs as root at boot",
      "/Library/LaunchDaemons/\(item)",
      parent: "/Library/LaunchDaemons"),
    ArchiveDestinationCase(
      "a launch daemon directory dressed in the shape of a store payload",
      "/Library/LaunchDaemons/payloads/\(item)",
      parent: "/Library/LaunchDaemons/payloads"),
    ArchiveDestinationCase(
      "the system wide launch agents directory",
      "/Library/LaunchAgents/com.example.persist.plist",
      parent: "/Library/LaunchAgents"),
    ArchiveDestinationCase(
      "the applications directory",
      "/Applications/\(item)",
      parent: "/Applications"),
    ArchiveDestinationCase(
      "the applications directory dressed in the shape of a store payload",
      "/Applications/payloads/\(item)",
      parent: "/Applications/payloads"),
    ArchiveDestinationCase(
      "the root of the volume",
      "/\(item)",
      parent: "/"),
    ArchiveDestinationCase(
      "the directory holding every user's home",
      "/Users/\(item)",
      parent: "/Users"),
  ]

  /// Homes belonging to somebody else whose name merely begins with the
  /// connecting user's. A containment check written on characters admits every
  /// one of these; a check written on path components admits none. This
  /// codebase has already paid for the difference once, in the leftover
  /// association rule.
  static let anotherUsersHomeSharingAPrefix: [ArchiveDestinationCase] = [
    ArchiveDestinationCase(
      "another user's store, whose home name extends the connecting user's",
      "/Users/julianne/Library/Application Support/MacGleam/SafetyNet/payloads/\(item)",
      parent: "/Users/julianne/Library/Application Support/MacGleam/SafetyNet/payloads"),
    ArchiveDestinationCase(
      "another user's store, whose home name is the connecting user's plus a digit",
      "/Users/julian2/Library/Application Support/MacGleam/SafetyNet/payloads/\(item)",
      parent: "/Users/julian2/Library/Application Support/MacGleam/SafetyNet/payloads"),
  ]

  /// Destinations inside the connecting user's home that are not the shape of
  /// a store payload. The home check alone admits all of these, so they are
  /// what separates a containment check from the shape rule.
  static let insideTheHomeButNotAStorePayload: [ArchiveDestinationCase] = [
    ArchiveDestinationCase(
      "the user's own launch agents directory, where a written plist runs at login",
      "/Users/julian/Library/LaunchAgents/com.example.persist.plist",
      parent: "/Users/julian/Library/LaunchAgents"),
    ArchiveDestinationCase(
      "the home directory itself",
      "/Users/julian/\(item)",
      parent: "/Users/julian"),
    ArchiveDestinationCase(
      "the store's own root, which is where the removal shaped archive used to land",
      "\(store)/\(item)",
      parent: store),
    ArchiveDestinationCase(
      "the payloads directory itself, which is a directory and not a payload",
      payloads,
      parent: store),
    ArchiveDestinationCase(
      "a path below a payload rather than directly inside the payloads directory",
      "\(payloads)/\(item)/inner",
      parent: "\(payloads)/\(item)"),
    ArchiveDestinationCase(
      "a directory whose name merely begins with payloads",
      "\(store)/payloadsElsewhere/\(item)",
      parent: "\(store)/payloadsElsewhere"),
    ArchiveDestinationCase(
      "a directory whose name merely ends with payloads",
      "\(store)/Xpayloads/\(item)",
      parent: "\(store)/Xpayloads"),
  ]

  /// Destinations of the right shape whose last component is not the item the
  /// request names, so the reply, the log line and the manifest entry would
  /// name three different things.
  static let notTheRequestsItem: [ArchiveDestinationCase] = [
    ArchiveDestinationCase(
      "another item's payload",
      "\(payloads)/\(otherItem)",
      parent: payloads),
    ArchiveDestinationCase(
      "a name that merely begins with the item identifier",
      "\(payloads)/\(item)x",
      parent: payloads),
    ArchiveDestinationCase(
      "a name that merely ends with the item identifier",
      "\(payloads)/x\(item)",
      parent: payloads),
  ]

  /// A destination inside the home, of the right shape, sitting in a subtree
  /// the helper's own denylist blocks.
  static let denylisted: [ArchiveDestinationCase] = [
    ArchiveDestinationCase(
      "a denylisted subtree of the connecting user's home",
      "/Users/julian/Blocked/payloads/\(item)",
      parent: "/Users/julian/Blocked/payloads")
  ]

  /// Every case above, for the tests that sweep the whole surface.
  static let everyRefusal: [ArchiveDestinationCase] =
    outsideTheUsersHome
    + anotherUsersHomeSharingAPrefix
    + insideTheHomeButNotAStorePayload
    + notTheRequestsItem
    + denylisted
}

// MARK: - The policy under test

/// The construction surface these tests demand of the concrete C31 policy.
///
/// It is `makeHelperPolicy`'s surface plus one collaborator, `paths`, which is
/// how the destination stage learns whether a parent exists and whether a
/// component is a symbolic link. It carries no default: a policy that could be
/// built without one would be a policy that trusts every path it is handed,
/// which is the state this slice exists to end.
func makeArchivePolicy(
  denylist: Denylist,
  paths: HelperPathTable = .standard,
  expectedClient: ExpectedClientIdentity = HelperFixture.expectedClient,
  contractVersion: UInt16 = HelperContract.version,
  ownership: any PathOwnershipPolicy = HelperSystemRootsOwnershipPolicy(),
  environment: OwnershipEnvironment = HelperFixture.environment,
  launchItems: any HelperLaunchItemLocating = HelperLaunchItemTable()
) -> HelperConnectionPolicy {
  HelperConnectionPolicy(
    expectedClient: expectedClient,
    contractVersion: contractVersion,
    denylist: denylist,
    ownership: ownership,
    environment: environment,
    launchItems: launchItems,
    paths: paths
  )
}

/// The same policy on a connection that has already agreed a version, which is
/// the state every request after the first one arrives in.
func makeHandshakenArchivePolicy(
  denylist: Denylist,
  paths: HelperPathTable = .standard,
  expectedClient: ExpectedClientIdentity = HelperFixture.expectedClient,
  ownership: any PathOwnershipPolicy = HelperSystemRootsOwnershipPolicy()
) throws -> HelperConnectionPolicy {
  let policy = makeArchivePolicy(
    denylist: denylist,
    paths: paths,
    expectedClient: expectedClient,
    ownership: ownership)
  try #require(
    policy.admit(HelperFixture.handshake(), from: HelperFixture.trustedClient) == .admitted,
    "the fixture handshake must be admitted before a test can exercise a later stage")
  return policy
}
