import Foundation

/// The rules channel: where a signed catalogue update comes from.
///
/// One host, one path, no query, no headers carrying anything about this Mac.
/// The request says nothing except which file it wants, because a rules fetch
/// that carried an identifier would be a report of who is running MacGleam,
/// and this app promises that no path, file name or scan content ever leaves
/// the machine.
///
/// What comes back is bytes and nothing more. Every decision about them is
/// made by `RuleCatalogStore`, which verifies the signature against the pinned
/// key and refuses anything that is not strictly newer. So a channel that is
/// compromised, redirected or replayed hands over bytes that are then refused:
/// the trust is in the signature, never in the transport.
public struct RulesChannel: Sendable {
  /// One of exactly three outbound endpoints in the whole app, beside the
  /// update appcast and licence activation.
  public static let manifestURL = URL(
    string: "https://rules.macgleam.app/v1/catalog.json")!

  private let url: URL
  private let session: URLSession

  public init(url: URL = RulesChannel.manifestURL, session: URLSession = .rulesChannel) {
    self.url = url
    self.session = session
  }

  /// The manifest bytes, or a typed channel failure. Everything that can go
  /// wrong out here is the same fact to the store: no update arrived, so the
  /// catalogue in force stays in force.
  public func fetchManifest() async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.cachePolicy = .reloadIgnoringLocalCacheData
    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        throw RuleCatalogError.channelUnreachable(
          description: "The rules channel answered with something that is not a web response.")
      }
      guard http.statusCode == 200 else {
        throw RuleCatalogError.channelUnreachable(
          description: "The rules channel answered \(http.statusCode).")
      }
      return data
    } catch let error as RuleCatalogError {
      throw error
    } catch {
      throw RuleCatalogError.channelUnreachable(
        description: "The rules channel could not be reached.")
    }
  }
}

extension URLSession {
  /// The session the rules fetch uses: no cookies, no credential storage, no
  /// shared cache. A rules fetch carries nothing about this Mac and leaves
  /// nothing behind on it.
  public static var rulesChannel: URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.httpShouldSetCookies = false
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 60
    return URLSession(configuration: configuration)
  }
}
