import Foundation

/// The bytes that cross the process boundary, and the only place either
/// process turns a message into them.
///
/// The encoding is JSON with one top level key naming the message, and it is
/// canonical: keys are sorted, so equal messages always produce identical
/// bytes and decoding then re encoding reproduces the bytes exactly. A plain
/// encoder leaves key order to a hash seed, which makes a byte comparison of
/// two encodings of the same message pass or fail by luck.
///
/// Decoding is strict. A message missing a value it declares fails rather
/// than taking a default, and a number outside the range its field declares
/// fails rather than wrapping: the version handshake is only worth having if
/// a malformed version is rejected instead of quietly becoming a plausible
/// one.
public struct HelperWireCodec: Sendable {
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init() {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    self.encoder = encoder
    self.decoder = JSONDecoder()
  }

  public func encode(_ request: HelperRequest) throws -> Data {
    try encoder.encode(request)
  }

  public func encode(_ response: HelperResponse) throws -> Data {
    try encoder.encode(response)
  }

  public func decodeRequest(from data: Data) throws -> HelperRequest {
    try decoder.decode(HelperRequest.self, from: data)
  }

  public func decodeResponse(from data: Data) throws -> HelperResponse {
    try decoder.decode(HelperResponse.self, from: data)
  }
}
