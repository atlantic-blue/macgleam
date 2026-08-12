import Darwin
import Foundation

/// The real file system. Directory listing uses getattrlistbulk so one call
/// returns names and metadata together; the enumerator on top bounds the
/// number of concurrent directory reads. Trash goes through the platform
/// trash and returns the resolved destination. Nothing shells out.
public struct DiskFileSystem: Sendable {
  public init() {}

  static func posixError(_ code: Int32, at path: AbsolutePath) -> FileSystemError {
    switch code {
    case ENOENT, ENOTDIR: return .notFound(path)
    case EACCES, EPERM: return .permissionDenied(path)
    case EEXIST: return .destinationOccupied(path)
    case ENODEV, ENXIO: return .volumeUnavailable(path)
    default: return .ioFailure(path, description: String(cString: strerror(code)))
    }
  }

  static func cocoaError(_ error: any Error, at path: AbsolutePath) -> FileSystemError {
    let underlying = error as NSError
    if underlying.domain == NSCocoaErrorDomain {
      switch underlying.code {
      case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return .notFound(path)
      case NSFileWriteFileExistsError: return .destinationOccupied(path)
      case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
        return .permissionDenied(path)
      default: break
      }
    }
    if underlying.domain == NSPOSIXErrorDomain {
      return posixError(Int32(underlying.code), at: path)
    }
    return .ioFailure(path, description: underlying.localizedDescription)
  }
}

// MARK: - RawDirectoryReading

extension DiskFileSystem: RawDirectoryReading {
  public func children(of directory: AbsolutePath) async throws -> [FileRecord] {
    let descriptor = open(directory.value, O_RDONLY | O_DIRECTORY)
    guard descriptor >= 0 else { throw Self.posixError(errno, at: directory) }
    defer { close(descriptor) }
    var request = BulkAttributes.request()
    var records: [FileRecord] = []
    var buffer = [UInt8](repeating: 0, count: 256 * 1024)
    while true {
      let entryCount = buffer.withUnsafeMutableBytes { raw in
        getattrlistbulk(descriptor, &request, raw.baseAddress, raw.count, 0)
      }
      guard entryCount >= 0 else { throw Self.posixError(errno, at: directory) }
      guard entryCount > 0 else { break }
      buffer.withUnsafeBytes { raw in
        BulkAttributes.parse(raw, entryCount: Int(entryCount), directory: directory, into: &records)
      }
    }
    return records
  }
}

/// Layout constants and the record parser for getattrlistbulk buffers.
/// Attribute data is packed in the canonical order of sys/attr.h, each field
/// aligned to four bytes.
private enum BulkAttributes {
  static let returnedAttrs: UInt32 = 0x8000_0000  // ATTR_CMN_RETURNED_ATTRS
  static let name: UInt32 = 0x0000_0001  // ATTR_CMN_NAME
  static let deviceID: UInt32 = 0x0000_0002  // ATTR_CMN_DEVID
  static let objectType: UInt32 = 0x0000_0008  // ATTR_CMN_OBJTYPE
  static let createdTime: UInt32 = 0x0000_0200  // ATTR_CMN_CRTIME
  static let modifiedTime: UInt32 = 0x0000_0400  // ATTR_CMN_MODTIME
  static let accessedTime: UInt32 = 0x0000_1000  // ATTR_CMN_ACCTIME
  static let accessMask: UInt32 = 0x0002_0000  // ATTR_CMN_ACCESSMASK
  static let fileID: UInt32 = 0x0200_0000  // ATTR_CMN_FILEID
  static let allocatedSize: UInt32 = 0x0000_0004  // ATTR_FILE_ALLOCSIZE

  static let regularFileType: UInt32 = 1  // VREG
  static let directoryType: UInt32 = 2  // VDIR

  static func request() -> attrlist {
    var request = attrlist()
    request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
    request.commonattr =
      returnedAttrs | name | deviceID | objectType | createdTime | modifiedTime | accessedTime
      | accessMask | fileID
    request.fileattr = allocatedSize
    return request
  }

  static func parse(
    _ raw: UnsafeRawBufferPointer,
    entryCount: Int,
    directory: AbsolutePath,
    into records: inout [FileRecord]
  ) {
    var offset = 0
    for _ in 0..<entryCount {
      let entryLength = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
      if let record = parseEntry(raw, at: offset, directory: directory) {
        records.append(record)
      }
      offset += entryLength
    }
  }

  private static func parseEntry(
    _ raw: UnsafeRawBufferPointer,
    at entryStart: Int,
    directory: AbsolutePath
  ) -> FileRecord? {
    var reader = FieldReader(raw: raw, offset: entryStart + 4)
    let returnedCommon = reader.uint32()
    _ = reader.uint32()  // volume attribute set
    _ = reader.uint32()  // directory attribute set
    let returnedFile = reader.uint32()
    _ = reader.uint32()  // fork attribute set

    guard returnedCommon & name != 0, let entryName = reader.attributeString() else { return nil }
    let volumeID = returnedCommon & deviceID != 0 ? UInt64(bitPattern: Int64(reader.int32())) : 0
    let entryType = returnedCommon & objectType != 0 ? reader.uint32() : 0
    let created = returnedCommon & createdTime != 0 ? reader.date() : nil
    let modified = returnedCommon & modifiedTime != 0 ? reader.date() : nil
    let lastOpened = returnedCommon & accessedTime != 0 ? reader.date() : nil
    let mode = returnedCommon & accessMask != 0 ? reader.uint32() : 0
    let entryFileID = returnedCommon & fileID != 0 ? reader.uint64() : 0
    let allocated = returnedFile & allocatedSize != 0 ? reader.uint64() : 0

    return FileRecord(
      path: AbsolutePath(normalising: directory.value + "/" + entryName),
      fileID: entryFileID,
      volumeID: volumeID,
      allocatedBytes: entryType == directoryType ? 0 : allocated,
      isDirectory: entryType == directoryType,
      isExecutable: entryType == regularFileType && mode & 0o100 != 0,
      created: created,
      modified: modified,
      lastOpened: lastOpened)
  }

  private struct FieldReader {
    let raw: UnsafeRawBufferPointer
    var offset: Int

    mutating func uint32() -> UInt32 {
      defer { offset += 4 }
      return raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
    }

    mutating func int32() -> Int32 {
      defer { offset += 4 }
      return raw.loadUnaligned(fromByteOffset: offset, as: Int32.self)
    }

    mutating func uint64() -> UInt64 {
      defer { offset += 8 }
      return raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
    }

    mutating func date() -> Date? {
      let seconds = raw.loadUnaligned(fromByteOffset: offset, as: Int64.self)
      let nanoseconds = raw.loadUnaligned(fromByteOffset: offset + 8, as: Int64.self)
      offset += 16
      guard seconds != 0 || nanoseconds != 0 else { return nil }
      return Date(
        timeIntervalSince1970: Double(seconds) + Double(nanoseconds) / 1_000_000_000)
    }

    mutating func attributeString() -> String? {
      let referenceStart = offset
      let dataOffset = Int(raw.loadUnaligned(fromByteOffset: offset, as: Int32.self))
      let dataLength = Int(raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
      offset += 8
      let start = referenceStart + dataOffset
      guard dataLength > 0, start >= 0, start + dataLength <= raw.count else { return nil }
      let bytes = raw[start..<(start + dataLength)].prefix { $0 != 0 }
      return String(decoding: bytes, as: UTF8.self)
    }
  }
}

// MARK: - FileSystemReading

extension DiskFileSystem: FileSystemReading {
  public func enumerate(
    root: AbsolutePath,
    options: EnumerationOptions
  ) -> AsyncThrowingStream<EnumerationEvent, Error> {
    FileSystemEnumerator(source: self).enumerate(root: root, options: options)
  }

  public func metadata(at path: AbsolutePath) async throws -> FileRecord {
    var status = stat()
    guard lstat(path.value, &status) == 0 else { throw Self.posixError(errno, at: path) }
    let format = UInt32(status.st_mode) & 0o170000
    let isDirectory = format == 0o040000
    let isRegular = format == 0o100000
    return FileRecord(
      path: path,
      fileID: status.st_ino,
      volumeID: UInt64(bitPattern: Int64(status.st_dev)),
      allocatedBytes: isDirectory ? 0 : UInt64(clamping: status.st_blocks) * 512,
      isDirectory: isDirectory,
      isExecutable: isRegular && UInt32(status.st_mode) & 0o100 != 0,
      created: Self.date(from: status.st_birthtimespec),
      modified: Self.date(from: status.st_mtimespec),
      lastOpened: Self.date(from: status.st_atimespec))
  }

  public func posixPermissions(at path: AbsolutePath) async throws -> UInt16 {
    var status = stat()
    guard lstat(path.value, &status) == 0 else { throw Self.posixError(errno, at: path) }
    return UInt16(status.st_mode & 0o7777)
  }

  public func readData(at path: AbsolutePath, maxBytes: UInt64) async throws -> Data {
    guard FileManager.default.fileExists(atPath: path.value) else {
      throw FileSystemError.notFound(path)
    }
    guard let handle = FileHandle(forReadingAtPath: path.value) else {
      throw FileSystemError.permissionDenied(path)
    }
    defer { try? handle.close() }
    do {
      let limit = Int(min(maxBytes, UInt64(Int.max)))
      return try handle.read(upToCount: limit) ?? Data()
    } catch {
      throw FileSystemError.ioFailure(path, description: error.localizedDescription)
    }
  }

  public func extendedAttributes(at path: AbsolutePath) async throws -> [String: Data] {
    let size = listxattr(path.value, nil, 0, XATTR_NOFOLLOW)
    guard size >= 0 else { throw Self.posixError(errno, at: path) }
    guard size > 0 else { return [:] }
    var nameBuffer = [CChar](repeating: 0, count: size)
    let written = listxattr(path.value, &nameBuffer, size, XATTR_NOFOLLOW)
    guard written >= 0 else { throw Self.posixError(errno, at: path) }
    let names = nameBuffer[..<written]
      .split(separator: 0)
      .map { chunk in String(decoding: chunk.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
    var attributes: [String: Data] = [:]
    for name in names {
      attributes[name] = try attributeValue(named: name, at: path)
    }
    return attributes
  }

  private func attributeValue(named name: String, at path: AbsolutePath) throws -> Data {
    let size = getxattr(path.value, name, nil, 0, 0, XATTR_NOFOLLOW)
    guard size >= 0 else { throw Self.posixError(errno, at: path) }
    guard size > 0 else { return Data() }
    var value = Data(count: size)
    let read = value.withUnsafeMutableBytes {
      getxattr(path.value, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW)
    }
    guard read >= 0 else { throw Self.posixError(errno, at: path) }
    return value.prefix(read)
  }

  public func exists(_ path: AbsolutePath) async -> Bool {
    FileManager.default.fileExists(atPath: path.value)
  }

  public func volumeInfo(at path: AbsolutePath) async throws -> VolumeInfo {
    var status = stat()
    guard lstat(path.value, &status) == 0 else { throw Self.posixError(errno, at: path) }
    do {
      let values = try URL(fileURLWithPath: path.value).resourceValues(forKeys: [
        .volumeURLKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsInternalKey,
      ])
      return VolumeInfo(
        root: AbsolutePath(normalising: values.volume?.path ?? "/"),
        volumeID: UInt64(bitPattern: Int64(status.st_dev)),
        capacityBytes: UInt64(clamping: values.volumeTotalCapacity ?? 0),
        availableBytes: UInt64(clamping: values.volumeAvailableCapacity ?? 0),
        isInternal: values.volumeIsInternal ?? true)
    } catch {
      throw FileSystemError.ioFailure(path, description: error.localizedDescription)
    }
  }

  private static func date(from time: timespec) -> Date? {
    guard time.tv_sec != 0 || time.tv_nsec != 0 else { return nil }
    return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000)
  }
}

// MARK: - FileSystemMutating

extension DiskFileSystem: FileSystemMutating {
  public func moveToTrash(_ path: AbsolutePath) async throws -> AbsolutePath {
    guard FileManager.default.fileExists(atPath: path.value) else {
      throw FileSystemError.notFound(path)
    }
    var trashedURL: NSURL?
    do {
      try FileManager.default.trashItem(
        at: URL(fileURLWithPath: path.value), resultingItemURL: &trashedURL)
    } catch {
      throw Self.cocoaError(error, at: path)
    }
    guard let trashedPath = trashedURL?.path else {
      throw FileSystemError.ioFailure(path, description: "The trash did not report a destination.")
    }
    return AbsolutePath(normalising: trashedPath)
  }

  public func move(_ source: AbsolutePath, to destination: AbsolutePath) async throws {
    guard FileManager.default.fileExists(atPath: source.value) else {
      throw FileSystemError.notFound(source)
    }
    guard renamex_np(source.value, destination.value, UInt32(RENAME_EXCL)) != 0 else { return }
    switch errno {
    case EEXIST: throw FileSystemError.destinationOccupied(destination)
    case EXDEV: try moveAcrossVolumes(source, to: destination)
    default: throw Self.posixError(errno, at: source)
    }
  }

  private func moveAcrossVolumes(_ source: AbsolutePath, to destination: AbsolutePath) throws {
    guard !FileManager.default.fileExists(atPath: destination.value) else {
      throw FileSystemError.destinationOccupied(destination)
    }
    do {
      try FileManager.default.moveItem(atPath: source.value, toPath: destination.value)
    } catch {
      throw Self.cocoaError(error, at: source)
    }
  }

  /// Deleting descends, and it repairs traversal on the way.
  ///
  /// Removing a directory's children needs search and write permission on the
  /// directory holding them, so a payload the SafetyNet store contained by
  /// stripping its execute bits cannot be handed to `removeItem` as it stands:
  /// it fails with permission denied on a real volume. This adds owner search
  /// and write to each directory it must enter, removes each directory after
  /// its children, and clears every bit it added if it cannot finish, so an
  /// interrupted purge leaves the payload as contained as it found it.
  ///
  /// It changes no file's mode, ever, so nothing gains the ability to run that
  /// could not run before, and it adds nothing for group or other, so the
  /// opening reaches only this process, which owns the payload and could have
  /// granted itself the same thing directly.
  public func delete(_ path: AbsolutePath) async throws {
    guard FileManager.default.fileExists(atPath: path.value) else {
      throw FileSystemError.notFound(path)
    }
    var repaired: [(path: String, mode: mode_t)] = []
    do {
      try Self.removeDescending(path.value, repaired: &repaired)
    } catch {
      for opening in repaired.reversed() {
        _ = chmod(opening.path, opening.mode)
      }
      throw error
    }
  }

  /// One node: a file is unlinked, a directory is entered, emptied and
  /// removed. A directory this process cannot repair, because it neither owns
  /// it nor is root, fails the delete rather than partly emptying it.
  private static func removeDescending(
    _ path: String,
    repaired: inout [(path: String, mode: mode_t)]
  ) throws {
    var record = stat()
    guard lstat(path, &record) == 0 else {
      throw posixError(errno, at: AbsolutePath(normalising: path))
    }
    guard (record.st_mode & S_IFMT) == S_IFDIR else {
      guard unlink(path) == 0 else {
        throw posixError(errno, at: AbsolutePath(normalising: path))
      }
      return
    }
    let mode = record.st_mode & 0o7777
    if mode & 0o300 != 0o300 {
      guard chmod(path, mode | 0o300) == 0 else {
        throw posixError(errno, at: AbsolutePath(normalising: path))
      }
      repaired.append((path, mode))
    }
    for child in try contents(of: path) {
      try removeDescending(path + "/" + child, repaired: &repaired)
    }
    guard rmdir(path) == 0 else {
      throw posixError(errno, at: AbsolutePath(normalising: path))
    }
  }

  private static func contents(of path: String) throws -> [String] {
    guard let directory = opendir(path) else {
      throw posixError(errno, at: AbsolutePath(normalising: path))
    }
    defer { closedir(directory) }
    var names: [String] = []
    while let entry = readdir(directory) {
      let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
        String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
      }
      guard name != ".", name != ".." else { continue }
      names.append(name)
    }
    return names
  }

  public func createDirectory(at path: AbsolutePath) async throws {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: path.value, isDirectory: &isDirectory) {
      guard isDirectory.boolValue else { throw FileSystemError.destinationOccupied(path) }
      return
    }
    do {
      try FileManager.default.createDirectory(
        atPath: path.value, withIntermediateDirectories: true)
    } catch {
      throw Self.cocoaError(error, at: path)
    }
  }

  /// Writes a temporary file in the destination's own directory and renames it
  /// into place. The rename is where the atomicity comes from, so the
  /// temporary file must share the destination's volume.
  public func writeData(_ data: Data, to path: AbsolutePath) async throws {
    guard let parent = path.parent else { throw FileSystemError.destinationOccupied(path) }
    var parentIsDirectory: ObjCBool = false
    let parentExists = FileManager.default.fileExists(
      atPath: parent.value, isDirectory: &parentIsDirectory)
    guard parentExists, parentIsDirectory.boolValue else {
      throw FileSystemError.notFound(parent)
    }
    let temporary = parent.value + "/.\(path.lastComponent).macgleam-\(UUID().uuidString)"
    do {
      try data.write(to: URL(fileURLWithPath: temporary))
    } catch {
      throw Self.cocoaError(error, at: path)
    }
    guard rename(temporary, path.value) == 0 else {
      let failure = Self.posixError(errno, at: path)
      unlink(temporary)
      throw failure
    }
  }

  public func setPosixPermissions(_ mode: UInt16, at path: AbsolutePath) async throws {
    guard FileManager.default.fileExists(atPath: path.value) else {
      throw FileSystemError.notFound(path)
    }
    guard chmod(path.value, mode_t(mode)) == 0 else { throw Self.posixError(errno, at: path) }
  }

  public func setExtendedAttributes(
    _ attributes: [String: Data],
    at path: AbsolutePath
  ) async throws {
    let existing = try await extendedAttributes(at: path)
    for name in existing.keys where attributes[name] == nil {
      guard removexattr(path.value, name, XATTR_NOFOLLOW) == 0 else {
        throw Self.posixError(errno, at: path)
      }
    }
    for (name, value) in attributes {
      let status = value.withUnsafeBytes {
        setxattr(path.value, name, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW)
      }
      guard status == 0 else { throw Self.posixError(errno, at: path) }
    }
  }
}
