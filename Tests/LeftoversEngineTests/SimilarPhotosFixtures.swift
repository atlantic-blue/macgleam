import Foundation
import GleamCore
import LeftoversEngine

// Fixtures for the similar photos slice. All symbols carry the SimilarPhotos
// prefix so they cannot collide with fixtures from earlier Leftovers slices.

enum SimilarPhotosFixtures {
  static let home = AbsolutePath(normalising: "/Users/similarphotos")
  static let referenceDate = Date(timeIntervalSince1970: 1_755_000_000)
  static let photoDate = Date(timeIntervalSince1970: 1_755_000_000 - 30 * 86_400)
  static let catalogSignature = Data(repeating: 0x7E, count: 64)

  static func settings() -> Settings {
    var settings = Settings.defaults
    settings.deletionMode = .trash
    // Thresholds pushed far out so large and old file findings cannot
    // appear among the similar photo findings under test.
    settings.largeFileThresholdBytes = 1_000_000_000
    settings.oldFileThresholdDays = 10_000
    return settings
  }

  static func catalog(denylistPatterns: [String] = []) -> RuleCatalog {
    RuleCatalog(
      version: RuleCatalogVersion(value: 1),
      signature: catalogSignature,
      cleanupRules: [],
      adwareRules: [],
      denylist: Denylist(patterns: denylistPatterns.map { PathPattern(pattern: $0) })
    )
  }

  static func engine() -> LeftoversEngine {
    LeftoversEngine(userHome: home, referenceDate: referenceDate)
  }

  static func scanContext(
    sessionID: UUID,
    fileSystem: InMemoryFileSystem,
    denylistPatterns: [String] = []
  ) -> ScanContext {
    ScanContext(
      sessionID: sessionID,
      fileSystem: fileSystem,
      rules: catalog(denylistPatterns: denylistPatterns),
      settings: settings(),
      hasFullDiskAccess: true
    )
  }

  static func planContext(
    sessionID: UUID,
    denylistPatterns: [String] = []
  ) -> PlanContext {
    PlanContext(
      sessionID: sessionID,
      rules: catalog(denylistPatterns: denylistPatterns),
      settings: settings(),
      ownership: SimilarPhotosOwnershipPolicy()
    )
  }
}

struct SimilarPhotosOwnershipPolicy: PathOwnershipPolicy {
  func ownership(of path: AbsolutePath, environment: OwnershipEnvironment) -> PathOwnership {
    if path == environment.currentUserHome || path.isDescendant(of: environment.currentUserHome) {
      return .userDomain
    }
    return .systemDomain
  }
}

// MARK: - Byte built photographs

// Minimal valid PNG files assembled byte by byte so the suite needs no
// bundled resources and no real image encoder. A fixture validity test
// decodes them through ImageIO to prove they are real images.
enum SimilarPhotosImageFactory {
  typealias Pixel = (red: UInt8, green: UInt8, blue: UInt8)

  static let width = 8
  static let height = 8

  /// A solid red scene.
  static var beach: Data { png(pixels: solidPixels(200, 40, 40)) }

  /// The beach scene with an extra text chunk: pixel identical to `beach`,
  /// byte distinct from it.
  static var beachAnnotated: Data {
    png(pixels: solidPixels(200, 40, 40), comment: "annotated copy")
  }

  /// The beach scene with a single pixel nudged by one intensity step.
  static var beachRetouched: Data {
    var pixels = solidPixels(200, 40, 40)
    pixels[0][0] = (199, 40, 40)
    return png(pixels: pixels)
  }

  /// A black and white checkerboard scene, unrelated to the beach.
  static var checker: Data { png(pixels: checkerPixels()) }

  /// The checkerboard with an extra text chunk: pixel identical, byte
  /// distinct.
  static var checkerAnnotated: Data {
    png(pixels: checkerPixels(), comment: "annotated copy")
  }

  /// A solid green scene used for byte identical duplicate pairs.
  static var meadow: Data { png(pixels: solidPixels(30, 160, 60)) }

  /// ASCII prose bytes: not an image in any format.
  static var proseBytes: Data {
    Data("These are holiday notes, not a photograph of anything.".utf8)
  }

  static func solidPixels(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> [[Pixel]] {
    Array(repeating: Array(repeating: (red, green, blue), count: width), count: height)
  }

  static func checkerPixels() -> [[Pixel]] {
    (0..<height).map { row in
      (0..<width).map { column in
        (row + column).isMultiple(of: 2) ? (0, 0, 0) : (255, 255, 255)
      }
    }
  }

  static func png(pixels: [[Pixel]], comment: String? = nil) -> Data {
    var raw: [UInt8] = []
    for row in pixels {
      raw.append(0)
      for pixel in row {
        raw.append(contentsOf: [pixel.red, pixel.green, pixel.blue])
      }
    }
    var ihdr = bigEndian32(UInt32(pixels[0].count)) + bigEndian32(UInt32(pixels.count))
    ihdr += [8, 2, 0, 0, 0]

    var file: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    file += chunk("IHDR", ihdr)
    if let comment {
      file += chunk("tEXt", Array("Comment".utf8) + [0] + Array(comment.utf8))
    }
    file += chunk("IDAT", zlibStored(raw))
    file += chunk("IEND", [])
    return Data(file)
  }

  private static func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
    let typeBytes = Array(type.utf8)
    return bigEndian32(UInt32(data.count))
      + typeBytes + data
      + bigEndian32(crc32(typeBytes + data))
  }

  private static func zlibStored(_ raw: [UInt8]) -> [UInt8] {
    let length = UInt16(raw.count)
    var stream: [UInt8] = [0x78, 0x01, 0x01]
    stream += [UInt8(length & 0xFF), UInt8(length >> 8)]
    stream += [UInt8(~length & 0xFF), UInt8((~length) >> 8)]
    stream += raw
    stream += bigEndian32(adler32(raw))
    return stream
  }

  private static func bigEndian32(_ value: UInt32) -> [UInt8] {
    [
      UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
      UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
    ]
  }

  private static func crc32(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
      crc ^= UInt32(byte)
      for _ in 0..<8 {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
      }
    }
    return crc ^ 0xFFFF_FFFF
  }

  private static func adler32(_ bytes: [UInt8]) -> UInt32 {
    var a: UInt32 = 1
    var b: UInt32 = 0
    for byte in bytes {
      a = (a + UInt32(byte)) % 65_521
      b = (b + a) % 65_521
    }
    return (b << 16) | a
  }
}

// MARK: - Seeding

func similarPhotosSeed(
  _ fileSystem: InMemoryFileSystem,
  files: [(path: String, data: Data)]
) async {
  var directories = Set<String>()
  for file in files {
    var components = file.path.split(separator: "/").map(String.init)
    components.removeLast()
    var prefix = ""
    for component in components {
      prefix += "/" + component
      directories.insert(prefix)
    }
  }
  for directory in directories.sorted() {
    await fileSystem.seedDirectory(at: AbsolutePath(normalising: directory))
  }
  for file in files {
    await fileSystem.seedFile(
      at: AbsolutePath(normalising: file.path),
      contents: file.data,
      created: SimilarPhotosFixtures.photoDate,
      modified: SimilarPhotosFixtures.photoDate,
      lastOpened: SimilarPhotosFixtures.photoDate
    )
  }
}

/// The tree most tests share: one pixel identical byte distinct pair per
/// scene plus a byte identical pair that must remain a duplicate set.
func similarPhotosSeedStandardTree(_ fileSystem: InMemoryFileSystem) async {
  let pictures = "\(SimilarPhotosFixtures.home.value)/Pictures"
  await similarPhotosSeed(
    fileSystem,
    files: [
      ("\(pictures)/holiday/beach.png", SimilarPhotosImageFactory.beach),
      ("\(pictures)/holiday/beach-annotated.png", SimilarPhotosImageFactory.beachAnnotated),
      ("\(pictures)/holiday/beach-retouched.png", SimilarPhotosImageFactory.beachRetouched),
      ("\(pictures)/garden/checker.png", SimilarPhotosImageFactory.checker),
      ("\(pictures)/garden/checker-annotated.png", SimilarPhotosImageFactory.checkerAnnotated),
      ("\(pictures)/archive/copy-one.png", SimilarPhotosImageFactory.meadow),
      ("\(pictures)/archive/copy-two.png", SimilarPhotosImageFactory.meadow),
    ])
}

// MARK: - Scan capture

struct SimilarPhotosCapture {
  var phases: [ScanPhase] = []
  var progress: [ScanCounters] = []
  var findings: [Finding] = []
  var degraded: [String] = []

  var similarSets: [Finding] {
    findings.filter { $0.similarPhotosKeptPath != nil }
  }

  var duplicateSets: [Finding] {
    findings.filter { $0.similarPhotosDuplicateKeptPath != nil }
  }
}

func similarPhotosRunScan(
  fileSystem: InMemoryFileSystem,
  sessionID: UUID = UUID(),
  denylistPatterns: [String] = []
) async throws -> SimilarPhotosCapture {
  let engine = SimilarPhotosFixtures.engine()
  let context = SimilarPhotosFixtures.scanContext(
    sessionID: sessionID,
    fileSystem: fileSystem,
    denylistPatterns: denylistPatterns
  )
  var capture = SimilarPhotosCapture()
  for try await event in engine.scan(context) {
    switch event {
    case .phase(let phase):
      capture.phases.append(phase)
    case .progress(let counters):
      capture.progress.append(counters)
    case .reading:
      break
    case .finding(let finding):
      capture.findings.append(finding)
    case .degraded(let unavailable):
      capture.degraded.append(unavailable)
    }
  }
  return capture
}

// MARK: - Small helpers

extension Finding {
  var similarPhotosKeptPath: AbsolutePath? {
    if case .similarPhotoSet(let keptPath) = category { return keptPath }
    return nil
  }

  var similarPhotosDuplicateKeptPath: AbsolutePath? {
    if case .duplicateSet(let keptPath) = category { return keptPath }
    return nil
  }
}

extension Operation.Kind {
  var similarPhotosTarget: AbsolutePath? {
    switch self {
    case .moveToTrash(let target): return target
    case .deletePermanently(let target): return target
    case .quarantine(let target): return target
    case .archive(let target, _): return target
    case .setLaunchItemEnabled, .runMaintenance: return nil
    }
  }
}

struct SimilarPhotosSetShape: Hashable {
  let keptPath: String
  let members: Set<String>

  init(_ finding: Finding) {
    keptPath = finding.similarPhotosKeptPath?.value ?? ""
    members = Set(finding.paths.map(\.value))
  }
}

func similarPhotosExtension(of path: AbsolutePath) -> String {
  let name = path.lastComponent
  guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
  return String(name[name.index(after: dot)...]).lowercased()
}

let similarPhotosImageExtensions: Set<String> = [
  "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp",
]
