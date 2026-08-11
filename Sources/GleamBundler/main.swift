import Foundation

/// Assembles MacGleam.app.
///
/// macOS identifies an application for Transparency, Consent and Control by
/// its bundle identifier and code signature. A bare executable run from the
/// build directory has neither, so it can never appear in the Full Disk
/// Access list and any access it attempts is attributed to whichever terminal
/// launched it. Only a signed bundle can hold a permission.
///
/// The signature here is ad hoc, which is enough for the system to recognise
/// the app and list it. It is not enough to distribute: the identifier stays
/// stable across builds but the code directory hash does not, so a rebuild
/// can require granting access again. Developer ID signing and notarization
/// are launch milestone work.
struct Bundler {
  static let bundleIdentifier = "com.atlanticblue.macgleam"
  static let executableName = "MacGleam"
  static let minimumSystemVersion = "14.0"

  /// The privileged daemon travels inside the app. `SMAppService` registers a
  /// daemon by the file name of a property list in the app's own
  /// `Contents/Library/LaunchDaemons`, and launchd refuses a property list
  /// whose `Label` and file name disagree, so both are this one string.
  static let helperExecutableName = "GleamHelper"
  static let helperLabel = "com.atlanticblue.macgleam.helper"

  let configuration: String
  let packageRoot: URL

  var buildDirectory: URL {
    packageRoot.appending(path: ".build/\(configuration)")
  }

  var bundleURL: URL {
    packageRoot.appending(path: "dist/\(Self.executableName).app")
  }

  func run() throws {
    let binary = buildDirectory.appending(path: Self.executableName)
    let helperBinary = buildDirectory.appending(path: Self.helperExecutableName)
    for built in [binary, helperBinary] {
      guard FileManager.default.fileExists(atPath: built.path) else {
        throw BundlerError.missingBinary(built.path, configuration: configuration)
      }
    }

    try replaceBundle()
    try installBinary(from: binary, named: Self.executableName)
    try installBinary(from: helperBinary, named: Self.helperExecutableName)
    try writeInformationPropertyList()
    try writeLaunchDaemonPropertyList()
    try sign()

    print("Bundled \(bundleURL.path)")
    print("Open it with: open \(bundleURL.path)")
  }

  private func replaceBundle() throws {
    let manager = FileManager.default
    if manager.fileExists(atPath: bundleURL.path) {
      try manager.removeItem(at: bundleURL)
    }
    for directory in ["Contents/MacOS", "Contents/Resources", "Contents/Library/LaunchDaemons"] {
      try manager.createDirectory(
        at: bundleURL.appending(path: directory),
        withIntermediateDirectories: true
      )
    }
  }

  private func installBinary(from binary: URL, named name: String) throws {
    try FileManager.default.copyItem(
      at: binary,
      to: bundleURL.appending(path: "Contents/MacOS/\(name)")
    )
  }

  /// The daemon's launchd job. `BundleProgram` is relative to the app bundle,
  /// so the daemon that runs is always the one inside the app that registered
  /// it, and `AssociatedBundleIdentifiers` is what puts a line reading MacGleam
  /// rather than a bare label in Login Items and Extensions.
  private func writeLaunchDaemonPropertyList() throws {
    let job: [String: Any] = [
      "Label": Self.helperLabel,
      "BundleProgram": "Contents/MacOS/\(Self.helperExecutableName)",
      "MachServices": [Self.helperLabel: true],
      "AssociatedBundleIdentifiers": [Self.bundleIdentifier],
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: job,
      format: .xml,
      options: 0
    )
    try data.write(
      to: bundleURL.appending(path: "Contents/Library/LaunchDaemons/\(Self.helperLabel).plist"))
  }

  private func writeInformationPropertyList() throws {
    let keys: [String: Any] = [
      "CFBundleExecutable": Self.executableName,
      "CFBundleIdentifier": Self.bundleIdentifier,
      "CFBundleName": Self.executableName,
      "CFBundleDisplayName": Self.executableName,
      "CFBundlePackageType": "APPL",
      "CFBundleInfoDictionaryVersion": "6.0",
      "CFBundleShortVersionString": "0.1.0",
      "CFBundleVersion": "1",
      "LSMinimumSystemVersion": Self.minimumSystemVersion,
      "NSHighResolutionCapable": true,
      "LSApplicationCategoryType": "public.app-category.utilities",
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: keys,
      format: .xml,
      options: 0
    )
    try data.write(to: bundleURL.appending(path: "Contents/Info.plist"))
  }

  /// Inside out, which is the only order that works: signing the app seals the
  /// hashes of everything inside it, so a nested executable signed afterwards
  /// invalidates the enclosing signature it is sealed into.
  private func sign() throws {
    try codesign(bundleURL.appending(path: "Contents/MacOS/\(Self.helperExecutableName)"))
    try codesign(bundleURL)
  }

  private func codesign(_ target: URL) throws {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/codesign")
    process.arguments = ["--force", "--sign", "-", "--timestamp=none", target.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw BundlerError.signingFailed(status: process.terminationStatus)
    }
  }
}

enum BundlerError: Error, CustomStringConvertible {
  case missingBinary(String, configuration: String)
  case signingFailed(status: Int32)

  var description: String {
    switch self {
    case .missingBinary(let path, let configuration):
      return """
        No built executable at \(path).
        Build both first: swift build -c \(configuration) --product MacGleam
        and swift build -c \(configuration) --product GleamHelper
        """
    case .signingFailed(let status):
      return "codesign exited with status \(status)."
    }
  }
}

let configuration = CommandLine.arguments.contains("--release") ? "release" : "debug"
let packageRoot = URL(filePath: FileManager.default.currentDirectoryPath)

do {
  try Bundler(configuration: configuration, packageRoot: packageRoot).run()
} catch {
  FileHandle.standardError.write(Data("\(error)\n".utf8))
  exit(1)
}
