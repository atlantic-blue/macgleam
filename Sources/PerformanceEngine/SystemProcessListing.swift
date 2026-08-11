import Darwin
import Foundation
import GleamCore

/// What this machine is running, read from the kernel and nothing else.
///
/// It is the reading side and it declares one method, so nothing holding it
/// can end a process. A process whose detail this app is not allowed to read
/// is left out of the snapshot rather than reported with invented numbers; a
/// process table the machine will not give up at all is a refused snapshot,
/// which the monitor skips.
///
/// It is an actor because the processor share of a process is a difference
/// between two readings, so the previous reading has to live somewhere. That
/// state is the only reason: nothing here is shared with the caller.
public actor SystemProcessListing: ProcessListing {
  private var previousProcessorNanoseconds: [Int32: UInt64] = [:]
  private var previousReadAt: DispatchTime?
  private var bundleIdentifiers: [String: String?] = [:]
  private let coreCount: Double

  public init() {
    coreCount = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
  }

  public func snapshot() async throws -> [ProcessSample] {
    let identifiers = try Self.runningProcessIdentifiers()
    let readAt = DispatchTime.now()
    let elapsed = elapsedNanoseconds(to: readAt)
    var samples: [ProcessSample] = []
    var processorNanoseconds: [Int32: UInt64] = [:]
    for identifier in identifiers {
      guard let reading = read(identifier) else { continue }
      processorNanoseconds[identifier] = reading.processorNanoseconds
      samples.append(sample(identifier, reading, over: elapsed))
    }
    previousProcessorNanoseconds = processorNanoseconds
    previousReadAt = readAt
    return samples
  }

  // MARK: - One row

  private func sample(
    _ identifier: Int32,
    _ reading: Reading,
    over elapsed: UInt64
  ) -> ProcessSample {
    ProcessSample(
      processIdentifier: identifier,
      name: reading.name,
      bundleID: reading.bundleID,
      memoryFootprintBytes: reading.memoryFootprintBytes,
      processorLoadFraction: processorLoad(identifier, reading, over: elapsed)
    )
  }

  /// The share of the machine a process took since the previous reading. A
  /// process seen for the first time reports nothing rather than its whole
  /// lifetime average, which would put a long lived process at the top of a
  /// live view for work it did yesterday.
  private func processorLoad(
    _ identifier: Int32,
    _ reading: Reading,
    over elapsed: UInt64
  ) -> Double {
    guard elapsed > 0, let previous = previousProcessorNanoseconds[identifier] else { return 0 }
    guard reading.processorNanoseconds > previous else { return 0 }
    let used = Double(reading.processorNanoseconds - previous)
    let fraction = used / (Double(elapsed) * coreCount)
    return min(max(fraction, 0), 1)
  }

  private func elapsedNanoseconds(to readAt: DispatchTime) -> UInt64 {
    guard let previousReadAt, readAt.uptimeNanoseconds > previousReadAt.uptimeNanoseconds else {
      return 0
    }
    return readAt.uptimeNanoseconds - previousReadAt.uptimeNanoseconds
  }

  // MARK: - The machine

  /// Every process identifier the kernel will list. A machine running nothing
  /// answers an empty list, which is a snapshot; a machine that refuses to
  /// answer is a refusal, which is not.
  private static func runningProcessIdentifiers() throws -> [Int32] {
    let expected = proc_listallpids(nil, 0)
    guard expected >= 0 else { throw ProcessMachineFailure.processTableUnreadable }
    guard expected > 0 else { return [] }
    var identifiers = [Int32](repeating: 0, count: Int(expected) + 64)
    let counted = identifiers.withUnsafeMutableBufferPointer { buffer in
      proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<Int32>.stride))
    }
    guard counted >= 0 else { throw ProcessMachineFailure.processTableUnreadable }
    return identifiers.prefix(Int(counted)).filter { $0 > 0 }
  }

  /// What one process will tell this app about itself. Nothing is guessed: a
  /// process whose task detail is refused is left out of the snapshot.
  private func read(_ identifier: Int32) -> Reading? {
    guard let name = try? LiveProcessName.of(identifier) else { return nil }
    guard let task = Self.taskInfo(identifier) else { return nil }
    let footprint = Self.memoryFootprintBytes(identifier)
    return Reading(
      name: name,
      bundleID: bundleIdentifier(identifier),
      memoryFootprintBytes: footprint ?? UInt64(task.pti_resident_size),
      processorNanoseconds: UInt64(task.pti_total_user) + UInt64(task.pti_total_system)
    )
  }

  private static func taskInfo(_ identifier: Int32) -> proc_taskinfo? {
    var info = proc_taskinfo()
    let size = Int32(MemoryLayout<proc_taskinfo>.size)
    let written = proc_pidinfo(identifier, PROC_PIDTASKINFO, 0, &info, size)
    guard written == size else { return nil }
    return info
  }

  /// The footprint Activity Monitor calls memory, when the machine will give
  /// it up. The resident size stands in when it will not, which is a smaller
  /// number rather than an invented one.
  private static func memoryFootprintBytes(_ identifier: Int32) -> UInt64? {
    var usage = rusage_info_v4()
    let outcome = withUnsafeMutablePointer(to: &usage) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
        proc_pid_rusage(identifier, RUSAGE_INFO_V4, rebound)
      }
    }
    guard outcome == 0 else { return nil }
    return usage.ri_phys_footprint
  }

  /// The bundle identifier of the application a process belongs to, for the
  /// processes that belong to one. Read from the bundle on disk rather than
  /// from any window server, so a background process is treated the same as a
  /// foreground one.
  private func bundleIdentifier(_ identifier: Int32) -> String? {
    guard let executable = LiveProcessName.executablePath(identifier) else { return nil }
    if let remembered = bundleIdentifiers[executable] { return remembered }
    let read = Self.bundleIdentifier(forExecutableAt: executable)
    bundleIdentifiers[executable] = read
    return read
  }

  /// The identifier in the enclosing bundle's information property list. Read
  /// once per executable: the answer cannot change while the process lives,
  /// and a live view reads the same executables every tick.
  private static func bundleIdentifier(forExecutableAt executable: String) -> String? {
    var directory = (executable as NSString).deletingLastPathComponent
    while !directory.isEmpty, directory != "/" {
      if (directory as NSString).pathExtension == "app" {
        return Bundle(path: directory)?.bundleIdentifier
      }
      directory = (directory as NSString).deletingLastPathComponent
    }
    return nil
  }

  /// One process's answer, before it becomes a sample.
  private struct Reading {
    let name: String
    let bundleID: String?
    let memoryFootprintBytes: UInt64
    let processorNanoseconds: UInt64
  }
}
