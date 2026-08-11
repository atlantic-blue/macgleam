import Foundation

/// One connection to the privileged helper, in bytes.
///
/// Bytes rather than typed messages on purpose. What comes back is whatever
/// the other side of a process boundary chose to send, and a typed reply would
/// hand the client a decoded, well formed message it never checked. The client
/// decodes and validates every reply itself, so a helper that is confused,
/// stale or malicious costs one operation instead of being believed.
public protocol HelperTransporting: Sendable {
  func send(_ payload: Data) async throws -> Data
}
