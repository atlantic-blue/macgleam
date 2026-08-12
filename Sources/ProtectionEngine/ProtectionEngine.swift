import Foundation
import GleamCore
import os

/// Malware and adware detection: known malware binaries by signature, and the
/// adware launch items, browser extensions and unwanted application paths the
/// curated catalogue names.
///
/// Honest labelling throughout. This is malware and adware removal, not
/// antivirus: it finds what the published signatures and the curated list
/// describe, and it says what it did not look at rather than implying it
/// looked everywhere.
///
/// Everything it finds is quarantined, never deleted. That is the whole shape
/// of the plan, and it is a property of the builder rather than a branch
/// inside it: nothing here can construct a removal, so a detection cannot
/// become a silent deletion through a settings change, a forged finding or a
/// category added later.
public struct ProtectionEngine: GleamEngine {
  public var module: GleamModule { .protection }

  private let matcher: (any YaraScanning)?
  private let ruleSources: [YaraRuleSource]
  private let log = Logger(subsystem: "com.atlanticblue.macgleam", category: "protection")

  /// A build or a test without a matcher scans the curated adware list alone
  /// and says so, in the same shape as every other absence in this app: the
  /// work that can be done is done, and the work that cannot is named.
  public init(matcher: (any YaraScanning)? = nil, ruleSources: [YaraRuleSource] = []) {
    self.matcher = matcher
    self.ruleSources = ruleSources
  }

  public func scan(_ context: ScanContext) -> AsyncThrowingStream<ScanEvent, Error> {
    AsyncThrowingStream { continuation in
      let scanTask = Task {
        do {
          try await runScan(context) { continuation.yield($0) }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in scanTask.cancel() }
    }
  }

  public func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan {
    guard !selection.isEmpty else { throw PlanningError.emptySelection }
    for finding in selection where finding.sessionID != context.sessionID {
      throw PlanningError.findingFromDifferentSession(finding.id)
    }
    var builder = QuarantinePlanBuilder(context: context)
    for finding in selection {
      builder.add(finding)
    }
    return builder.build(sessionID: context.sessionID)
  }
}

// MARK: - Scanning

extension ProtectionEngine {
  fileprivate func runScan(
    _ context: ScanContext,
    yield: @Sendable (ScanEvent) -> Void
  ) async throws {
    yield(.phase(.indeterminate))
    let signatures = compiledSignatures(yield: yield)
    var detections = DetectionBatches(
      adwareRules: context.rules.adwareRules, sessionID: context.sessionID)
    var counters = ScanCounters.zero
    let options = EnumerationOptions(
      includesHiddenFiles: true, descendsIntoPackages: true, skipSubtrees: [])
    for try await event in context.fileSystem.enumerate(
      root: AbsolutePath(normalising: "/"), options: options)
    {
      try Task.checkCancellation()
      guard case .record(let record) = event, !record.isDirectory else { continue }
      counters.filesSeen += 1
      guard !context.rules.denylist.blocks(record.path) else { continue }
      detections.matchAdware(record)
      if let signatures {
        for identifier in try await matchedSignatures(record, against: signatures, context) {
          detections.matchMalware(record, signatureIdentifier: identifier)
        }
      }
    }
    yield(.phase(.determinate(estimatedTotalFiles: counters.filesSeen)))
    for finding in detections.findings() {
      counters.itemCount += finding.itemCount
      counters.bytesReclaimable += finding.byteSize
      yield(.finding(finding))
      yield(.progress(counters))
    }
    yield(.progress(counters))
    yield(.phase(.settling))
  }

  /// The rules that compiled, and a sentence for anything that did not.
  ///
  /// A rule that will not compile is disabled and logged, and the scan carries
  /// on with the rest: one bad line in a published catalogue must never be the
  /// difference between scanning for malware and not.
  private func compiledSignatures(yield: (ScanEvent) -> Void) -> [CompiledSignature]? {
    guard let matcher else {
      yield(
        .degraded(
          unavailable:
            "Known malware signatures were not checked, because this build has no signature "
            + "matcher. The curated adware list was still checked."))
      return nil
    }
    var compiled: [CompiledSignature] = []
    var failed: [String] = []
    for rule in ruleSources {
      do {
        compiled.append(
          CompiledSignature(
            identifier: rule.identifier,
            rules: try matcher.compile(rulesSource: rule.source)))
      } catch {
        failed.append(rule.identifier)
        log.warning("A signature rule did not compile and was disabled: \(rule.identifier).")
      }
    }
    if !failed.isEmpty {
      yield(
        .degraded(
          unavailable:
            "\(failed.count == 1 ? "One signature rule" : "\(failed.count) signature rules") "
            + "could not be read and were skipped. Everything else was checked."))
    }
    return compiled
  }

  /// The signatures a file matches. A file the matcher cannot read is not a
  /// detection and not a failure of the scan: it is one file it could not
  /// look inside, and the walk continues.
  private func matchedSignatures(
    _ record: FileRecord,
    against signatures: [CompiledSignature],
    _ context: ScanContext
  ) async throws -> [String] {
    guard let matcher, isCandidate(record) else { return [] }
    var identifiers: Set<String> = []
    for signature in signatures {
      let matches =
        (try? await matcher.match(
          file: record.path, against: signature.rules, fileSystem: context.fileSystem)) ?? []
      identifiers.formUnion(matches.map(\.ruleIdentifier))
    }
    // A signature names one thing, so a file that two compiled sets both
    // recognise is one detection rather than two rows saying the same.
    return identifiers.sorted()
  }

  /// What is worth reading with a signature: something the machine can run.
  ///
  /// The bound is stated rather than hidden. Matching every file on a disk
  /// against every rule would read the whole volume through the rule engine,
  /// and the things these signatures describe are executables, so a document
  /// nobody can run is not a candidate. A payload hidden inside a document and
  /// unpacked later is not found by this, which is the cost.
  private func isCandidate(_ record: FileRecord) -> Bool {
    record.isExecutable
  }

  fileprivate struct CompiledSignature {
    let identifier: String
    let rules: CompiledYaraRules
  }
}
