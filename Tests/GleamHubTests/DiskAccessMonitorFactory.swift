import Foundation
import GleamHub

/// A monitor under full test control. The grant flag and the update stream
/// are scripted from the test, and every deep link request is counted, so
/// the flow model's behaviour is pinned without System Settings or a real
/// file system probe. The stream buffers, so tests script every emission,
/// finish the stream, then await consumption: fully deterministic.
final class FakeFullDiskAccessMonitor: FullDiskAccessMonitoring, @unchecked Sendable {
  private let lock = NSLock()
  private var grantFlag: Bool
  private let stream: AsyncStream<Bool>
  private let continuation: AsyncStream<Bool>.Continuation

  @MainActor private(set) var privacySettingsOpenCount = 0

  init(isGranted: Bool) {
    grantFlag = isGranted
    (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
  }

  private func readGrantFlag() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return grantFlag
  }

  var isGranted: Bool {
    get async {
      readGrantFlag()
    }
  }

  func updates() -> AsyncStream<Bool> {
    stream
  }

  @MainActor func openPrivacySettings() {
    privacySettingsOpenCount += 1
  }

  /// Scripts a grant change: the flag moves with the emission, because C32
  /// guarantees `isGranted` reflects the real current grant.
  func emitGrantChange(_ granted: Bool) {
    lock.lock()
    grantFlag = granted
    lock.unlock()
    continuation.yield(granted)
  }

  func finishUpdates() {
    continuation.finish()
  }
}

func degradedBanner(of step: DiskAccessOnboardingStep) -> String? {
  if case .degraded(let unavailable) = step {
    return unavailable
  }
  return nil
}
