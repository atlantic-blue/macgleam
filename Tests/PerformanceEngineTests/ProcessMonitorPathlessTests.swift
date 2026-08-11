import Foundation
import GleamCore
import PerformanceEngine
import Testing

/// C5 as amended, stated over the module rather than over a list of cases: "no
/// Performance finding names a path (C23), so every Performance category is
/// pathless". C23 puts the live process view outside the scan altogether: "the
/// live process view is not a scan, it is C25."
///
/// So this slice owes the rule twice over. The view emits no finding at all, and
/// a process sample carries no path for anything to expand into a removal. Both
/// are asserted here against the types rather than against a scan's output,
/// because the point of the pathless rule is that it holds for code nobody has
/// written yet: whatever a later screen does with a `ProcessSample`, there is no
/// file in it to delete. The monitor holds no file system at all, which is why
/// there is no test here for what it does to one: the initialiser takes a
/// listing, a signalling side and a cadence, and a disk is not among them.
@Suite("The live view carries no path")
struct ProcessMonitorPathlessTests {

  @Test("a process sample carries no path")
  func aProcessSampleCarriesNoPath() {
    let mirror = Mirror(reflecting: ProcessFixture.xcode)

    #expect(
      mirror.children.count == 5,
      "C25 fixes the five fields; a sixth that named a file would be a removal target")
    for child in mirror.children {
      #expect(
        child.value as? AbsolutePath == nil,
        "the field \(child.label ?? "unnamed") is a path, and a live view has no business with one"
      )
      #expect(child.value as? PathEntry == nil)
      #expect(child.label != "path")
    }
  }

  @Test("no field of a process sample is a byte size that anything could promise to reclaim")
  func theOnlyBytesAreAMeasurement() {
    let sample = ProcessFixture.xcode

    #expect(
      sample.memoryFootprintBytes == 8_589_934_592,
      "memory in use is a reading, and quitting a process frees memory rather than disk")
    let mirror = Mirror(reflecting: sample)
    let labels = mirror.children.compactMap(\.label).sorted()
    #expect(
      labels == [
        "bundleID", "memoryFootprintBytes", "name", "processIdentifier", "processorLoadFraction",
      ])
  }

  /// C23 draws the line: scanning produces findings a plan can act on, and the
  /// live view is not a scan. A monitor that also conformed to `GleamEngine`
  /// would be routed by everything that routes engines, including Full Sweep.
  @Test("the process monitor is not an engine, so nothing routes it into a plan")
  func theMonitorIsNotAnEngine() {
    let monitor = makeProcessMonitor(over: FakeMachine())

    #expect((monitor as Any) is any GleamEngine == false)
    #expect((monitor as Any) is any PlanExecuting == false)
  }

  @Test("every Performance finding emitted while the view is running carries no path entries")
  func performanceFindingsStayPathless() async throws {
    let machine = FakeMachine()
    _ = await collectSnapshots(
      from: makeProcessMonitor(over: machine, cadence: ScriptedCadence(ticks: 3)))

    let outcome = try await runPerformanceScan()

    #expect(outcome.findings.isEmpty == false)
    for finding in outcome.findings {
      #expect(
        finding.entries.isEmpty,
        "C5: a Performance finding names a task or a registration, never a file")
      #expect(finding.paths.isEmpty)
      #expect(
        finding.byteSize == 0,
        "zero here is exact: the Performance module reclaims nothing, so nothing is unknown")
    }
  }

  @Test("a Performance plan built while the view is running still removes nothing")
  func performancePlansStillRemoveNothing() async throws {
    let machine = FakeMachine()
    _ = await collectSnapshots(
      from: makeProcessMonitor(over: machine, cadence: ScriptedCadence(ticks: 1)))
    let outcome = try await runPerformanceScan()

    let plan = try PerformanceEngine().plan(
      selection: outcome.maintenanceFindings,
      context: makePlanContext(rules: try makeSignedPerformanceCatalog()))

    expectNoFileRemoval(in: plan)
    #expect(plan.totalBytes == 0)
  }
}
