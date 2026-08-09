import Foundation
import GleamCore
import Testing

/// Tests for the enumeration engine behind C13's enumerate, driven through
/// the raw platform seam so platform misbehaviour can be scripted. The
/// deduplication case models the macOS Sequoia regression where the bulk
/// attribute call repeats entries: the raw source repeats every child and
/// the engine must still yield each (volumeID, fileID) pair once.
private let engineRoot = Fixture.path("/scan")

/// A raw platform source with a scripted listing per directory, optional
/// scripted failures, and an optional repeat factor for every entry.
private struct ScriptedRawSource: RawDirectoryReading {
  var listing: [AbsolutePath: [FileRecord]] = [:]
  var failures: [AbsolutePath: FileSystemError] = [:]
  var repeatsEachEntry = 1

  func children(of directory: AbsolutePath) async throws -> [FileRecord] {
    if let failure = failures[directory] {
      throw failure
    }
    return (listing[directory] ?? []).flatMap {
      Array(repeating: $0, count: repeatsEachEntry)
    }
  }
}

/// A raw source whose tree never ends: every directory holds one file and
/// one deeper directory. Only cancellation can end an enumeration of it.
private struct BottomlessRawSource: RawDirectoryReading {
  func children(of directory: AbsolutePath) async throws -> [FileRecord] {
    let depth = UInt64(directory.value.split(separator: "/").count)
    return [
      makeFileRecord(path: directory.appending("file.txt"), fileID: depth * 2 + 1),
      makeDirectoryRecord(path: directory.appending("deeper"), fileID: depth * 2 + 2),
    ]
  }
}

@Suite("Enumeration engine: traversal")
struct EnumerationEngineTraversalTests {

  @Test("the engine descends into subdirectories and yields their records")
  func engineDescendsIntoSubdirectories() async throws {
    let sub = engineRoot.appending("sub")
    let source = ScriptedRawSource(listing: [
      engineRoot: [
        makeDirectoryRecord(path: sub, fileID: 1),
        makeFileRecord(path: engineRoot.appending("top.txt"), fileID: 2),
      ],
      sub: [
        makeFileRecord(path: sub.appending("nested.txt"), fileID: 3)
      ],
    ])
    let outcome = try await collectEnumeration(
      FileSystemEnumerator(source: source).enumerate(root: engineRoot, options: .default)
    )
    #expect(
      outcome.recordPaths == [
        sub,
        engineRoot.appending("top.txt"),
        sub.appending("nested.txt"),
      ])
  }

  @Test("the engine yields nothing at or under a skipped subtree")
  func engineOmitsSkippedSubtrees() async throws {
    let skipped = engineRoot.appending("skipme")
    let kept = engineRoot.appending("keep")
    let source = ScriptedRawSource(listing: [
      engineRoot: [
        makeDirectoryRecord(path: skipped, fileID: 1),
        makeDirectoryRecord(path: kept, fileID: 2),
        makeFileRecord(path: engineRoot.appending("top.txt"), fileID: 3),
      ],
      skipped: [makeFileRecord(path: skipped.appending("s.txt"), fileID: 4)],
      kept: [makeFileRecord(path: kept.appending("k.txt"), fileID: 5)],
    ])
    let outcome = try await collectEnumeration(
      FileSystemEnumerator(source: source).enumerate(
        root: engineRoot,
        options: makeEnumerationOptions(skipSubtrees: [skipped])
      )
    )
    #expect(
      outcome.recordPaths == [
        kept,
        engineRoot.appending("top.txt"),
        kept.appending("k.txt"),
      ])
  }

  @Test("the engine omits dot prefixed entries and their subtrees when hidden files are excluded")
  func engineOmitsHiddenEntriesWhenExcluded() async throws {
    let hiddenDirectory = engineRoot.appending(".shadow")
    let source = ScriptedRawSource(listing: [
      engineRoot: [
        makeFileRecord(path: engineRoot.appending(".secret.txt"), fileID: 1),
        makeDirectoryRecord(path: hiddenDirectory, fileID: 2),
        makeFileRecord(path: engineRoot.appending("shown.txt"), fileID: 3),
      ],
      hiddenDirectory: [
        makeFileRecord(path: hiddenDirectory.appending("inside.txt"), fileID: 4)
      ],
    ])
    let outcome = try await collectEnumeration(
      FileSystemEnumerator(source: source).enumerate(
        root: engineRoot,
        options: makeEnumerationOptions(includesHiddenFiles: false)
      )
    )
    #expect(outcome.recordPaths == [engineRoot.appending("shown.txt")])
  }

  @Test("the engine includes dot prefixed entries when hidden files are included")
  func engineIncludesHiddenEntriesWhenIncluded() async throws {
    let hiddenDirectory = engineRoot.appending(".shadow")
    let source = ScriptedRawSource(listing: [
      engineRoot: [
        makeFileRecord(path: engineRoot.appending(".secret.txt"), fileID: 1),
        makeDirectoryRecord(path: hiddenDirectory, fileID: 2),
        makeFileRecord(path: engineRoot.appending("shown.txt"), fileID: 3),
      ],
      hiddenDirectory: [
        makeFileRecord(path: hiddenDirectory.appending("inside.txt"), fileID: 4)
      ],
    ])
    let outcome = try await collectEnumeration(
      FileSystemEnumerator(source: source).enumerate(
        root: engineRoot,
        options: makeEnumerationOptions(includesHiddenFiles: true)
      )
    )
    #expect(
      outcome.recordPaths == [
        engineRoot.appending(".secret.txt"),
        hiddenDirectory,
        engineRoot.appending("shown.txt"),
        hiddenDirectory.appending("inside.txt"),
      ])
  }
}

@Suite("Enumeration engine: deduplication")
struct EnumerationEngineDeduplicationTests {

  @Test("each (volumeID, fileID) pair is yielded once when the platform repeats every entry")
  func repeatedRawEntriesAreYieldedOnce() async throws {
    let sub = engineRoot.appending("sub")
    let source = ScriptedRawSource(
      listing: [
        engineRoot: [
          makeFileRecord(path: engineRoot.appending("a.txt"), fileID: 1),
          makeFileRecord(path: engineRoot.appending("b.txt"), fileID: 2),
          makeDirectoryRecord(path: sub, fileID: 3),
        ],
        sub: [
          makeFileRecord(path: sub.appending("c.txt"), fileID: 4)
        ],
      ],
      repeatsEachEntry: 2
    )
    let outcome = try await collectEnumeration(
      FileSystemEnumerator(source: source).enumerate(root: engineRoot, options: .default)
    )
    #expect(outcome.identities.count == Set(outcome.identities).count)
    #expect(
      Set(outcome.identities) == [
        FileIdentity(volumeID: 1, fileID: 1),
        FileIdentity(volumeID: 1, fileID: 2),
        FileIdentity(volumeID: 1, fileID: 3),
        FileIdentity(volumeID: 1, fileID: 4),
      ])
  }

  @Test("two paths sharing one file identity yield a single record")
  func hardLinkedIdentityIsYieldedOnce() async throws {
    let source = ScriptedRawSource(listing: [
      engineRoot: [
        makeFileRecord(path: engineRoot.appending("original.txt"), fileID: 7),
        makeFileRecord(path: engineRoot.appending("hardlink.txt"), fileID: 7),
      ]
    ])
    let outcome = try await collectEnumeration(
      FileSystemEnumerator(source: source).enumerate(root: engineRoot, options: .default)
    )
    let matching = outcome.records.filter {
      FileIdentity($0) == FileIdentity(volumeID: 1, fileID: 7)
    }
    #expect(matching.count == 1)
  }

  @Test("equal file identifiers on different volumes are different files and both yield")
  func equalFileIdentifiersOnDifferentVolumesBothYield() async throws {
    let source = ScriptedRawSource(listing: [
      engineRoot: [
        makeFileRecord(path: engineRoot.appending("internal.txt"), fileID: 9, volumeID: 1),
        makeFileRecord(path: engineRoot.appending("external.txt"), fileID: 9, volumeID: 2),
      ]
    ])
    let outcome = try await collectEnumeration(
      FileSystemEnumerator(source: source).enumerate(root: engineRoot, options: .default)
    )
    #expect(
      Set(outcome.identities) == [
        FileIdentity(volumeID: 1, fileID: 9),
        FileIdentity(volumeID: 2, fileID: 9),
      ])
  }
}

@Suite("Enumeration engine: failures")
struct EnumerationEngineFailureTests {

  @Test(
    "an unreadable subdirectory is reported as inaccessible with a reason and siblings keep enumerating"
  )
  func unreadableSubdirectoryIsReportedAndEnumerationContinues() async throws {
    let locked = engineRoot.appending("locked")
    let source = ScriptedRawSource(
      listing: [
        engineRoot: [
          makeDirectoryRecord(path: locked, fileID: 1),
          makeFileRecord(path: engineRoot.appending("sibling.txt"), fileID: 2),
        ]
      ],
      failures: [locked: .permissionDenied(locked)]
    )
    let outcome = try await collectEnumeration(
      FileSystemEnumerator(source: source).enumerate(root: engineRoot, options: .default)
    )
    let reported = outcome.inaccessible.filter { $0.path == locked }
    #expect(reported.count == 1)
    #expect(!(reported.first?.reason.isEmpty ?? true))
    #expect(outcome.recordPaths.contains(engineRoot.appending("sibling.txt")))
  }

  @Test("an unreadable root is reported as inaccessible, not thrown")
  func unreadableRootIsReportedNotThrown() async throws {
    let source = ScriptedRawSource(
      failures: [engineRoot: .permissionDenied(engineRoot)]
    )
    let outcome = try await collectEnumeration(
      FileSystemEnumerator(source: source).enumerate(root: engineRoot, options: .default)
    )
    #expect(outcome.records.isEmpty)
    #expect(outcome.inaccessible.map(\.path) == [engineRoot])
  }

  @Test("a volume level failure throws out of the stream")
  func volumeLevelFailureThrows() async throws {
    let source = ScriptedRawSource(
      failures: [engineRoot: .volumeUnavailable(engineRoot)]
    )
    await #expect(throws: FileSystemError.volumeUnavailable(engineRoot)) {
      _ = try await collectEnumeration(
        FileSystemEnumerator(source: source).enumerate(root: engineRoot, options: .default)
      )
    }
  }
}

@Suite("Enumeration engine: cancellation")
struct EnumerationEngineCancellationTests {

  @Test("cancelling the consuming task ends a bottomless enumeration promptly")
  func cancellationEndsBottomlessEnumerationPromptly() async throws {
    let stream = FileSystemEnumerator(source: BottomlessRawSource()).enumerate(
      root: engineRoot,
      options: .default
    )
    let (enoughSeen, enoughSeenContinuation) = AsyncStream.makeStream(of: Void.self)
    let consumer = Task {
      var seen = 0
      do {
        for try await event in stream {
          if case .record = event {
            seen += 1
            if seen == 5 {
              enoughSeenContinuation.yield()
            }
          }
        }
      } catch {
        // Ending in cancellation is acceptable; the assertion is prompt
        // termination of a stream that would otherwise never end.
      }
      return seen
    }
    var signal = enoughSeen.makeAsyncIterator()
    _ = await signal.next()
    consumer.cancel()
    let endedPromptly = await completesPromptly {
      _ = await consumer.value
    }
    #expect(endedPromptly, "the bottomless enumeration kept running after cancellation")
  }
}
