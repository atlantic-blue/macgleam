import Foundation
import Testing

/// The release pipeline, checked as text the way somebody auditing it would.
///
/// What a release does with signing keys is a security property rather than a
/// convention, so these read the workflow itself: the keys come from the
/// repository's secrets, the identity guard runs before anything is signed,
/// and what leaves has been through notarisation and the same assessment a
/// clean machine will make.
@Suite("Release pipeline")
struct ReleasePipelineTests {

  private static let repositoryRoot: URL = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { url.deleteLastPathComponent() }
    return url
  }()

  private func read(_ relativePath: String) throws -> String {
    try String(
      contentsOf: Self.repositoryRoot.appending(path: relativePath), encoding: .utf8)
  }

  private func workflow() throws -> String {
    try read(".github/workflows/release.yml")
  }

  @Test("a release happens on a tag rather than on a merge")
  func aReleaseHappensOnATag() throws {
    let workflow = try workflow()
    #expect(workflow.contains("tags:"))
    #expect(
      workflow.contains("\"v*\""),
      "a release is a version somebody decided on, not a consequence of merging")
  }

  @Test("the identity guard runs before anything is signed")
  func theIdentityGuardRunsBeforeSigning() throws {
    let workflow = try workflow()
    let guardStep = try #require(workflow.range(of: "GleamReleaseGuard"))
    let importStep = try #require(workflow.range(of: "Import the signing identity"))
    #expect(
      guardStep.lowerBound < importStep.lowerBound,
      """
      the helper admits exactly one client and every guarantee it makes assumes \
      that check bites, so a placeholder identity has to stop the release \
      before a signature makes it look finished
      """)
  }

  @Test("the tests run, and an empty run stops the release")
  func theTestsRunAndAnEmptyRunStopsTheRelease() throws {
    let workflow = try workflow()
    #expect(workflow.contains("swift test"))
    #expect(
      workflow.contains("refusing to release on that"),
      "a suite that executed nothing reports success just the same")
  }

  @Test("everything is signed, notarised and stapled")
  func everythingIsSignedNotarisedAndStapled() throws {
    let workflow = try workflow()
    #expect(workflow.contains("--options runtime"), "the hardened runtime, which notarising needs")
    #expect(workflow.contains("notarytool submit"))
    #expect(
      workflow.contains("--wait"), "a submission nobody waited for is a submission nobody read")
    #expect(workflow.contains("stapler staple"))
  }

  @Test("the helper is signed before the app that seals it")
  func theHelperIsSignedBeforeTheAppThatSealsIt() throws {
    let workflow = try workflow()
    let helper = try #require(workflow.range(of: "MacGleam.app/Contents/MacOS/GleamHelper"))
    let app = try #require(workflow.range(of: "\n            dist/MacGleam.app\n"))
    #expect(
      helper.lowerBound < app.lowerBound,
      """
      signing the app seals the hashes of everything inside it, so a nested \
      executable signed afterwards invalidates the signature it is sealed into
      """)
  }

  @Test("what leaves has passed the assessment a clean machine will make")
  func whatLeavesHasPassedTheAssessment() throws {
    let workflow = try workflow()
    #expect(workflow.contains("spctl --assess"))
    #expect(workflow.contains("codesign --verify"))
  }

  @Test("no signing key is ever written into the repository")
  func noSigningKeyIsWrittenIntoTheRepository() throws {
    let workflow = try workflow()
    for secret in [
      "secrets.DEVELOPER_ID_CERTIFICATE",
      "secrets.APP_STORE_CONNECT_KEY",
      "secrets.SPARKLE_PRIVATE_KEY",
    ] {
      #expect(workflow.contains(secret), "\(secret) comes from the repository's secrets")
    }
    #expect(!workflow.contains("BEGIN PRIVATE KEY"))
    #expect(
      workflow.contains("rm -f certificate.p12"),
      "the certificate is removed after import rather than left on the runner")
    #expect(workflow.contains("rm -f connect.p8"))
  }

  @Test("the appcast entry is signed with the key that only the pipeline has")
  func theAppcastEntryIsSignedWithThePipelinesKey() throws {
    let workflow = try workflow()
    #expect(workflow.contains("GleamAppcast"))
    #expect(
      workflow.contains("No appcast signing key is configured"),
      "a release with no key stops rather than publishing something unsigned")
  }

  @Test("the appcast tool takes its key from the environment and from no file")
  func theAppcastToolTakesItsKeyFromTheEnvironment() throws {
    let source = try read("Sources/GleamAppcast/main.swift")
    #expect(source.contains("ProcessInfo.processInfo.environment[\"SPARKLE_PRIVATE_KEY\"]"))
    #expect(
      !source.contains("--key "),
      "a key taken from a path is a key somebody keeps on a laptop")
  }

  @Test("the identity in the tree is still a placeholder, so a release today would stop")
  func theIdentityInTheTreeIsStillAPlaceholder() throws {
    let policy = try read("Sources/GleamHelperCore/HelperPolicy.swift")
    #expect(
      policy.contains("DEVELOPERIDPENDING"),
      """
      the Developer ID does not exist yet. While that is true the guard is what \
      stops a release going out with a helper that admits nobody, and this test \
      is what says the guard still has something to catch
      """)
  }
}
