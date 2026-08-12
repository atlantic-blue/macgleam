import CleanupModule
import Foundation
import GleamCore
import Observation
import os

/// The app's licence: the record in Application Support beside the settings,
/// the embedded public key, and the activation endpoint.
///
/// The public key is a development stage key, minted the same way the rules
/// baseline was. The production ceremony is a launch task, and until it
/// happens a licence signed by anybody else fails to verify, which is the
/// right way round: a build that cannot check a licence treats every licence
/// as absent rather than as valid.
@MainActor
enum LicenceComposition {
  /// One of exactly three outbound endpoints in the whole app, beside the
  /// update appcast and the rules channel.
  static let activationURL = URL(string: "https://licence.macgleam.app/v1/activate")!

  static func make() -> LicenceModel {
    LicenceModel(
      validator: LicenceValidator(
        store: LicenceRecordFile(directory: CleanupComposition.settingsDirectory()),
        activator: HTTPLicenceActivator(url: activationURL),
        publicKey: developmentPublicKey))
  }

  /// A development stage key. Replaced by the production one in the signing
  /// ceremony at launch, which is the same commit that replaces the rules key.
  static let developmentPublicKey = Data([
    0x9c, 0x1f, 0x1a, 0x6a, 0x2e, 0x63, 0x7f, 0x1c, 0x2b, 0x44, 0x5f, 0x11, 0x8d, 0x23, 0x71,
    0x0e, 0x5a, 0x36, 0x62, 0x19, 0x74, 0x48, 0x2f, 0x55, 0x6b, 0x0d, 0x3c, 0x27, 0x18, 0x59,
    0x40, 0x12,
  ])
}

/// What the Settings screen reads. It holds the state and nothing else: every
/// module works identically whatever it says, which is what the trial being
/// full featured means in practice.
@MainActor @Observable
final class LicenceModel {
  private(set) var state: LicenceState = .trial(startedAt: Date())
  private(set) var activationNotice: String?
  private(set) var isActivating = false

  @ObservationIgnored private let validator: any LicenceValidating

  init(validator: any LicenceValidating) {
    self.validator = validator
  }

  func refresh() async {
    state = await validator.currentState(now: Date())
  }

  /// Activation says what happened in a sentence and changes nothing when it
  /// fails, which is the whole of what somebody typing a key needs to know.
  func activate(licenceKey: String) async {
    let key = licenceKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return }
    isActivating = true
    activationNotice = nil
    do {
      state = try await validator.activate(licenceKey: key)
    } catch {
      activationNotice =
        (error as? any LocalizedError)?.errorDescription
        ?? "That did not work, and nothing was changed."
    }
    isActivating = false
  }
}

/// The record, in a file beside the settings so it survives a reinstall of the
/// application bundle. A file that cannot be read is no record at all, which
/// starts a fresh trial rather than locking somebody out.
struct LicenceRecordFile: LicenceRecordStoring {
  let directory: URL

  private var path: URL {
    directory.appending(path: "licence.json")
  }

  func load() async -> LicenceRecord? {
    guard let data = try? Data(contentsOf: path) else { return nil }
    return try? JSONDecoder().decode(LicenceRecord.self, from: data)
  }

  func save(_ record: LicenceRecord) async throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(record).write(to: path, options: .atomic)
  }
}

/// The activation endpoint. It sends a key and reads a licence back, and it
/// carries nothing else about this Mac: a request that identified the machine
/// would be a report of who is running MacGleam.
struct HTTPLicenceActivator: LicenceActivating {
  let url: URL

  func activate(licenceKey: String) async throws -> SignedLicence {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(["licenceKey": licenceKey])
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.rulesChannel.data(for: request)
    } catch {
      throw LicenceActivationError.serverUnreachable(
        description: "The licence server could not be reached.")
    }
    guard let http = response as? HTTPURLResponse else {
      throw LicenceActivationError.malformedResponse
    }
    guard http.statusCode == 200 else {
      throw LicenceActivationError.keyRejected(
        reason: "That licence key was not accepted, so nothing was changed.")
    }
    guard let licence = try? JSONDecoder().decode(SignedLicence.self, from: data) else {
      throw LicenceActivationError.malformedResponse
    }
    return licence
  }
}
