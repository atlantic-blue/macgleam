import Darwin
import Foundation
import GleamCore

/// The machine's own figures, sampled on a steady cadence off the main actor.
///
/// The storage figures come from the same volume reading the Disk Map uses, so
/// the two surfaces cannot show contradictory numbers for the same volume at
/// the same instant. Memory pressure comes from the kernel's own notion rather
/// than from a threshold invented here, which is what stops the app claiming a
/// fourth state the system does not have.
struct LiveSystemStats: SystemStatsProviding {
  /// Every four seconds. Fast enough that a menu bar figure is current when
  /// somebody glances at it, slow enough that watching it costs nothing.
  static let interval: Duration = .seconds(4)

  let fileSystem: DiskFileSystem
  let bootVolume: AbsolutePath

  init(
    fileSystem: DiskFileSystem = DiskFileSystem(),
    bootVolume: AbsolutePath = AbsolutePath(normalising: "/")
  ) {
    self.fileSystem = fileSystem
    self.bootVolume = bootVolume
  }

  func samples() -> AsyncStream<SystemStats> {
    AsyncStream { continuation in
      let work = Task.detached(priority: .utility) {
        while !Task.isCancelled {
          if let sample = await read() {
            continuation.yield(sample)
          }
          try? await Task.sleep(for: Self.interval)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in work.cancel() }
    }
  }

  /// One reading, or nothing. A volume that will not answer is not a reason
  /// to put a wrong number in the menu bar: the last good sample stays on
  /// screen until a new one arrives.
  private func read() async -> SystemStats? {
    guard let volume = try? await fileSystem.volumeInfo(at: bootVolume) else { return nil }
    return SystemStats(
      bootVolumeCapacityBytes: volume.capacityBytes,
      bootVolumeAvailableBytes: volume.availableBytes,
      memoryPressure: Self.memoryPressure(),
      memoryUsedBytes: Self.memoryUsedBytes(),
      processorLoadFraction: Self.processorLoadFraction(),
      sampledAt: Date())
  }

  /// The kernel's own pressure level, read through the sysctl the system sets
  /// itself. Anything else would be this app's opinion of what pressure is.
  private static func memoryPressure() -> SystemStats.MemoryPressure {
    var level: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
      return .normal
    }
    switch level {
    case 4: return .critical
    case 2: return .warning
    default: return .normal
    }
  }

  /// What is not free: everything the kernel counts as active, wired or
  /// compressed. Inactive pages are excluded, because they are memory the
  /// system will hand over the moment anything asks.
  private static func memoryUsedBytes() -> UInt64 {
    var statistics = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &statistics) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
        host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
      }
    }
    guard result == KERN_SUCCESS else { return 0 }
    var pageSize: vm_size_t = 0
    guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return 0 }
    let used =
      UInt64(statistics.active_count) + UInt64(statistics.wire_count)
      + UInt64(statistics.compressor_page_count)
    return used * UInt64(pageSize)
  }

  /// The share of processor time that is not idle, taken across all cores.
  private static func processorLoadFraction() -> Double {
    var load = host_cpu_load_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &load) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
      }
    }
    guard result == KERN_SUCCESS else { return 0 }
    let user = Double(load.cpu_ticks.0)
    let system = Double(load.cpu_ticks.1)
    let idle = Double(load.cpu_ticks.2)
    let nice = Double(load.cpu_ticks.3)
    let total = user + system + idle + nice
    guard total > 0 else { return 0 }
    return (user + system + nice) / total
  }
}
