/// The keys the hub navigation understands. A closed set: full operation
/// without a pointer means these six are sufficient to reach every module
/// and come back.
public enum HubKeyEvent: String, CaseIterable, Sendable, Equatable {
  case arrowLeft
  case arrowRight
  case arrowUp
  case arrowDown
  case `return`
  case escape
}
