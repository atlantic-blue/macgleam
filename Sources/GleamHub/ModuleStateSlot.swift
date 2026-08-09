import Foundation

/// One module's preserved state, opaque to the hub. The module encodes its
/// own Codable state into `payload` on leaving and decodes it on re entry;
/// the hub stores and returns bytes and never interprets them.
public struct ModuleStateSlot: Codable, Sendable, Equatable {
  public let payload: Data

  public init(payload: Data) {
    self.payload = payload
  }
}
