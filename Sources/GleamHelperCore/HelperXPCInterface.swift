import Foundation

/// The names launchd, the app and the daemon must all agree on, declared once
/// in the package both processes link so a rename cannot land on one side.
///
/// The label is also the Mach service name and also the property list's file
/// name. `SMAppService.daemon(plistName:)` finds the daemon by that file name,
/// and launchd refuses a property list whose `Label` and file name disagree,
/// so one constant with `.plist` appended is the only shape that cannot drift.
public enum GleamHelperService {
  public static let label = "com.atlanticblue.macgleam.helper"
  public static let machServiceName = label
  public static let propertyListName = "\(label).plist"
  /// Where the daemon binary sits inside MacGleam.app, and the value of the
  /// property list's `BundleProgram`.
  public static let bundleProgram = "Contents/MacOS/GleamHelper"
}

/// The XPC (inter process communication) interface, in bytes both ways.
///
/// Bytes rather than a typed remote interface on purpose. A typed interface
/// would hand each side a decoded, well formed message it never checked, and
/// both sides here treat the other as untrusted: the helper decodes and admits
/// through C31 before acting, and the client decodes and validates against C30
/// before believing. `NSSecureCoding` on a Data payload is the whole of what
/// crosses.
@objc public protocol GleamHelperXPC {
  func handle(_ payload: Data, withReply reply: @escaping @Sendable (Data) -> Void)
}
