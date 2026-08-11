import Darwin
import Foundation
import GleamCore

/// The signalling side, against this machine.
///
/// It answers who holds an identifier right now and it sends one signal. Both
/// live here because the check is only worth something when it is made on the
/// same boundary as the signal and immediately before it.
///
/// The name it answers comes from the same reader the live view's rows are
/// drawn with, so the comparison the monitor makes is between two spellings of
/// the same origin. A different reader on each side would refuse every quit on
/// this machine while passing every test on a fake one.
public struct SystemProcessTerminating: ProcessTerminating {
  public init() {}

  /// What holds the identifier now, or nothing at all.
  ///
  /// `nil` means no process holds it. A throw means the machine would not say,
  /// and the monitor turns that into a refusal rather than into permission.
  public func name(ofProcessIdentifier processIdentifier: Int32) async throws -> String? {
    try LiveProcessName.of(processIdentifier)
  }

  /// One signal, of the kind that was confirmed: ask the process to end, or
  /// end it. Nothing here escalates and nothing here retries.
  public func terminate(processIdentifier: Int32, force: Bool) async throws {
    guard processIdentifier > 0 else {
      throw ProcessMachineFailure.signalRefused(processIdentifier)
    }
    let sent = kill(processIdentifier, force ? SIGKILL : SIGTERM)
    guard sent == 0 else {
      throw ProcessMachineFailure.signalRefused(processIdentifier)
    }
  }
}
