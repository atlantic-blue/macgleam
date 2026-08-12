import Foundation
import GleamCore
import os

/// The app's rule catalogue: the embedded baseline, plus whatever the channel
/// has published since, verified here before a word of it is believed.
///
/// One store for the whole app run. Every module reads its rules from this, so
/// a catalogue adopted mid session is adopted everywhere at once rather than
/// in whichever module scanned next.
///
/// A refresh is best effort by design. No network, a redirected host, a
/// tampered manifest and a replayed old version are all the same fact from
/// here: no update arrived, so the catalogue in force stays in force and the
/// app keeps working exactly as it did.
final class RuleSupply: Sendable {
  private let store: RuleCatalogStore?
  /// The catalogue every consumer reads, kept behind a lock rather than
  /// behind the store's actor so a component that cannot await still reads
  /// the current one. It is replaced whole when an update is adopted, so
  /// nothing ever sees half a catalogue.
  private let adopted: OSAllocatedUnfairLock<RuleCatalog>
  private let log = Logger(subsystem: "com.atlanticblue.macgleam", category: "rules")

  init(channel: RulesChannel = RulesChannel()) {
    let baseline = Self.loadBaseline()
    self.adopted = OSAllocatedUnfairLock(initialState: baseline)
    self.store = Self.makeStore(baseline: baseline, channel: channel)
  }

  /// The catalogue in force, with the denylist every consumer must see: the
  /// union of the baseline's and the adopted catalogue's, so an update can
  /// extend the protected set and can never shrink it.
  var rules: RuleCatalog {
    adopted.withLock { $0 }
  }

  /// Asks the channel for anything newer. Nothing here throws at the caller:
  /// the outcome is logged and the app carries on, because a rules update
  /// failing is not a reason for a scan not to run.
  @discardableResult
  func refresh() async -> RuleCatalogUpdate {
    guard let store else { return .alreadyCurrent }
    do {
      let outcome = try await store.refreshFromChannel()
      if case .updated(let from, let to) = outcome {
        log.info("Adopted rule catalogue \(to.value) in place of \(from.value).")
        await publish(store)
      }
      return outcome
    } catch {
      log.notice("No rule catalogue update was adopted: \(String(describing: error)).")
      return .alreadyCurrent
    }
  }

  /// Replaces the catalogue in force with the adopted one and its effective
  /// denylist, in one write, so a reader sees the old one or the new one.
  private func publish(_ store: RuleCatalogStore) async {
    let current = await store.current
    let denylist = await store.effectiveDenylist
    adopted.withLock { rules in
      rules = RuleCatalog(
        version: current.version,
        signature: current.signature,
        cleanupRules: current.cleanupRules,
        adwareRules: current.adwareRules,
        denylist: denylist)
    }
  }

  /// A baseline that fails to load leaves an empty catalogue: scans find
  /// nothing rather than crash, and the failure is logged for diagnosis.
  private static func loadBaseline() -> RuleCatalog {
    do {
      return try RuleCatalogBaseline.load()
    } catch {
      Logger(subsystem: "com.atlanticblue.macgleam", category: "rules")
        .error("The baseline rule catalogue failed to load: \(error).")
      return RuleCatalog(
        version: RuleCatalogVersion(value: 0),
        signature: Data(),
        cleanupRules: [],
        adwareRules: [],
        denylist: Denylist(patterns: []))
    }
  }

  /// A store that will not verify its own baseline is no store at all, and
  /// the app runs on the baseline it holds rather than pretending to have a
  /// channel. That is the same shape as every other absence here: do the work
  /// that can be done, and never half of a job.
  private static func makeStore(
    baseline: RuleCatalog,
    channel: RulesChannel
  ) -> RuleCatalogStore? {
    do {
      let verifier = try RuleCatalogVerifier(publicKey: RuleCatalogBaseline.publicKey)
      return try RuleCatalogStore(
        baseline: baseline,
        verifier: verifier,
        channelFetch: { try await channel.fetchManifest() })
    } catch {
      Logger(subsystem: "com.atlanticblue.macgleam", category: "rules")
        .error("The rule catalogue store could not be built: \(error).")
      return nil
    }
  }
}
