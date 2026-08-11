import Foundation
import GleamCore
import GleamHelperCore
import Testing

/// C31's destination stage. The helper checks where it is being asked to write
/// as carefully as what it is being asked to touch.
///
/// Without this stage the admission policy reads the target of a request and
/// nothing else, so a client past the identity check can name any directory at
/// all and have a root daemon put a system file in it. The denylist does not
/// stand in for it: the destinations that matter most are places the baseline
/// never blocked, because nothing in the product ever removes them.
/// `/Library/LaunchDaemons` is the plainest of those, and it is where a written
/// file runs as root at boot.
///
/// The identity check is the only thing standing in the way today, and defence
/// in depth exists precisely so that is never the only thing standing in the
/// way.
@Suite("Helper policy archive destination")
struct HelperPolicyArchiveDestinationTests {

  private func policy(
    paths: HelperPathTable = .standard
  ) async throws -> HelperConnectionPolicy {
    try makeHandshakenArchivePolicy(
      denylist: try await HelperFixture.verifiedDenylist(), paths: paths)
  }

  // MARK: The destinations the contract admits

  @Test("the payload path the store named is admitted")
  func theStorePayloadPathIsAdmitted() async throws {
    let admission = try await policy().admit(
      ArchiveFixture.archive(to: ArchiveFixture.legitimatePayload),
      from: HelperFixture.trustedClient)
    #expect(
      admission == .admitted,
      """
      a check that refuses the one destination the store actually names is \
      vacuous, and vacuous is how a security check most often ends up
      """)
  }

  @Test(
    "every item gets its own admitted payload path",
    arguments: [0x20, 0x21, 0x22, 0x23] as [UInt8]
  )
  func everyItemGetsItsOwnAdmittedPayloadPath(suffix: UInt8) async throws {
    let itemID = HelperFixture.uuid(suffix)
    let admission = try await policy().admit(
      ArchiveFixture.archive(to: ArchiveFixture.payload(for: itemID), itemID: itemID),
      from: HelperFixture.trustedClient)
    #expect(admission == .admitted, "nothing about one fixture identifier may be load bearing")
  }

  @Test(
    "the target being archived does not change what the destination stage decides",
    arguments: [
      "/Library/Caches/com.example.helper",
      "/Library/Application Support/com.example.helper",
      "/Applications/Example.app",
    ]
  )
  func theTargetDoesNotChangeTheDestinationDecision(target: String) async throws {
    let admission = try await policy().admit(
      ArchiveFixture.archive(
        target: HelperFixture.path(target), to: ArchiveFixture.legitimatePayload),
      from: HelperFixture.trustedClient)
    #expect(admission == .admitted)
  }

  @Test("two requests differing only in the destination are decided differently")
  func twoRequestsDifferingOnlyInTheDestinationAreDecidedDifferently() async throws {
    let policy = try await policy()
    let intoTheStore = ArchiveFixture.archive(to: ArchiveFixture.legitimatePayload)
    let intoALaunchDaemonDirectory = ArchiveFixture.archive(
      to: ArchiveFixture.path("/Library/LaunchDaemons/\(ArchiveFixture.itemID.uuidString)"))
    #expect(policy.admit(intoTheStore, from: HelperFixture.trustedClient) == .admitted)
    #expect(
      policy.admit(intoALaunchDaemonDirectory, from: HelperFixture.trustedClient)
        == .refused(.destinationRejected),
      """
      same client, same policy, same target, same item: the destination is the \
      only thing that differs, so it is the only thing that can have decided it
      """)
  }

  // MARK: The destinations the contract refuses

  @Test(
    "a destination outside the connecting user's home is refused",
    arguments: ArchiveDestinationCase.outsideTheUsersHome
  )
  func aDestinationOutsideTheUsersHomeIsRefused(destination: ArchiveDestinationCase) async throws {
    let admission = try await policy().admit(
      ArchiveFixture.archive(to: destination.storedPath), from: HelperFixture.trustedClient)
    #expect(admission == .refused(.destinationRejected), "\(destination.rule)")
  }

  @Test(
    "another user's home whose name merely begins with the connecting user's is refused",
    arguments: ArchiveDestinationCase.anotherUsersHomeSharingAPrefix
  )
  func anotherUsersHomeSharingAPrefixIsRefused(destination: ArchiveDestinationCase) async throws {
    let admission = try await policy().admit(
      ArchiveFixture.archive(to: destination.storedPath), from: HelperFixture.trustedClient)
    #expect(
      admission == .refused(.destinationRejected),
      """
      \(destination.rule). Containment is a check on path components, never on \
      characters: "/Users/julianne" begins with "/Users/julian" and is somebody \
      else's home
      """)
  }

  @Test(
    "a destination inside the home that is not the shape of a store payload is refused",
    arguments: ArchiveDestinationCase.insideTheHomeButNotAStorePayload
  )
  func aDestinationInsideTheHomeThatIsNotAPayloadIsRefused(
    destination: ArchiveDestinationCase
  ) async throws {
    let admission = try await policy().admit(
      ArchiveFixture.archive(to: destination.storedPath), from: HelperFixture.trustedClient)
    #expect(admission == .refused(.destinationRejected), "\(destination.rule)")
  }

  @Test(
    "a payload path naming an item the request does not is refused",
    arguments: ArchiveDestinationCase.notTheRequestsItem
  )
  func aPayloadPathNamingAnotherItemIsRefused(
    destination: ArchiveDestinationCase
  ) async throws {
    let admission = try await policy().admit(
      ArchiveFixture.archive(to: destination.storedPath), from: HelperFixture.trustedClient)
    #expect(
      admission == .refused(.destinationRejected),
      """
      \(destination.rule). The reply, the helper's log line and the manifest \
      entry all name one archive, which they cannot do if the path and the \
      request disagree about which item it is
      """)
  }

  @Test(
    "a destination the helper's own denylist blocks is refused",
    arguments: ArchiveDestinationCase.denylisted
  )
  func aDenylistedDestinationIsRefused(destination: ArchiveDestinationCase) async throws {
    let admission = try await policy().admit(
      ArchiveFixture.archive(to: destination.storedPath), from: HelperFixture.trustedClient)
    #expect(admission == .refused(.destinationRejected), "\(destination.rule)")
  }

  @Test(
    "every request in the archive family refuses every one of these destinations",
    arguments: ArchiveDestinationCase.everyRefusal
  )
  func everyRequestInTheFamilyRefusesEveryRefusedDestination(
    destination: ArchiveDestinationCase
  ) async throws {
    let policy = try await policy()
    for request in ArchiveFixture.wholeFamily(naming: destination.storedPath) {
      #expect(
        policy.admit(request, from: HelperFixture.trustedClient)
          == .refused(.destinationRejected),
        """
        \(destination.rule). The stage is stated for the family, and \
        discardArchived is the one that deletes: a path check missing there is \
        an arbitrary root delete rather than an arbitrary root write
        """)
    }
  }

  // MARK: Symbolic links and directories that do not exist

  /// Every ancestor of the legitimate payload path, and the payload itself.
  /// A symbolic link at any one of them makes every other check on the string
  /// meaningless, because the string is then not where the write lands.
  static let componentsOfTheLegitimatePayload: [String] = {
    let components = ArchiveFixture.legitimatePayload.value.split(separator: "/").map(String.init)
    return components.indices.map { index in
      "/" + components[0...index].joined(separator: "/")
    }
  }()

  @Test(
    "a symbolic link in any component of the destination is refused",
    arguments: componentsOfTheLegitimatePayload
  )
  func aSymbolicLinkInAnyComponentIsRefused(component: String) async throws {
    let linked = HelperPathTable.standard.markingSymbolicLink(
      at: ArchiveFixture.path(component))
    let admission = try await policy(paths: linked).admit(
      ArchiveFixture.archive(to: ArchiveFixture.legitimatePayload),
      from: HelperFixture.trustedClient)
    #expect(
      admission == .refused(.destinationRejected),
      """
      "\(component)" is a symbolic link, so every check made on the rest of the \
      string describes a path the write would not land on
      """)
  }

  @Test("a destination whose parent does not exist is refused rather than created")
  func aDestinationWhoseParentDoesNotExistIsRefused() async throws {
    let withoutThePayloadsDirectory = HelperPathTable.standard.removingDirectory(
      at: ArchiveFixture.payloadsDirectory)
    let admission = try await policy(paths: withoutThePayloadsDirectory).admit(
      ArchiveFixture.archive(to: ArchiveFixture.legitimatePayload),
      from: HelperFixture.trustedClient)
    #expect(
      admission == .refused(.destinationRejected),
      """
      the helper creates no directory for a destination, which is what makes \
      the rest of this stage enforceable: a helper that creates the tree it was \
      asked for can be asked for any tree at all
      """)
  }

  @Test("a destination in a tree that exists nowhere is refused for the whole family")
  func aDestinationInATreeThatExistsNowhereIsRefused() async throws {
    let policy = try await policy()
    let invented = ArchiveFixture.path(
      "/Users/julian/Library/Invented/payloads/\(ArchiveFixture.itemID.uuidString)")
    for request in ArchiveFixture.wholeFamily(naming: invented) {
      #expect(
        policy.admit(request, from: HelperFixture.trustedClient)
          == .refused(.destinationRejected))
    }
  }

  // MARK: A traversal never reaches the policy at all

  @Test(
    "a stored path with a traversal cannot be constructed",
    arguments: [
      "/Users/julian/Library/Application Support/MacGleam/SafetyNet/payloads/../../../../../../Library/LaunchDaemons/com.example.persist.plist",
      "/Users/julian/../../Library/LaunchDaemons/com.example.persist.plist",
      "/Users/julian/./Library/LaunchAgents/com.example.persist.plist",
      "../../Library/LaunchDaemons/com.example.persist.plist",
    ]
  )
  func aStoredPathWithATraversalCannotBeConstructed(value: String) {
    #expect(
      AbsolutePath(validating: value) == nil,
      "the crossing type refuses a traversal rather than normalising one silently")
  }

  @Test("a stored path with a traversal does not survive the wire")
  func aStoredPathWithATraversalDoesNotSurviveTheWire() throws {
    let codec = HelperWireCodec()
    let valid = try codec.encode(ArchiveFixture.archive(to: ArchiveFixture.legitimatePayload))
    let mutated = try helperWirePayload(
      valid,
      replacingBodyField: "storedPath",
      with:
        "/Users/julian/Library/Application Support/MacGleam/SafetyNet/payloads/../../../../../../Library/LaunchDaemons/com.example.persist.plist"
    )
    #expect(throws: (any Error).self) {
      try codec.decodeRequest(from: mutated)
    }
  }

  // MARK: A removal is not an archive

  @Test("a removal into the connecting user's trash is still admitted")
  func aRemovalIntoTheUsersTrashIsStillAdmitted() async throws {
    let admission = try await policy().admit(
      HelperFixture.remove(
        HelperFixture.systemAllowedTarget,
        destination: .userTrash(userHome: HelperFixture.userHome)),
      from: HelperFixture.trustedClient)
    #expect(
      admission == .admitted,
      "the destination stage is stated for the archive family, and a removal has no stored path")
  }

  @Test("a permanent removal is still admitted")
  func aPermanentRemovalIsStillAdmitted() async throws {
    let admission = try await policy().admit(
      HelperFixture.remove(HelperFixture.systemAllowedTarget, destination: .permanent),
      from: HelperFixture.trustedClient)
    #expect(admission == .admitted)
  }

  // MARK: The fixture cannot pass a case for the wrong reason

  @Test(
    "every refused destination has a parent that exists and is not a symbolic link",
    arguments: ArchiveDestinationCase.everyRefusal
  )
  func everyRefusedDestinationHasAnExistingPlainParent(
    destination: ArchiveDestinationCase
  ) {
    #expect(
      HelperPathTable.standard.directoryExists(at: destination.parent),
      """
      "\(destination.parent.value)" must exist in the fixture, or the stage \
      could refuse "\(destination.storedPath.value)" under the parent rule and \
      this sweep would go green with the home and shape rules never written
      """)
    #expect(HelperPathTable.standard.isSymbolicLink(at: destination.parent) == false)
  }

  @Test(
    "no refused destination normalises onto the one the contract admits",
    arguments: ArchiveDestinationCase.everyRefusal
  )
  func noRefusedDestinationNormalisesOntoTheAdmittedOne(
    destination: ArchiveDestinationCase
  ) {
    #expect(destination.storedPath != ArchiveFixture.legitimatePayload)
  }

  @Test("the sweep covers a launch daemon directory, which the baseline denylist does not block")
  func theSweepCoversALaunchDaemonDirectory() async throws {
    let denylist = try await HelperFixture.verifiedDenylist()
    let launchDaemons = ArchiveFixture.path("/Library/LaunchDaemons")
    #expect(
      denylist.blocks(launchDaemons) == false,
      """
      if the denylist blocked it, the sweep would prove nothing about the \
      destination stage; it does not, which is why the stage has to exist
      """)
    #expect(
      ArchiveDestinationCase.everyRefusal.contains {
        $0.storedPath.isDescendant(of: launchDaemons)
      })
  }
}
