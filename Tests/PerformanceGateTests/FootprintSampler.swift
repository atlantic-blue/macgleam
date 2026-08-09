import Darwin
import Foundation

/// The physical footprint of this process in bytes, straight from the
/// kernel's task ledger through `task_info` with `TASK_VM_INFO`. This is the
/// figure Activity Monitor reports as memory, and the one the 500 megabyte
/// design ceiling is written against.
func currentPhysicalFootprintBytes() -> UInt64 {
  var info = task_vm_info_data_t()
  var count = mach_msg_type_number_t(
    MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
  )
  let kernelResult = withUnsafeMutablePointer(to: &info) { pointer in
    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
      task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
    }
  }
  guard kernelResult == KERN_SUCCESS, info.phys_footprint >= 0 else {
    return 0
  }
  return UInt64(info.phys_footprint)
}

/// One sampled measurement: where the process started, where it peaked.
struct FootprintMeasurement: Sendable {
  let baselineBytes: UInt64
  let peakBytes: UInt64

  var growthBytes: UInt64 { peakBytes >= baselineBytes ? peakBytes - baselineBytes : 0 }

  static func megabytes(_ bytes: UInt64) -> Double {
    Double(bytes) / (1024 * 1024)
  }
}

/// Samples the process footprint on a fixed interval and keeps the peak.
/// Sampling brackets the measured work: one sample the moment it starts, one
/// every interval while it runs, and a final sample on stop, so a spike that
/// lands between the first and last sample is still caught.
actor FootprintSampler {

  private var baselineBytes: UInt64 = 0
  private var peakBytes: UInt64 = 0
  private var samplingTask: Task<Void, Never>?

  func start(every interval: Duration) {
    guard samplingTask == nil else { return }
    baselineBytes = currentPhysicalFootprintBytes()
    peakBytes = baselineBytes
    samplingTask = Task {
      while !Task.isCancelled {
        self.sampleOnce()
        try? await Task.sleep(for: interval)
      }
    }
  }

  func stop() -> FootprintMeasurement {
    samplingTask?.cancel()
    samplingTask = nil
    recordSample()
    return FootprintMeasurement(baselineBytes: baselineBytes, peakBytes: peakBytes)
  }

  private func sampleOnce() {
    recordSample()
  }

  private func recordSample() {
    peakBytes = max(peakBytes, currentPhysicalFootprintBytes())
  }
}
