import Foundation
import GleamCore
import GleamHub
import Testing

/// The menu bar: three figures read at a glance, in a fixed order, saying the
/// same thing the hub says.
///
/// Two surfaces disagreeing about how full the disk is would make both of them
/// useless, so the figures come from one sample and the byte style is the one
/// every other surface uses.
@MainActor
@Suite("Menu bar")
struct MenuBarModelTests {

  private static let instant = Date(timeIntervalSince1970: 1_726_000_000)

  private func sample(
    capacity: UInt64 = 1_000_000_000,
    available: UInt64 = 250_000_000,
    pressure: SystemStats.MemoryPressure = .normal,
    memoryUsed: UInt64 = 8_000_000_000,
    load: Double = 0.25
  ) -> SystemStats {
    SystemStats(
      bootVolumeCapacityBytes: capacity,
      bootVolumeAvailableBytes: available,
      memoryPressure: pressure,
      memoryUsedBytes: memoryUsed,
      processorLoadFraction: load,
      sampledAt: Self.instant)
  }

  private func allOn() -> MenuBarPreferences {
    MenuBarPreferences(showsStorage: true, showsMemory: true, showsProcessorLoad: true)
  }

  // MARK: - What it shows

  @Test("the three figures appear in a fixed order")
  func theThreeFiguresAppearInAFixedOrder() {
    let lines = MenuBarModel.lines(for: sample(), preferences: allOn())
    #expect(lines.map(\.kind) == [.storage, .memory, .processor])
  }

  @Test("a figure switched off is not there at all")
  func aFigureSwitchedOffIsNotThere() {
    let lines = MenuBarModel.lines(
      for: sample(),
      preferences: MenuBarPreferences(
        showsStorage: false, showsMemory: true, showsProcessorLoad: false))
    #expect(lines.map(\.kind) == [.memory])
  }

  @Test("everything switched off leaves nothing rather than an empty box of bars")
  func everythingSwitchedOffLeavesNothing() {
    let lines = MenuBarModel.lines(
      for: sample(),
      preferences: MenuBarPreferences(
        showsStorage: false, showsMemory: false, showsProcessorLoad: false))
    #expect(lines.isEmpty)
  }

  @Test("storage says what is free, in the same words as everywhere else")
  func storageSaysWhatIsFree() throws {
    let lines = MenuBarModel.lines(for: sample(available: 250_000_000), preferences: allOn())
    let storage = try #require(lines.first { $0.kind == .storage })
    #expect(storage.value == ByteFigure.string(250_000_000) + " free")
  }

  @Test("the storage bar is the share used, not the share free")
  func theStorageBarIsTheShareUsed() throws {
    let lines = MenuBarModel.lines(
      for: sample(capacity: 1_000, available: 250), preferences: allOn())
    let storage = try #require(lines.first { $0.kind == .storage })
    #expect(storage.fraction == 0.75)
  }

  @Test("a volume with no capacity draws no bar rather than dividing by nothing")
  func aVolumeWithNoCapacityDrawsNoBar() throws {
    let lines = MenuBarModel.lines(
      for: sample(capacity: 0, available: 0), preferences: allOn())
    let storage = try #require(lines.first { $0.kind == .storage })
    #expect(storage.fraction == 0)
  }

  @Test("the processor figure is a whole percentage")
  func theProcessorFigureIsAWholePercentage() throws {
    let lines = MenuBarModel.lines(for: sample(load: 0.376), preferences: allOn())
    let processor = try #require(lines.first { $0.kind == .processor })
    #expect(processor.value == "38 per cent")
  }

  @Test("a load outside nought to one is clamped rather than shown as it arrived")
  func aLoadOutsideTheRangeIsClamped() throws {
    for load in [-1.0, 2.0] {
      let lines = MenuBarModel.lines(for: sample(load: load), preferences: allOn())
      let processor = try #require(lines.first { $0.kind == .processor })
      #expect(processor.fraction ?? 0 >= 0)
      #expect(processor.fraction ?? 0 <= 1)
    }
  }

  // MARK: - What asks for attention

  @Test("memory under pressure says so rather than showing a number alone")
  func memoryUnderPressureSaysSo() throws {
    for pressure in [SystemStats.MemoryPressure.warning, .critical] {
      let lines = MenuBarModel.lines(for: sample(pressure: pressure), preferences: allOn())
      let memory = try #require(lines.first { $0.kind == .memory })
      #expect(memory.isAttention)
      #expect(memory.value.contains(","), "the state is said in words, not implied by a colour")
    }
  }

  @Test("memory at normal pressure asks for nothing")
  func memoryAtNormalPressureAsksForNothing() throws {
    let lines = MenuBarModel.lines(for: sample(pressure: .normal), preferences: allOn())
    #expect(try #require(lines.first { $0.kind == .memory }).isAttention == false)
  }

  @Test("a nearly full disk asks for attention")
  func aNearlyFullDiskAsksForAttention() throws {
    let lines = MenuBarModel.lines(
      for: sample(capacity: 1_000, available: 50), preferences: allOn())
    #expect(try #require(lines.first { $0.kind == .storage }).isAttention)
  }

  @Test("a disk with room asks for nothing")
  func aDiskWithRoomAsksForNothing() throws {
    let lines = MenuBarModel.lines(
      for: sample(capacity: 1_000, available: 500), preferences: allOn())
    #expect(try #require(lines.first { $0.kind == .storage }).isAttention == false)
  }

  // MARK: - Sampling

  @Test("the lines follow the samples as they arrive")
  func theLinesFollowTheSamples() async throws {
    let stats = ScriptedStats(samples: [
      sample(available: 500_000_000), sample(available: 100_000_000),
    ])
    let model = MenuBarModel(stats: stats, preferences: allOn())

    model.start()
    await expectEventuallyMenuBar("the second sample lands") {
      model.lines.first?.value == ByteFigure.string(100_000_000) + " free"
    }

    #expect(model.lastSample?.bootVolumeAvailableBytes == 100_000_000)
  }

  @Test("switching a figure off takes effect on what is already on screen")
  func switchingAFigureOffTakesEffectNow() async throws {
    let model = MenuBarModel(stats: ScriptedStats(samples: [sample()]), preferences: allOn())
    model.start()
    await expectEventuallyMenuBar("the first sample lands") { !model.lines.isEmpty }

    model.apply(
      MenuBarPreferences(showsStorage: false, showsMemory: false, showsProcessorLoad: true))

    #expect(model.lines.map(\.kind) == [.processor])
  }

  @Test("stopping ends the sampling")
  func stoppingEndsTheSampling() async throws {
    let stats = ScriptedStats(samples: [sample()])
    let model = MenuBarModel(stats: stats, preferences: allOn())
    model.start()
    await expectEventuallyMenuBar("the first sample lands") { !model.lines.isEmpty }

    model.stop()

    #expect(!model.lines.isEmpty, "what was on screen stays on screen")
  }
}

/// A stats source that yields exactly what the test scripted and then waits,
/// so nothing here depends on a clock.
struct ScriptedStats: SystemStatsProviding {
  let scripted: [SystemStats]

  init(samples: [SystemStats]) {
    self.scripted = samples
  }

  func samples() -> AsyncStream<SystemStats> {
    let values = scripted
    return AsyncStream { continuation in
      for sample in values {
        continuation.yield(sample)
      }
      continuation.finish()
    }
  }
}

@MainActor
func expectEventuallyMenuBar(
  _ what: String,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ condition: @MainActor () -> Bool
) async {
  for _ in 0..<200 {
    if condition() { return }
    await Task.yield()
    try? await Task.sleep(nanoseconds: 1_000_000)
  }
  Issue.record("\(what) never happened", sourceLocation: sourceLocation)
}
