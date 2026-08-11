import Foundation
import GleamCore

/// A tick now and then one every interval, for as long as somebody is
/// watching.
///
/// The first tick is immediate, so a live view has rows the moment it opens
/// rather than an interval of nothing. Letting go of the tick stream ends the
/// ticking, which is how a closed view stops the sampling behind it.
public struct SteadyProcessSampleCadence: ProcessSampleCadence {
  private let interval: Duration

  public init(interval: Duration = .seconds(2)) {
    self.interval = interval
  }

  public func ticks() -> AsyncStream<Void> {
    let interval = self.interval
    return AsyncStream { continuation in
      let ticking = Task.detached(priority: .userInitiated) {
        continuation.yield(())
        while !Task.isCancelled {
          do {
            try await Task.sleep(for: interval)
          } catch {
            break
          }
          guard case .enqueued = continuation.yield(()) else { break }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in ticking.cancel() }
    }
  }
}
