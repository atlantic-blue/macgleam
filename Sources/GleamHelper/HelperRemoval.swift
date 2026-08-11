import Foundation
import GleamCore
import GleamHelperCore

/// The root side of a removal. The destination arrives with the request and is
/// never chosen here, so the helper cannot decide to delete something the app
/// asked to keep.
struct HelperRemoval: Sendable {
  let fileSystem: DiskFileSystem

  func remove(
    _ target: AbsolutePath,
    to destination: HelperRemovalDestination
  ) async throws -> UInt64 {
    let bytes = try await measureBytes(at: target)
    switch destination {
    case .permanent:
      try await fileSystem.delete(target)
    case .userTrash(let userHome):
      try await moveIntoDirectory(target, directory: trashDirectory(of: userHome), giveTo: userHome)
    case .safetyNetStore(let storeDirectory):
      try await moveIntoDirectory(target, directory: storeDirectory, giveTo: nil)
    }
    return bytes
  }

  private func trashDirectory(of userHome: AbsolutePath) -> AbsolutePath {
    AbsolutePath(normalising: "\(userHome.value)/.Trash")
  }

  /// Moves the item under a directory, and hands a trashed item to the account
  /// that owns the home it landed in. A root owned file dropped into someone's
  /// Trash that they cannot then restore is a worse outcome than leaving it
  /// where it was, so ownership transfers with it.
  private func moveIntoDirectory(
    _ target: AbsolutePath,
    directory: AbsolutePath,
    giveTo userHome: AbsolutePath?
  ) async throws {
    try await fileSystem.createDirectory(at: directory)
    let destination = try await freeName(in: directory, for: target)
    try await fileSystem.move(target, to: destination)
    guard let userHome else { return }
    try HelperOwnership.give(destination, toOwnerOf: userHome)
  }

  /// The first unused name in the directory, starting from the item's own and
  /// then numbering, which is what the Finder does when two files of the same
  /// name meet in the Trash.
  private func freeName(
    in directory: AbsolutePath,
    for target: AbsolutePath
  ) async throws -> AbsolutePath {
    let name = target.lastComponent
    let stem = (name as NSString).deletingPathExtension
    let suffix = (name as NSString).pathExtension
    for attempt in 1...Self.namingAttempts {
      let candidate =
        attempt == 1 ? name : Self.name(stem: stem, extension: suffix, number: attempt)
      let path = AbsolutePath(normalising: "\(directory.value)/\(candidate)")
      if await !fileSystem.exists(path) { return path }
    }
    throw FileSystemError.destinationOccupied(directory)
  }

  private static let namingAttempts = 999

  private static func name(stem: String, extension suffix: String, number: Int) -> String {
    suffix.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(suffix)"
  }

  /// Allocated bytes, summed over a directory's contents, measured before the
  /// move so the figure describes what actually left.
  private func measureBytes(at path: AbsolutePath) async throws -> UInt64 {
    let record = try await fileSystem.metadata(at: path)
    guard record.isDirectory else { return record.allocatedBytes }
    var total = record.allocatedBytes
    let options = EnumerationOptions(includesHiddenFiles: true, descendsIntoPackages: true)
    for try await event in fileSystem.enumerate(root: path, options: options) {
      if case .record(let child) = event { total += child.allocatedBytes }
    }
    return total
  }
}

/// Hands a file to the account that owns a home directory, all the way down.
enum HelperOwnership {
  static func give(_ path: AbsolutePath, toOwnerOf userHome: AbsolutePath) throws {
    var home = stat()
    guard stat(userHome.value, &home) == 0 else {
      throw FileSystemError.ioFailure(
        userHome, description: "The home directory could not be read.")
    }
    try change(path, uid: home.st_uid, gid: home.st_gid)
    let manager = FileManager.default
    guard let walk = manager.enumerator(atPath: path.value) else { return }
    for case let relative as String in walk {
      let child = AbsolutePath(normalising: "\(path.value)/\(relative)")
      try change(child, uid: home.st_uid, gid: home.st_gid)
    }
  }

  /// `lchown` rather than `chown`, so a symbolic link is retargeted rather
  /// than whatever it points at.
  private static func change(_ path: AbsolutePath, uid: uid_t, gid: gid_t) throws {
    guard lchown(path.value, uid, gid) != 0 else { return }
    throw FileSystemError.ioFailure(
      path, description: "Ownership could not be transferred: \(String(cString: strerror(errno)))")
  }
}
