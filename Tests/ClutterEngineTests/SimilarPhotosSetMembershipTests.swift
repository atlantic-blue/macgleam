import CoreGraphics
import Foundation
import GleamCore
import ImageIO
import Testing

@Suite("Similar photos: set membership")
struct SimilarPhotosSetMembershipTests {

  @Test("fixture photographs decode as real images")
  func fixturePhotographsDecodeAsRealImages() throws {
    let candidates: [Data] = [
      SimilarPhotosImageFactory.beach,
      SimilarPhotosImageFactory.beachAnnotated,
      SimilarPhotosImageFactory.beachRetouched,
      SimilarPhotosImageFactory.checker,
      SimilarPhotosImageFactory.checkerAnnotated,
      SimilarPhotosImageFactory.meadow,
    ]
    for data in candidates {
      let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
      let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
      #expect(image.width == SimilarPhotosImageFactory.width)
      #expect(image.height == SimilarPhotosImageFactory.height)
    }
    #expect(SimilarPhotosImageFactory.beach != SimilarPhotosImageFactory.beachAnnotated)
    #expect(SimilarPhotosImageFactory.checker != SimilarPhotosImageFactory.checkerAnnotated)
  }

  // Pin: C21 leaves the grouping algorithm to the engine. The minimal
  // useful behaviour is grouping two pixel identical, byte distinct
  // renderings of one scene; without it no kept path mechanics are
  // reachable at all.
  @Test("groups two pixel identical byte distinct photos into one similar set")
  func groupsPixelIdenticalByteDistinctPhotos() async throws {
    let fileSystem = InMemoryFileSystem()
    let pictures = "\(SimilarPhotosFixtures.home.value)/Pictures"
    let one = "\(pictures)/holiday/beach.png"
    let two = "\(pictures)/holiday/beach-annotated.png"
    await similarPhotosSeed(
      fileSystem,
      files: [
        (one, SimilarPhotosImageFactory.beach),
        (two, SimilarPhotosImageFactory.beachAnnotated),
      ])

    let capture = try await similarPhotosRunScan(fileSystem: fileSystem)

    let set = try #require(capture.similarSets.first)
    let members = Set(set.paths.map(\.value))
    #expect(members.contains(one))
    #expect(members.contains(two))
  }

  @Test("set members always carry image file extensions in a mixed tree")
  func setMembersAlwaysCarryImageExtensions() async throws {
    let fileSystem = InMemoryFileSystem()
    let pictures = "\(SimilarPhotosFixtures.home.value)/Pictures"
    await similarPhotosSeed(
      fileSystem,
      files: [
        ("\(pictures)/holiday/beach.png", SimilarPhotosImageFactory.beach),
        ("\(pictures)/holiday/beach-annotated.png", SimilarPhotosImageFactory.beachAnnotated),
        ("\(pictures)/holiday/notes.txt", SimilarPhotosImageFactory.proseBytes),
        (
          "\(pictures)/holiday/album.zip",
          Data([0x50, 0x4B, 0x03, 0x04]) + SimilarPhotosImageFactory.proseBytes
        ),
        ("\(pictures)/holiday/report.pdf", Data("%PDF-1.4 not a photo".utf8)),
        ("\(pictures)/holiday/clip.mp4", Data(repeating: 0x42, count: 128)),
        ("\(SimilarPhotosFixtures.home.value)/Documents/main.swift", Data("let value = 1".utf8)),
      ])

    let capture = try await similarPhotosRunScan(fileSystem: fileSystem)

    #expect(!capture.similarSets.isEmpty)
    for set in capture.similarSets {
      for member in set.paths {
        #expect(
          similarPhotosImageExtensions.contains(similarPhotosExtension(of: member)),
          "\(member.value) is not an image file"
        )
      }
    }
  }

  // Pin: C21 says every member is an image file but does not define one and
  // says nothing about content sniffing. Pinned as extension based: image
  // bytes under a non image name never join a set.
  @Test("a valid png body named notes.txt is never a member of any set")
  func pngBytesUnderTextNameNeverJoinASet() async throws {
    let fileSystem = InMemoryFileSystem()
    let pictures = "\(SimilarPhotosFixtures.home.value)/Pictures"
    let impostor = "\(pictures)/holiday/notes.txt"
    await similarPhotosSeed(
      fileSystem,
      files: [
        ("\(pictures)/holiday/beach.png", SimilarPhotosImageFactory.beach),
        ("\(pictures)/holiday/beach-annotated.png", SimilarPhotosImageFactory.beachAnnotated),
        // Byte identical image content to the beach photo, wrong name.
        (impostor, SimilarPhotosImageFactory.beach),
      ])

    let capture = try await similarPhotosRunScan(fileSystem: fileSystem)

    #expect(!capture.similarSets.isEmpty)
    for set in capture.similarSets {
      #expect(!set.paths.map(\.value).contains(impostor))
    }
  }

  // Pin: contract is silent on files whose name claims an image format but
  // whose bytes do not. Pinned: the scan completes and the file joins no
  // set, whether the engine screens by content or simply fails to match it.
  @Test("a text body named photo.png completes the scan and joins no set")
  func textBytesUnderImageNameJoinNoSet() async throws {
    let fileSystem = InMemoryFileSystem()
    let pictures = "\(SimilarPhotosFixtures.home.value)/Pictures"
    let impostor = "\(pictures)/holiday/photo.png"
    await similarPhotosSeed(
      fileSystem,
      files: [
        ("\(pictures)/holiday/beach.png", SimilarPhotosImageFactory.beach),
        ("\(pictures)/holiday/beach-annotated.png", SimilarPhotosImageFactory.beachAnnotated),
        (impostor, SimilarPhotosImageFactory.proseBytes),
      ])

    let capture = try await similarPhotosRunScan(fileSystem: fileSystem)

    #expect(!capture.similarSets.isEmpty)
    for set in capture.similarSets {
      #expect(!set.paths.map(\.value).contains(impostor))
    }
  }

  @Test("a tree of documents archives and code yields zero similar photo sets")
  func nonPhotoTreeYieldsNoSets() async throws {
    let fileSystem = InMemoryFileSystem()
    let home = SimilarPhotosFixtures.home.value
    await similarPhotosSeed(
      fileSystem,
      files: [
        ("\(home)/Documents/essay.txt", SimilarPhotosImageFactory.proseBytes),
        ("\(home)/Documents/essay-copy.txt", SimilarPhotosImageFactory.proseBytes),
        ("\(home)/Documents/readme.md", Data("# readme".utf8)),
        ("\(home)/Documents/thesis.pdf", Data("%PDF-1.4 words".utf8)),
        ("\(home)/Downloads/bundle.zip", Data([0x50, 0x4B, 0x03, 0x04, 0x00])),
        ("\(home)/Downloads/backup.tar", Data(repeating: 0x00, count: 512)),
        ("\(home)/Projects/main.swift", Data("print(1)".utf8)),
        ("\(home)/Projects/index.js", Data("console.log(1)".utf8)),
        ("\(home)/Music/song.mp3", Data(repeating: 0x11, count: 64)),
        ("\(home)/Movies/clip.mp4", Data(repeating: 0x22, count: 64)),
      ])

    let capture = try await similarPhotosRunScan(fileSystem: fileSystem)

    #expect(capture.similarSets.isEmpty)
  }
}
