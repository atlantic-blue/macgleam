import AppKit
import GleamHub
import os

/// The live Full Disk Access monitor. Probes the grant by attempting to
/// read a directory macOS gates behind Full Disk Access, which never
/// triggers a permission prompt: the only way to grant is the System
/// Settings toggle.
///
/// `updates` is event driven, not scheduled: it re probes when the app
/// becomes active, which is exactly the moment the user returns from
/// flipping the toggle in System Settings, and emits only when the grant
/// changed.
final class RealFullDiskAccessMonitor: FullDiskAccessMonitoring {
  /// Directories the system gates behind Full Disk Access. Readable means
  /// granted. A directory that is missing or unreadable for any reason
  /// counts as ungranted, which errs on the honest side.
  private static let protectedDirectories = [
    "Library/Mail",
    "Library/Safari",
  ]

  var isGranted: Bool {
    get async { Self.probeGrant() }
  }

  func updates() -> AsyncStream<Bool> {
    AsyncStream { continuation in
      let lastKnownGrant = OSAllocatedUnfairLock(initialState: Self.probeGrant())
      nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
        forName: NSApplication.didBecomeActiveNotification,
        object: nil,
        queue: nil
      ) { _ in
        let currentGrant = Self.probeGrant()
        let hasChanged = lastKnownGrant.withLock { state in
          guard state != currentGrant else { return false }
          state = currentGrant
          return true
        }
        if hasChanged {
          continuation.yield(currentGrant)
        }
      }
      continuation.onTermination = { _ in
        NotificationCenter.default.removeObserver(observer)
      }
    }
  }

  @MainActor func openPrivacySettings() {
    let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    guard let url = URL(string: pane) else { return }
    NSWorkspace.shared.open(url)
  }

  private static func probeGrant() -> Bool {
    let home = FileManager.default.homeDirectoryForCurrentUser
    for directory in protectedDirectories {
      let path = home.appending(path: directory).path
      if (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil {
        return true
      }
    }
    return false
  }
}
