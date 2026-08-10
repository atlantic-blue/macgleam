import DiskMapEngine
import Foundation
import GleamCore
import Testing

@Suite("Disk map: streaming and structure")
struct DiskMapStreamingTests {

  @Test("the engine names the disk map module")
  func engineNamesTheDiskMapModule() {
    #expect(DiskMapEngine().module == .diskMap)
  }

  @Test("every seeded file and directory arrives as a node")
  func everySeededPathArrivesAsANode() async throws {
    let fileSystem = await LensTree.seeded()
    let outcome = try await runMap(over: fileSystem, rules: try LensTree.catalog())

    let expected: Set<AbsolutePath> = Set(
      LensTree.files.map { DiskMapFixture.path($0.path) } + [
        DiskMapFixture.path(LensTree.documentsDirectory),
        DiskMapFixture.path(LensTree.reportsDirectory),
        DiskMapFixture.path(LensTree.picturesDirectory),
        DiskMapFixture.path(LensTree.protectedDirectory),
        DiskMapFixture.path("/Users/lens/Library"),
        DiskMapFixture.path("/Users/lens"),
        DiskMapFixture.path("/Users"),
      ])
    #expect(outcome.nodePaths.isSuperset(of: expected))
  }

  @Test("the map builds outward from the root: every node's parent was already streamed")
  func everyNodesParentWasAlreadyStreamed() async throws {
    let fileSystem = await LensTree.seeded()
    let outcome = try await runMap(over: fileSystem, rules: try LensTree.catalog())

    var seen = Set<AbsolutePath>()
    for node in outcome.nodesInOrder {
      if let parent = node.parent {
        #expect(
          seen.contains(parent),
          "\(node.path.value) streamed before its parent \(parent.value)")
      }
      seen.insert(node.path)
    }
  }

  @Test("each node links to its parent and the mapped volume root has none")
  func nodesLinkToTheirParents() async throws {
    let fileSystem = await LensTree.seeded()
    let outcome = try await runMap(over: fileSystem, rules: try LensTree.catalog())

    let root = try #require(outcome.node(at: DiskMapFixture.volumeRoot))
    #expect(root.parent == nil)
    #expect(root.isDirectory)

    let reports = try #require(
      outcome.node(at: DiskMapFixture.path(LensTree.reportsDirectory)))
    #expect(reports.parent == DiskMapFixture.path(LensTree.documentsDirectory))
    #expect(reports.isDirectory)

    let q1 = try #require(outcome.node(at: DiskMapFixture.path(LensTree.reportQ1)))
    #expect(q1.parent == DiskMapFixture.path(LensTree.reportsDirectory))
    #expect(q1.isDirectory == false)
  }

  @Test("the stream terminates with exactly one completed event, after everything else")
  func exactlyOneCompletedEventTerminatesTheStream() async throws {
    let fileSystem = await LensTree.seeded()
    let outcome = try await runMap(over: fileSystem, rules: try LensTree.catalog())

    #expect(outcome.completedCount == 1)
    #expect(outcome.updates.last == .completed)
  }
}

@Suite("Disk map: totals only grow and converge")
struct DiskMapTotalTests {

  @Test("a node's reported subtree total never decreases across the stream")
  func subtreeTotalsNeverDecrease() async throws {
    let fileSystem = await LensTree.seeded(extraDocumentFiles: 40)
    let outcome = try await runMap(over: fileSystem, rules: try LensTree.catalog())

    for path in outcome.nodePaths {
      let history = outcome.totalHistory(for: path)
      #expect(
        isNonDecreasing(history),
        "totals for \(path.value) went backwards: \(history)")
    }
  }

  @Test("totals converge to the true allocated subtree totals when the stream completes")
  func totalsConvergeToTrueAllocatedTotals() async throws {
    let fileSystem = await LensTree.seeded()
    let outcome = try await runMap(over: fileSystem, rules: try LensTree.catalog())
    let expected = try await trueSubtreeTotals(on: fileSystem)

    let finals = outcome.finalTotals
    for (path, trueTotal) in expected {
      guard outcome.nodePaths.contains(path) else { continue }
      #expect(
        finals[path] == trueTotal,
        "\(path.value) converged to \(String(describing: finals[path])), true total \(trueTotal)")
    }
  }

  @Test("a file node's converged total is the file's own allocated bytes")
  func fileNodeTotalIsItsAllocatedBytes() async throws {
    let fileSystem = await LensTree.seeded()
    let outcome = try await runMap(over: fileSystem, rules: try LensTree.catalog())

    let photoPath = DiskMapFixture.path(LensTree.photo)
    let expected = try await allocatedBytes(of: LensTree.photo, on: fileSystem)
    #expect(outcome.finalTotals[photoPath] == expected)
  }

  @Test("the root's converged total covers every allocated byte on the volume")
  func rootTotalCoversTheWholeVolume() async throws {
    let fileSystem = await LensTree.seeded()
    let outcome = try await runMap(over: fileSystem, rules: try LensTree.catalog())
    let expected = try await trueSubtreeTotals(on: fileSystem)

    #expect(
      outcome.finalTotals[DiskMapFixture.volumeRoot] == expected[DiskMapFixture.volumeRoot])
  }

  @Test("two maps of the same tree converge to identical totals and structure")
  func mappingIsDeterministic() async throws {
    let fileSystem = await LensTree.seeded(extraDocumentFiles: 10)
    let catalog = try LensTree.catalog()
    let first = try await runMap(over: fileSystem, rules: catalog)
    let second = try await runMap(over: fileSystem, rules: catalog)

    #expect(first.nodePaths == second.nodePaths)
    #expect(first.finalTotals == second.finalTotals)
    #expect(first.selectabilityByPath == second.selectabilityByPath)
  }
}

@Suite("Disk map: denylisted nodes render but are not selectable")
struct DiskMapSelectabilityTests {

  @Test("a denylisted directory arrives as a node with isSelectable false")
  func denylistedDirectoryRendersUnselectable() async throws {
    let fileSystem = await LensTree.seeded()
    let outcome = try await runMap(over: fileSystem, rules: try LensTree.catalog())

    let protected = try #require(
      outcome.node(at: DiskMapFixture.path(LensTree.protectedDirectory)))
    #expect(protected.isSelectable == false)
  }

  @Test("a descendant of a denylisted directory is also unselectable")
  func denylistedDescendantIsUnselectable() async throws {
    let fileSystem = await LensTree.seeded()
    let outcome = try await runMap(over: fileSystem, rules: try LensTree.catalog())

    let keychain = try #require(
      outcome.node(at: DiskMapFixture.path(LensTree.protectedKeychain)))
    #expect(keychain.isSelectable == false)
  }

  @Test("paths the denylist does not block are selectable")
  func unblockedPathsAreSelectable() async throws {
    let fileSystem = await LensTree.seeded()
    let outcome = try await runMap(over: fileSystem, rules: try LensTree.catalog())

    for path in [LensTree.documentsDirectory, LensTree.reportQ1, LensTree.photo] {
      let node = try #require(outcome.node(at: DiskMapFixture.path(path)))
      #expect(node.isSelectable, "\(path) should be selectable")
    }
  }
}

@Suite("Disk map: cancellation")
struct DiskMapCancellationTests {

  @Test("cancelling the consuming task ends the stream promptly")
  func cancellingTheConsumerEndsTheStreamPromptly() async throws {
    let fileSystem = await LensTree.seeded(extraDocumentFiles: 200)
    let context = makeScanContext(over: fileSystem, rules: try LensTree.catalog())

    let (sawNodes, sawNodesContinuation) = AsyncStream<Void>.makeStream()
    let consumer = Task {
      var received = 0
      do {
        for try await update in DiskMapEngine().map(
          volume: DiskMapFixture.volumeRoot, context: context)
        {
          if case .node = update {
            received += 1
            if received == 3 {
              sawNodesContinuation.yield(())
            }
          }
        }
      } catch {
        // A cancelled stream may end by throwing; either ending is prompt.
      }
    }
    var iterator = sawNodes.makeAsyncIterator()
    _ = await iterator.next()
    consumer.cancel()

    let finishedPromptly = await completesPromptly {
      await consumer.value
    }
    #expect(finishedPromptly)
  }
}
