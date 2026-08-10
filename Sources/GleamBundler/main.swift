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
    guard FileManager.default.fileExists(atPath: binary.path) else {
      throw BundlerError.missingBinary(binary.path, configuration: configuration)
    }

    try replaceBundle()
    try installBinary(from: binary)
    try writeInformationPropertyList()
    try sign()

    print("Bundled \(bundleURL.path)")
    print("Open it with: open \(bundleURL.path)")
  }

  private func replaceBundle() throws {
    let manager = FileManager.default
    if manager.fileExists(atPath: bundleURL.path) {
      try manager.removeItem(at: bundleURL)
    }
    try manager.createDirectory(
      at: bundleURL.appending(path: "Contents/MacOS"),
      withIntermediateDirectories: true
    )
    try manager.createDirectory(
      at: bundleURL.appending(path: "Contents/Resources"),
      withIntermediateDirectories: true
    )
  }

  private func installBinary(from binary: URL) throws {
    try FileManager.default.copyItem(
      at: binary,
      to: bundleURL.appending(path: "Contents/MacOS/\(Self.executableName)")
    )
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

  private func sign() throws {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/codesign")
    process.arguments = ["--force", "--sign", "-", "--timestamp=none", bundleURL.path]
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
        Build it first: swift build -c \(configuration) --product MacGleam
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
