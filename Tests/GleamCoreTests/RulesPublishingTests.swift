import Foundation
import Testing

/// The publisher and its workflow, checked as text.
///
/// The rules key decides what every installation of MacGleam will delete
/// without asking again, so where it lives is a security property rather than
/// a convention. These read the repository the way somebody auditing it would:
/// the workflow takes the key from the repository's secrets, refuses to run
/// without it, and no key material sits in the tree.
@Suite("Rules publishing")
struct RulesPublishingTests {

  private static let repositoryRoot: URL = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { url.deleteLastPathComponent() }
    return url
  }()

  private func read(_ relativePath: String) throws -> String {
    let url = Self.repositoryRoot.appending(path: relativePath)
    return try String(contentsOf: url, encoding: .utf8)
  }

  @Test("the publish workflow exists and is run deliberately rather than on a push")
  func theWorkflowIsRunDeliberately() throws {
    let workflow = try read(".github/workflows/publish-rules.yml")
    #expect(workflow.contains("workflow_dispatch"))
    #expect(
      !workflow.contains("on:\n  push"),
      """
      a rules update changes what every installation deletes without asking \
      again, so it is somebody's deliberate act rather than a consequence of a \
      merge
      """)
  }

  @Test("the workflow signs with the pipeline's secret and refuses to run without it")
  func theWorkflowSignsWithTheSecret() throws {
    let workflow = try read(".github/workflows/publish-rules.yml")
    #expect(workflow.contains("secrets.RULES_SIGNING_KEY"))
    #expect(
      workflow.contains("Refuse an unsigned publish"),
      "a publish with no key must stop rather than produce something unsigned")
  }

  @Test("the workflow verifies the manifest the way the app will, before publishing it")
  func theWorkflowVerifiesBeforePublishing() throws {
    let workflow = try read(".github/workflows/publish-rules.yml")
    #expect(workflow.contains("--verify"))
  }

  @Test("the publisher takes the key from the environment and from no file")
  func thePublisherTakesTheKeyFromTheEnvironment() throws {
    let source = try read("Sources/GleamRulesPublisher/main.swift")
    #expect(source.contains("ProcessInfo.processInfo.environment[\"RULES_SIGNING_KEY\"]"))
    #expect(
      !source.contains("--key"),
      """
      a key taken from a path is a key somebody keeps on a laptop, and the \
      whole point of this one is that only the pipeline has it
      """)
  }

  @Test("no private key material sits in the repository")
  func noPrivateKeyMaterialSitsInTheRepository() throws {
    for path in [
      "Sources/GleamRulesPublisher/main.swift",
      ".github/workflows/publish-rules.yml",
      "rules/catalog.json",
    ] {
      let contents = try read(path)
      #expect(!contents.contains("BEGIN PRIVATE KEY"))
      #expect(!contents.contains("PrivateKey(rawRepresentation: Data(["))
    }
  }

  @Test("the catalogue the workflow signs carries no signature of its own")
  func theCatalogueCarriesNoSignatureOfItsOwn() throws {
    let catalog = try read("rules/catalog.json")
    #expect(catalog.contains("\"signature\": \"\""))
    #expect(
      catalog.contains("/System"),
      "the published catalogue still carries the protections the baseline has")
  }
}
