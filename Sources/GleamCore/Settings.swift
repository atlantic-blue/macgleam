import Foundation

public struct MenuBarPreferences: Codable, Sendable, Equatable {
  public var showsStorage: Bool
  public var showsMemory: Bool
  public var showsProcessorLoad: Bool

  public init(showsStorage: Bool, showsMemory: Bool, showsProcessorLoad: Bool) {
    self.showsStorage = showsStorage
    self.showsMemory = showsMemory
    self.showsProcessorLoad = showsProcessorLoad
  }
}

/// Motion follows the system Reduce Motion setting. `reduceMotionOverride`
/// lets a user force reduced motion on while the system setting is off;
/// nothing can force full motion on when the system asks for reduced.
public struct MotionPreferences: Codable, Sendable, Equatable {
  public var reduceMotionOverride: Bool?

  public init(reduceMotionOverride: Bool?) {
    self.reduceMotionOverride = reduceMotionOverride
  }
}

/// User preferences. One store, loaded once, validated on load.
public struct Settings: Codable, Sendable, Equatable {
  public enum DeletionMode: String, Codable, Sendable, Equatable {
    case trash, permanent
  }

  public var deletionMode: DeletionMode
  public var largeFileThresholdBytes: UInt64
  public var oldFileThresholdDays: UInt32
  public var menuBar: MenuBarPreferences
  public var motion: MotionPreferences

  /// Deletion mode defaults to trash. Switching to permanent is an explicit
  /// opt in.
  public static let defaults = Settings(
    deletionMode: .trash,
    largeFileThresholdBytes: 1_073_741_824,
    oldFileThresholdDays: 180,
    menuBar: MenuBarPreferences(showsStorage: true, showsMemory: true, showsProcessorLoad: true),
    motion: MotionPreferences(reduceMotionOverride: nil)
  )

  public init(
    deletionMode: DeletionMode,
    largeFileThresholdBytes: UInt64,
    oldFileThresholdDays: UInt32,
    menuBar: MenuBarPreferences,
    motion: MotionPreferences
  ) {
    self.deletionMode = deletionMode
    self.largeFileThresholdBytes = largeFileThresholdBytes
    self.oldFileThresholdDays = oldFileThresholdDays
    self.menuBar = menuBar
    self.motion = motion
  }
}
