import Foundation

/// Walks a directory tree over a `RawDirectoryReading` source and applies the
/// enumeration policy shared by every file system implementation: the root is
/// not yielded, skipped subtrees are excluded including their roots, hidden
/// means a dot prefixed name, packages are yielded but only entered on
/// request, duplicate (volumeID, fileID) pairs are yielded once, unreadable
/// directories become `inaccessible` events, and cancellation ends the stream
/// promptly. Directory reads run with bounded concurrency.
public struct FileSystemEnumerator: Sendable {
  private static let maxConcurrentDirectoryReads = 6

  private static let packageExtensions: Set<String> = [
    "app", "appex", "bundle", "framework", "plugin", "kext", "xpc",
    "prefpane", "qlgenerator", "docset", "playground", "xcodeproj",
    "xcworkspace", "photoslibrary", "musiclibrary", "tvlibrary", "scptd",
    "wdgt", "lproj",
  ]

  private let source: any RawDirectoryReading

  public init(source: any RawDirectoryReading) {
    self.source = source
  }

  public func enumerate(
    root: AbsolutePath,
    options: EnumerationOptions
  ) -> AsyncThrowingStream<EnumerationEvent, Error> {
    let source = self.source
    return AsyncThrowingStream { continuation in
      let walk = Task {
        do {
          try await Self.walk(root: root, options: options, source: source) { event in
            continuation.yield(event)
          }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in walk.cancel() }
    }
  }

  private struct DirectoryListing: Sendable {
    let directory: AbsolutePath
    let children: [FileRecord]
    let failure: (any Error)?
  }

  private struct FileIdentity: Hashable {
    let volumeID: UInt64
    let fileID: UInt64
  }

  private static func walk(
    root: AbsolutePath,
    options: EnumerationOptions,
    source: any RawDirectoryReading,
    yield: (EnumerationEvent) -> Void
  ) async throws {
    var seen = Set<FileIdentity>()
    var pending = [root]
    try await withThrowingTaskGroup(of: DirectoryListing.self) { group in
      var inFlight = 0
      while !pending.isEmpty || inFlight > 0 {
        try Task.checkCancellation()
        while inFlight < maxConcurrentDirectoryReads, let directory = pending.popLast() {
          group.addTask { await listing(of: directory, from: source) }
          inFlight += 1
        }
        guard let listing = try await group.next() else { break }
        inFlight -= 1
        if let failure = listing.failure {
          try handle(failure, in: listing.directory, yield: yield)
          continue
        }
        for record in listing.children {
          process(record, options: options, seen: &seen, pending: &pending, yield: yield)
        }
      }
      group.cancelAll()
    }
  }

  private static func listing(
    of directory: AbsolutePath,
    from source: any RawDirectoryReading
  ) async -> DirectoryListing {
    do {
      let children = try await source.children(of: directory)
      return DirectoryListing(directory: directory, children: children, failure: nil)
    } catch {
      return DirectoryListing(directory: directory, children: [], failure: error)
    }
  }

  private static func handle(
    _ failure: any Error,
    in directory: AbsolutePath,
    yield: (EnumerationEvent) -> Void
  ) throws {
    if failure is CancellationError { throw CancellationError() }
    if case .volumeUnavailable = failure as? FileSystemError { throw failure }
    yield(.inaccessible(directory, reason: inaccessibleReason(for: failure)))
  }

  private static func inaccessibleReason(for failure: any Error) -> String {
    let description = failure.localizedDescription
    guard description.isEmpty else { return description }
    return "The directory could not be read."
  }

  private static func process(
    _ record: FileRecord,
    options: EnumerationOptions,
    seen: inout Set<FileIdentity>,
    pending: inout [AbsolutePath],
    yield: (EnumerationEvent) -> Void
  ) {
    if isSkipped(record.path, by: options.skipSubtrees) { return }
    if !options.includesHiddenFiles && record.path.lastComponent.hasPrefix(".") { return }
    let identity = FileIdentity(volumeID: record.volumeID, fileID: record.fileID)
    guard seen.insert(identity).inserted else { return }
    yield(.record(record))
    guard record.isDirectory else { return }
    if !options.descendsIntoPackages && isPackage(record.path) { return }
    pending.append(record.path)
  }

  private static func isSkipped(_ path: AbsolutePath, by skipSubtrees: [AbsolutePath]) -> Bool {
    skipSubtrees.contains { path == $0 || path.isDescendant(of: $0) }
  }

  private static func isPackage(_ path: AbsolutePath) -> Bool {
    let name = path.lastComponent
    guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
    let fileExtension = name[name.index(after: dot)...]
    guard !fileExtension.isEmpty else { return false }
    return packageExtensions.contains(fileExtension.lowercased())
  }
}
