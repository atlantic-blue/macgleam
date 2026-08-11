/// What the pane beside the rail shows for the selected destination: the
/// heading, one sentence of what it is for, the jobs it runs, and the one
/// action that runs them.
///
/// A module that is not built yet still gets a pane. It says what it will do
/// and admits it cannot do it, rather than showing an empty screen or an
/// action that does nothing.
public struct ModulePane: Sendable, Equatable {
  public let title: String
  public let sentence: String
  public let jobs: [ModulePaneJob]
  public let action: ModulePaneAction?
  public let notReadyNote: String?

  public init(
    title: String,
    sentence: String,
    jobs: [ModulePaneJob],
    action: ModulePaneAction?,
    notReadyNote: String?
  ) {
    self.title = title
    self.sentence = sentence
    self.jobs = jobs
    self.action = action
    self.notReadyNote = notReadyNote
  }
}

/// One line of the pane's job list. `detail` carries the live figure once
/// there is one, and is empty before any scan has run.
public struct ModulePaneJob: Sendable, Equatable, Identifiable {
  public var id: String { name }
  public let name: String
  public let symbolName: String
  public let detail: String

  public init(name: String, symbolName: String, detail: String = "") {
    self.name = name
    self.symbolName = symbolName
    self.detail = detail
  }
}

/// The pane's single primary action, named for what it does.
public struct ModulePaneAction: Sendable, Equatable {
  public let title: String

  public init(title: String) {
    self.title = title
  }
}
