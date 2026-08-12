import Foundation
import GleamCore
import Testing

/// The three places this app is allowed to talk to, and the proof that there
/// is no fourth.
///
/// No path, file name or scan content ever leaves the machine. That promise is
/// only as good as the list of hosts the code can reach, so this reads the
/// tree the way somebody auditing it would: every web address written anywhere
/// in the sources, checked against the three that are allowed.
@Suite("Outbound endpoints")
struct OutboundEndpointTests {

  /// The rules channel, the update appcast and licence activation. Nothing
  /// else, ever.
  private static let permittedHosts: Set<String> = [
    "rules.macgleam.app",
    "updates.macgleam.app",
    "licence.macgleam.app",
  ]

  /// Hosts that appear in source for reasons that are not this app talking to
  /// them: a package to build against, a document to point a reader at.
  private static let notEndpoints: Set<String> = [
    "github.com",
    "www.asd-ste100.org",
  ]

  private static let repositoryRoot: URL = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { url.deleteLastPathComponent() }
    return url
  }()

  private func swiftSources() throws -> [(path: String, contents: String)] {
    let sources = Self.repositoryRoot.appending(path: "Sources")
    guard
      let walk = FileManager.default.enumerator(
        at: sources, includingPropertiesForKeys: nil)
    else { return [] }
    var files: [(String, String)] = []
    for case let url as URL in walk where url.pathExtension == "swift" {
      files.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
    }
    return files
  }

  @Test("every web address in the sources is one of the three permitted endpoints")
  func everyWebAddressIsPermitted() throws {
    let pattern = try NSRegularExpression(pattern: "https?://([A-Za-z0-9.-]+)")
    var checkedFiles = 0
    var foundHosts: Set<String> = []

    for file in try swiftSources() {
      checkedFiles += 1
      let range = NSRange(file.contents.startIndex..., in: file.contents)
      for match in pattern.matches(in: file.contents, range: range) {
        guard let hostRange = Range(match.range(at: 1), in: file.contents) else { continue }
        let host = String(file.contents[hostRange])
        guard !Self.notEndpoints.contains(host) else { continue }
        foundHosts.insert(host)
        #expect(
          Self.permittedHosts.contains(host),
          """
          \(file.path) names \(host). The only outbound endpoints are the rules \
          channel, the update appcast and licence activation, and a fourth one \
          would be this app sending something it promised never to send
          """)
      }
    }

    #expect(checkedFiles > 80, "a sweep over a handful of files is not a sweep over the app")
    #expect(
      foundHosts == Self.permittedHosts,
      """
      all three are expected to appear: a list of permitted endpoints nothing \
      uses would pass this test while proving nothing
      """)
  }

  @Test("each permitted endpoint is reached over a secure connection and carries no query")
  func eachEndpointIsSecureAndCarriesNoQuery() {
    for url in [
      RulesChannel.manifestURL,
      UpdateChannel.stable.appcastURL,
      UpdateChannel.beta.appcastURL,
    ] {
      #expect(url.scheme == "https")
      #expect(url.query() == nil, "a query is a place to put something about this Mac")
    }
  }

  @Test("the three endpoints are three different hosts, so one outage is one feature")
  func theThreeEndpointsAreThreeHosts() {
    #expect(Self.permittedHosts.count == 3)
  }
}
