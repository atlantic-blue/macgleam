import Foundation
import GleamCore

/// The live view of what the machine is running, and the one way a process is
/// ended on a person's say so.
///
/// It reads nothing, signals nothing and keeps no time of its own. The three
/// boundaries it is built from are the whole of its access to the machine, and
/// the initialiser carries no defaults, so nothing reaches a real process by
/// forgetting an argument.
///
/// The sampling loop holds `ProcessListing`, which declares one method and it
/// reads. A sampler that could end a process therefore does not compile, which
/// is a stronger statement than a loop that happens never to call terminate.
public struct ProcessMonitor: ProcessMonitoring {
  private let listing: any ProcessListing
  private let terminating: any ProcessTerminating
  private let cadence: any ProcessSampleCadence

  /// No defaults, deliberately. Every boundary is supplied by the caller, so a
  /// test cannot reach the real machine by omission and production cannot
  /// reach a fake one.
  public init(
    listing: any ProcessListing,
    terminating: any ProcessTerminating,
    cadence: any ProcessSampleCadence
  ) {
    self.listing = listing
    self.terminating = terminating
    self.cadence = cadence
  }

  // MARK: - Sampling

  /// One snapshot per tick, ordered, off the main actor.
  ///
  /// Nothing is read until the first tick arrives, the work runs on a detached
  /// task so a view built on the main actor never samples on it, and the
  /// stream finishes when the cadence finishes. A consumer that goes away
  /// cancels the loop, so ticks after it read the machine no further times.
  public func samples() -> AsyncStream<[ProcessSample]> {
    let listing = self.listing
    let ticks = cadence.ticks()
    return AsyncStream { continuation in
      let sampling = Task.detached(priority: .userInitiated) {
        for await _ in ticks {
          if await Self.sampleOnce(from: listing, into: continuation) == .stop { break }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in sampling.cancel() }
    }
  }

  /// Whether the sampling loop has anywhere left to send a snapshot.
  private enum SamplingStep {
    case carryOn
    case stop
  }

  /// One tick's work. A read the machine refuses is skipped rather than
  /// repeated: the tick is spent on the attempt, nothing is emitted, and the
  /// next tick reads again. Emitting the previous list instead would show a
  /// stale list as though it were current.
  private static func sampleOnce(
    from listing: any ProcessListing,
    into continuation: AsyncStream<[ProcessSample]>.Continuation
  ) async -> SamplingStep {
    let snapshot: [ProcessSample]
    do {
      snapshot = try await listing.snapshot()
    } catch {
      return .carryOn
    }
    guard case .terminated = continuation.yield(ordered(snapshot)) else { return .carryOn }
    return .stop
  }

  /// Heaviest first by memory footprint, equal footprints by the lower process
  /// identifier. A function of the snapshot alone: the same processes reported
  /// in any order come out in one order, and nothing is dropped, invented or
  /// edited on the way.
  static func ordered(_ snapshot: [ProcessSample]) -> [ProcessSample] {
    snapshot.sorted { left, right in
      if left.memoryFootprintBytes != right.memoryFootprintBytes {
        return left.memoryFootprintBytes > right.memoryFootprintBytes
      }
      return left.processIdentifier < right.processIdentifier
    }
  }

  // MARK: - Quitting

  /// Checks the name against the machine, then signals, and refuses in every
  /// other case.
  ///
  /// The live name comes from the signalling boundary and from nowhere else.
  /// Reading it from the last snapshot would satisfy every ordinary example
  /// and fail the one this exists for: an identifier the operating system has
  /// handed on since the row was drawn.
  public func quit(_ confirmation: QuitConfirmation) async throws {
    let live = try await liveName(of: confirmation)
    guard !confirmation.name.isEmpty, confirmation.name == live else {
      throw ProcessQuitError.nameMismatch(expected: confirmation.name, actual: live)
    }
    try await signal(confirmation)
  }

  /// What holds the identifier right now, read immediately before the signal.
  ///
  /// Fails closed on both of the ways this can go wrong. Nothing holding the
  /// identifier is `processNotFound` whatever name was confirmed, and a
  /// machine that will not say is `notPermitted`: a check that could not be
  /// made is not a check that passed.
  private func liveName(of confirmation: QuitConfirmation) async throws -> String {
    let name: String?
    do {
      name = try await terminating.name(ofProcessIdentifier: confirmation.processIdentifier)
    } catch {
      throw ProcessQuitError.notPermitted(Self.unreadableNameSentence(confirmation.name))
    }
    guard let name else {
      throw ProcessQuitError.processNotFound(confirmation.processIdentifier)
    }
    return name
  }

  /// The one signal, of the kind that was confirmed. A quit confirmation
  /// produces the graceful signal and only that, however many times it is
  /// answered: nothing here escalates.
  private func signal(_ confirmation: QuitConfirmation) async throws {
    do {
      try await terminating.terminate(
        processIdentifier: confirmation.processIdentifier,
        force: confirmation.kind == .forceQuit
      )
    } catch {
      throw ProcessQuitError.notPermitted(Self.refusedSignalSentence(confirmation))
    }
  }

  // MARK: - Sentences

  static func unreadableNameSentence(_ name: String) -> String {
    "MacGleam could not check what is running as \(name), so nothing was signalled."
  }

  static func refusedSignalSentence(_ confirmation: QuitConfirmation) -> String {
    switch confirmation.kind {
    case .quit:
      return "The system refused to quit \(confirmation.name)."
    case .forceQuit:
      return "The system refused to force quit \(confirmation.name)."
    }
  }
}
