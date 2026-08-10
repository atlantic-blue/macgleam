import CoreGraphics
import Foundation
import GleamCore
import ImageIO

// MARK: - Similar photo sets

extension LeftoversEngine {
  /// Membership is by file name alone: image bytes under another name never
  /// join, and non image bytes under one of these names are dropped at
  /// decode time instead of failing the scan.
  private static let imageExtensions: Set<String> = [
    "png", "jpg", "jpeg", "heic", "gif", "tiff", "tif", "bmp", "webp",
  ]

  /// The fingerprint is the photo downsampled to this many grayscale samples
  /// per edge. Two byte distinct encodings of one scene decode to the same
  /// pixels and so the same grid, while distinct scenes diverge.
  private static let fingerprintGridEdge = 8

  /// Two fingerprints describe similar photos when their summed absolute
  /// sample difference stays within this budget: four gray levels per sample
  /// on average, tight enough to reject distinct scenes while admitting the
  /// decode noise of re encoded copies.
  private static let similarityDifferenceBudget = 4 * 64

  /// Groups near identical photos into similar set findings. Byte identical
  /// photos are duplicates and never similar, so any photo whose duplicate
  /// set holds another photo is excluded before grouping. A photo whose only
  /// byte twins carry non image names keeps competing for similarity: that
  /// duplicate set claims the twins, not the photo's likeness.
  func similarPhotoSetFindings(
    _ files: [FileRecord],
    duplicates: [Finding],
    context: ScanContext
  ) async throws -> [Finding] {
    let claimed = Self.photosClaimedByDuplicates(duplicates)
    let candidates = files.filter {
      Self.hasImageExtension($0.path) && !claimed.contains($0.path)
    }
    let fingerprints = try await photoFingerprints(
      of: candidates, fileSystem: context.fileSystem)
    return groupedBySimilarity(fingerprints)
      .map { similarPhotoSetFinding(for: $0, context: context) }
      .sorted { $0.paths[0] < $1.paths[0] }
  }

  private static func photosClaimedByDuplicates(_ duplicates: [Finding]) -> Set<AbsolutePath> {
    var claimed: Set<AbsolutePath> = []
    for finding in duplicates {
      let imageMembers = finding.paths.filter(hasImageExtension)
      guard imageMembers.count >= 2 else { continue }
      claimed.formUnion(imageMembers)
    }
    return claimed
  }

  private static func hasImageExtension(_ path: AbsolutePath) -> Bool {
    guard let name = path.value.split(separator: "/").last,
      let dot = name.lastIndex(of: "."), dot != name.startIndex
    else { return false }
    return imageExtensions.contains(name[name.index(after: dot)...].lowercased())
  }

  private struct PhotoFingerprint {
    let record: FileRecord
    let grid: [UInt8]
  }

  /// Reads and decodes each candidate, skipping any whose bytes cannot be
  /// read or do not decode as an image, mirroring the duplicate scanner's
  /// skip semantics so a hostile file never sinks the scan.
  private func photoFingerprints(
    of candidates: [FileRecord],
    fileSystem: any FileSystemReading
  ) async throws -> [PhotoFingerprint] {
    var fingerprints: [PhotoFingerprint] = []
    for record in candidates {
      try Task.checkCancellation()
      let content: Data
      do {
        content = try await fileSystem.readData(at: record.path, maxBytes: .max)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        continue
      }
      guard let grid = Self.grayscaleGrid(of: content) else { continue }
      fingerprints.append(PhotoFingerprint(record: record, grid: grid))
    }
    return fingerprints
  }

  private static func grayscaleGrid(of content: Data) -> [UInt8]? {
    guard let source = CGImageSourceCreateWithData(content as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let edge = fingerprintGridEdge
    var samples = [UInt8](repeating: 0, count: edge * edge)
    let drawn = samples.withUnsafeMutableBytes { buffer in
      guard
        let canvas = CGContext(
          data: buffer.baseAddress, width: edge, height: edge,
          bitsPerComponent: 8, bytesPerRow: edge,
          space: CGColorSpaceCreateDeviceGray(),
          bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else { return false }
      canvas.interpolationQuality = .high
      canvas.draw(image, in: CGRect(x: 0, y: 0, width: edge, height: edge))
      return true
    }
    return drawn ? samples : nil
  }

  /// Disjoint grouping by pairwise similarity. Union find keeps the sets
  /// non overlapping by construction, and the path sorted input keeps the
  /// grouping deterministic across scans of one tree.
  private func groupedBySimilarity(_ fingerprints: [PhotoFingerprint]) -> [[FileRecord]] {
    var parents = Array(fingerprints.indices)
    func root(of index: Int) -> Int {
      var current = index
      while parents[current] != current { current = parents[current] }
      return current
    }
    for first in fingerprints.indices {
      for second in fingerprints.indices.dropFirst(first + 1)
      where Self.areSimilar(fingerprints[first].grid, fingerprints[second].grid) {
        parents[root(of: second)] = root(of: first)
      }
    }
    return Dictionary(grouping: fingerprints.indices, by: root(of:))
      .values
      .filter { $0.count >= 2 }
      .map { indices in indices.map { fingerprints[$0].record } }
  }

  private static func areSimilar(_ first: [UInt8], _ second: [UInt8]) -> Bool {
    var difference = 0
    for index in first.indices {
      difference += abs(Int(first[index]) - Int(second[index]))
    }
    return difference <= similarityDifferenceBudget
  }

  /// The kept copy is the lexicographically smallest path, the same rule as
  /// duplicate sets, so the choice is deterministic across scans.
  private func similarPhotoSetFinding(
    for group: [FileRecord],
    context: ScanContext
  ) -> Finding {
    let members = group.sorted { $0.path < $1.path }
    let keptPath = members[0].path
    return Finding(
      id: UUID(),
      sessionID: context.sessionID,
      category: .similarPhotoSet(keptPath: keptPath),
      entries: members.map { PathEntry(path: $0.path, allocatedBytes: $0.allocatedBytes) },
      risk: .review,
      explanation:
        "These \(members.count) photos look like versions of the same scene. "
        + "The copy at \(keptPath.value) is kept, "
        + "and removing the others reclaims the near duplicated space.",
      isPreselected: false)
  }
}
