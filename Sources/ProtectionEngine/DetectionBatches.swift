import Foundation
import GleamCore

/// What one Protection scan has found, gathered as it walks and turned into
/// findings at the end.
///
/// A detection is grouped by what it is: one finding per signature, one per
/// adware rule. That is what lets a review say "this is the Genieo launch
/// agent" rather than listing forty paths under one heading, and it is why the
/// signature identifier lives in the category rather than in the sentence.
struct DetectionBatches {
  private let adwareRules: [AdwareRule]
  private let sessionID: UUID
  private var adwareEntries: [Int: [PathEntry]] = [:]
  private var malwareEntries: [String: [PathEntry]] = [:]

  init(adwareRules: [AdwareRule], sessionID: UUID) {
    self.adwareRules = adwareRules
    self.sessionID = sessionID
  }

  /// A file matches an adware rule when its path, or an ancestor of it,
  /// matches one of the rule's patterns, which is the same rule the cleanup
  /// catalogue matches with. A rule naming a directory therefore itemises the
  /// files beneath it and never the directory.
  mutating func matchAdware(_ record: FileRecord) {
    let components = record.path.components
    for (index, rule) in adwareRules.enumerated()
    where rule.pathPatterns.contains(where: { $0.matchesPathOrAncestor(of: components) }) {
      adwareEntries[index, default: []].append(
        PathEntry(path: record.path, allocatedBytes: record.allocatedBytes))
    }
  }

  mutating func matchMalware(_ record: FileRecord, signatureIdentifier: String) {
    malwareEntries[signatureIdentifier, default: []].append(
      PathEntry(path: record.path, allocatedBytes: record.allocatedBytes))
  }

  /// Malware first, then adware in catalogue order. Both are preselected:
  /// quarantine is reversible for thirty days, so the default is to contain
  /// what was found rather than to leave it running while somebody decides.
  func findings() -> [Finding] {
    malwareFindings() + adwareFindings()
  }

  private func malwareFindings() -> [Finding] {
    malwareEntries.keys.sorted().flatMap { identifier in
      batched(malwareEntries[identifier] ?? []).map { entries in
        Finding(
          id: UUID(),
          sessionID: sessionID,
          category: .malware(signatureIdentifier: identifier),
          entries: entries,
          risk: .dangerous,
          explanation:
            "This matches the known malware signature \(identifier). Removing it moves it into "
            + "MacGleam's SafetyNet, where it cannot run and can be put back for thirty days.",
          isPreselected: true)
      }
    }
  }

  private func adwareFindings() -> [Finding] {
    adwareRules.indices.flatMap { index -> [Finding] in
      let rule = adwareRules[index]
      return batched(adwareEntries[index] ?? []).map { entries in
        Finding(
          id: UUID(),
          sessionID: sessionID,
          category: Self.category(of: rule.kind),
          entries: entries,
          risk: .dangerous,
          explanation: rule.explanation.isEmpty ? Self.sentence(for: rule) : rule.explanation,
          isPreselected: true)
      }
    }
  }

  /// Batched at the entry cap, so one rule matching a thousand files is still
  /// a list somebody can read.
  private func batched(_ entries: [PathEntry]) -> [[PathEntry]] {
    guard !entries.isEmpty else { return [] }
    return stride(from: 0, to: entries.count, by: ScanStreamPolicy.maximumFindingEntries).map {
      start in
      Array(entries[start..<min(start + ScanStreamPolicy.maximumFindingEntries, entries.count)])
    }
  }

  private static func category(of kind: AdwareRule.Kind) -> FindingCategory {
    switch kind {
    case .launchAgent, .launchDaemon:
      return .adwareLaunchItem
    case .browserExtension:
      return .suspiciousBrowserExtension
    case .applicationPath:
      return .unwantedAppPath
    }
  }

  private static func sentence(for rule: AdwareRule) -> String {
    switch rule.kind {
    case .launchAgent, .launchDaemon:
      return
        "\(rule.identifier) starts itself every time this Mac does. Removing it moves it into "
        + "MacGleam's SafetyNet, where it cannot run and can be put back for thirty days."
    case .browserExtension:
      return
        "\(rule.identifier) is a browser extension on the curated unwanted list. Removing it "
        + "moves it into MacGleam's SafetyNet, where it can be put back for thirty days."
    case .applicationPath:
      return
        "\(rule.identifier) is on the curated unwanted list. Removing it moves it into "
        + "MacGleam's SafetyNet, where it can be put back for thirty days."
    }
  }
}
