/// One module as the rail and its pane present it.
///
/// `figure` is the module's live figure line. Empty is allowed while the
/// module is a placeholder; it is never filler text. `isEnabled` false means
/// the module is reachable and says so in its pane, but offers no action.
public struct HubModuleSummary: Sendable, Equatable, Identifiable {
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
