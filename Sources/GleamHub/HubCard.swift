/// One module card on the hub.
///
/// `figure` is the card's live figure line. Empty is allowed while the module
/// is a placeholder; it is never filler text. `isEnabled` false means the card
/// renders but does not enter its module.
public struct HubCard: Sendable, Equatable, Identifiable {
  public var id: HubModule { module }
  public let module: HubModule
  public let figure: String
  public let isEnabled: Bool

  public init(module: HubModule, figure: String, isEnabled: Bool) {
    self.module = module
    self.figure = figure
    self.isEnabled = isEnabled
  }
}
