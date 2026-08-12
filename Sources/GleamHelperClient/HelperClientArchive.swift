import Foundation
import GleamCore
import GleamHelperCore

/// The app's side of the SafetyNet archive: the four requests the store sends
/// when a payload is one only root can move.
///
/// It is the store that calls this, never the executor, because the store
/// holds the manifest and an archive nothing recorded is exactly the defect
/// this family exists to close. Nothing here chooses a path: the stored path
/// and the item identifier both arrive from the store, which minted them
/// before it asked.
extension HelperClient: SafetyNetPrivilegedArchiving {

  public func archive(
    _ path: AbsolutePath,
    to storedPath: AbsolutePath,
    itemID: UUID
  ) async throws -> PrivilegedArchiveReport {
    try await report(
      from: .archiveIntoSafetyNet(target: path, storedPath: storedPath, itemID: itemID),
      itemID: itemID,
      about: path)
  }

  public func describeArchived(
    at storedPath: AbsolutePath,
    itemID: UUID
  ) async throws -> PrivilegedArchiveReport {
    try await report(
      from: .describeArchived(storedPath: storedPath, itemID: itemID),
      itemID: itemID,
      about: storedPath)
  }

  public func restoreArchived(
    at storedPath: AbsolutePath,
    itemID: UUID
  ) async throws -> AbsolutePath {
    let reply = try await answer(
      to: .restoreArchived(storedPath: storedPath, itemID: itemID),
      itemID: itemID,
      about: storedPath)
    guard case .restoredArchive(_, let originPath) = reply else {
      throw FileSystemError.ioFailure(storedPath, description: Self.wrongKindSentence)
    }
    return originPath
  }

  public func discardArchived(at storedPath: AbsolutePath, itemID: UUID) async throws {
    let reply = try await answer(
      to: .discardArchived(storedPath: storedPath, itemID: itemID),
      itemID: itemID,
      about: storedPath)
    guard case .discardedArchive = reply else {
      throw FileSystemError.ioFailure(storedPath, description: Self.wrongKindSentence)
    }
  }

  private func report(
    from request: HelperRequest,
    itemID: UUID,
    about path: AbsolutePath
  ) async throws -> PrivilegedArchiveReport {
    let reply = try await answer(to: request, itemID: itemID, about: path)
    guard case .archived(_, let report) = reply else {
      throw FileSystemError.ioFailure(path, description: Self.wrongKindSentence)
    }
    return report
  }

  /// One exchange, with everything checked before a word of the answer is
  /// believed: the helper is registered and approved, the connection has
  /// agreed a version, and the reply echoes this item and nothing else.
  private func answer(
    to request: HelperRequest,
    itemID: UUID,
    about path: AbsolutePath
  ) async throws -> HelperResponse {
    if let reason = await registrationRefusal(forArchiveOf: path) {
      throw FileSystemError.ioFailure(path, description: reason)
    }
    if let reason = await handshakeRefusal(forArchiveOf: path) {
      throw FileSystemError.ioFailure(path, description: reason)
    }
    switch await exchange(request) {
    case .notSent(let reason), .unanswered(let reason):
      throw FileSystemError.ioFailure(path, description: reason)
    case .reply(let reply):
      guard reply.correlationID == itemID else {
        throw FileSystemError.ioFailure(path, description: Self.anotherItemSentence)
      }
      if case .refused(_, let refusal) = reply {
        throw FileSystemError.ioFailure(
          path, description: HelperSentence.archiveRefused(refusal))
      }
      if case .failed(_, let reason) = reply {
        throw FileSystemError.ioFailure(path, description: reason)
      }
      return reply
    }
  }

  private static let wrongKindSentence =
    "The privileged helper's answer was not the kind of answer this request has, so nothing "
    + "was recorded."
  private static let anotherItemSentence =
    "The privileged helper answered about a different SafetyNet item, so nothing was recorded."
}
