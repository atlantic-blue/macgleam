import Foundation
import GleamCore

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
    try installFrameworks()
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
    for directory in [
      "Contents/MacOS", "Contents/Resources", "Contents/Frameworks",
      "Contents/Library/LaunchDaemons",
    ] {
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

  /// Every framework the build produced, and the search path that finds them.
  ///
  /// A dynamically linked framework left in the build directory is a bundle
  /// that builds, links, signs and then refuses to start: the loader looks
  /// beside the executable, finds nothing, and macOS reports that the
  /// application quit unexpectedly. So the frameworks travel inside the
  /// bundle, in the one place a signature can seal them and a notarised app is
  /// allowed to keep them.
  private func installFrameworks() throws {
    let manager = FileManager.default
    // The build directory is a symbolic link to the architecture's own
    // directory, and listing a link is not listing a directory.
    let built = try manager.contentsOfDirectory(
      at: buildDirectory.resolvingSymlinksInPath(), includingPropertiesForKeys: nil)
    let frameworks = built.filter { $0.pathExtension == "framework" }
    for framework in frameworks {
      try manager.copyItem(
        at: framework,
        to: bundleURL.appending(path: "Contents/Frameworks/\(framework.lastPathComponent)"))
    }
    guard !frameworks.isEmpty else { return }
    // The linker leaves @loader_path on the executable, which resolves to
    // Contents/MacOS once it is inside the bundle. This is the path that makes
    // Contents/Frameworks reachable from there.
    try addRunPath(
      "@executable_path/../Frameworks",
      to: bundleURL.appending(path: "Contents/MacOS/\(Self.executableName)"))
  }

  private func addRunPath(_ path: String, to binary: URL) throws {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/install_name_tool")
    process.arguments = ["-add_rpath", path, binary.path]
    // install_name_tool writes to standard error when the path is already
    // there, which is not a failure worth stopping a build for.
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
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

  /// The public half of the appcast signing key. The private half exists only
  /// in the release pipeline's secrets, so an update signed anywhere else is
  /// refused by every installation. This is a development stage placeholder
  /// until the launch ceremony mints the real pair, and a placeholder here
  /// fails closed: nothing verifies against it, so nothing installs.
  static let appcastPublicKey = "REPLACE_AT_LAUNCH_WITH_THE_APPCAST_PUBLIC_KEY"

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
      // The update feed and the key its entries are signed with. Both live in
      // the bundle rather than in code, because a build's own identity is
      // what an updater reads before it trusts anything it downloads, and a
      // feed nobody can see in the bundle is a feed nobody can audit.
      "SUFeedURL": UpdateChannel.stable.appcastURL.absoluteString,
      "SUPublicEDKey": Self.appcastPublicKey,
      // Updates are offered, never installed unasked. The two together are
      // what makes an app that can replace itself one that never does it
      // while nobody is looking.
      "SUEnableAutomaticChecks": true,
      "SUAutomaticallyUpdate": false,
      "SUScheduledCheckInterval": Int(UpdatePolicy.dailyInterval),
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
    let frameworks = bundleURL.appending(path: "Contents/Frameworks")
    let contents =
      (try? FileManager.default.contentsOfDirectory(
        at: frameworks, includingPropertiesForKeys: nil)) ?? []
    for framework in contents where framework.pathExtension == "framework" {
      try codesign(framework)
    }
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
