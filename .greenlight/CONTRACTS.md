# Contracts: MacGleam

Typed contracts derived from DESIGN.md, agreed 2026-08-09. These are the source
of truth for test writers and implementers. Test writers work from this file
without seeing implementations; implementers make the tests green without
modifying them.

How to read this file:

- Every contract is a boundary where two things talk. Internal helpers are not
  contracts.
- Doc comments are binding. They carry the behavioural guarantees, error cases
  and concurrency expectations that tests assert.
- All code is Swift 6 with strict concurrency. Every crossing type is Sendable.
  Types that cross the process boundary to GleamHelper are additionally Codable
  and Equatable.
- Contracts are numbered C1 to C35. GRAPH.md maps contracts to slices and
  carries each slice's verification tier.
- Nothing here says how. Enumeration strategy, hashing algorithm choice, shader
  code and storage engines are implementation, except where DESIGN.md locked a
  decision that is observable in behaviour (for example file id deduplication).

Package layout, restated from DESIGN.md: GleamDesign (C1, C2), GleamCore
(C3 to C19), engine packages (C20 to C29), GleamHelperCore (C30, C31), app
services (C32 to C35).

---

## GleamDesign

### C1. Design tokens

```swift
import SwiftUI

/// The complete visual token set. Every colour, size, radius and elevation in
/// the app resolves through these types. There is no other source of visual
/// constants.
///
/// Guarantees:
/// - Colour tokens resolve for both dark and light appearances from day one.
/// - Semantic colours (safe, review, dangerous) meet Web Content Accessibility
///   Guidelines AA contrast against the surfaces they appear on, in both
///   appearances. This is a testable threshold, not an aspiration.
/// - Spacing is an 8 point grid. `GleamSpacing.points(n)` returns exactly
///   `n * 8`. No view uses a padding or offset that is not a grid multiple.
/// - Exactly two corner radii and three elevation levels exist.
/// - The type scale has exactly five roles: one display size for the hub
///   number, three text sizes, one mono size for file paths. SF Pro only.
public enum GleamColorToken: CaseIterable, Sendable {
    case baseBackground      // deep neutral, near black blue
    case surface             // card surface
    case accent              // iridescent accent drawn from the orb motif
    case textPrimary
    case textSecondary
    case safe
    case review
    case dangerous

    /// Resolved colour for the given appearance.
    public func color(for appearance: ColorScheme) -> Color { fatalError("contract") }
}

public enum GleamSpacing: Sendable {
    /// The grid unit. Always 8.
    public static let unit: CGFloat = 8
    /// Returns count multiplied by the grid unit. Traps on negative counts.
    public static func points(_ count: Int) -> CGFloat { fatalError("contract") }
}

public enum GleamRadius: CaseIterable, Sendable {
    case card
    case control
    public var value: CGFloat { fatalError("contract") }
}

public enum GleamElevation: CaseIterable, Sendable {
    case low, medium, high
    // Each level is a material plus shadow token pair, resolved in SwiftUI.
}

public enum GleamTypeToken: CaseIterable, Sendable {
    case display     // the hub number
    case title
    case body
    case caption
    case mono        // file paths
    public var font: Font { fatalError("contract") }
}
```

### C2. Motion tokens

```swift
import SwiftUI

/// The canonical motion set. DESIGN.md is explicit: no animation outside this
/// token set. A new curve is a design decision recorded in DECISIONS.md, not a
/// local choice.
///
/// Guarantees:
/// - Exactly three springs and two fade durations exist.
/// - The numeric values are locked: snappy (response 0.30, damping 0.85),
///   gentle (response 0.55, damping 0.90), lively (response 0.40,
///   damping 0.70), micro fade 150 milliseconds, standard fade 250
///   milliseconds. A test asserts these exact values so a drive by tweak
///   fails loudly.
/// - Usage roles are part of the contract: snappy for navigation, selection
///   and toggles; gentle for layout settles and list reflow; lively for
///   celebration moments only.
/// - Reduce Motion mapping: every spring resolves to a crossfade of the
///   standard fade duration when the system Reduce Motion setting is on.
///   `animation(reduceMotion: true)` never returns a spring.
public enum GleamSpring: CaseIterable, Sendable {
    case snappy
    case gentle
    case lively

    public var response: Double { fatalError("contract") }
    public var dampingFraction: Double { fatalError("contract") }

    /// The SwiftUI animation for this token, honouring Reduce Motion.
    public func animation(reduceMotion: Bool) -> Animation { fatalError("contract") }
}

public enum GleamFade: CaseIterable, Sendable {
    case micro       // 150 milliseconds
    case standard    // 250 milliseconds
    public var duration: Duration { fatalError("contract") }
}
```

---

## GleamCore: shared value types

### C3. AbsolutePath

```swift
/// A normalised absolute file system path. The only path representation that
/// crosses any boundary in MacGleam, including the XPC boundary to the helper.
///
/// Guarantees:
/// - Always begins with "/". Never contains "." or ".." components. Never
///   contains a trailing slash except for the root itself.
/// - Construction from a non conforming string returns nil rather than
///   normalising silently across the XPC boundary; inside the app,
///   `normalising:` construction is available and total.
/// - Value semantics, Hashable, Comparable (lexicographic), Codable as a
///   plain string.
/// - `isDescendant(of:)` is a pure prefix check on components, not on
///   characters, so "/Library/App" is not a descendant of "/Library/Ap".
public struct AbsolutePath: Codable, Sendable, Hashable, Comparable {
    public let value: String
    public init?(validating value: String)
    public init(normalising value: String)
    public func isDescendant(of ancestor: AbsolutePath) -> Bool
    public var lastComponent: String { get }
}
```

### C4. ScanSession, ScanCounters, ScanPhase

```swift
/// One scan run of one module. The unit the status scene and progress
/// choreography observe.
///
/// Guarantees:
/// - `finishedAt` is nil exactly while `state` is `.running`, and set in the
///   same mutation that moves state to completed, cancelled or failed.
/// - Counters are monotonic within a session: filesSeen, bytesReclaimable and
///   findingCount never decrease. The motion design (counters only count up)
///   depends on this at the model layer, not on view smoothing alone.
/// - A cancelled or failed scan session never has side effects on disk.
///   Scanning is read only everywhere in MacGleam (see C13, C15).
/// - `failed` carries a plain sentence for the user, never a code.
public struct ScanSession: Identifiable, Codable, Sendable, Equatable {
    public enum State: Codable, Sendable, Equatable {
        case running
        case completed
        case cancelled
        case failed(reason: String)
    }
    public let id: UUID
    public let module: GleamModule
    public let startedAt: Date
    public var finishedAt: Date?
    public var state: State
    public var counters: ScanCounters
}

public struct ScanCounters: Codable, Sendable, Equatable {
    public var filesSeen: UInt64
    public var bytesReclaimable: UInt64
    public var findingCount: UInt32
    public static let zero: ScanCounters
}

/// Drives the three phase scan choreography from DESIGN.md.
/// Phases only ever advance: indeterminate, then determinate, then settling.
/// An engine may skip determinate on very fast scans, never go backwards.
public enum ScanPhase: Codable, Sendable, Equatable {
    case indeterminate
    case determinate(estimatedTotalFiles: UInt64)
    case settling
}

public enum GleamModule: String, Codable, Sendable, CaseIterable {
    case smartCare, cleanup, protection, performance, applications, clutter, spaceLens
}
```

### C5. Finding

```swift
/// The unit of user review. Everything a user can select, inspect and act on
/// is a Finding.
///
/// Guarantees:
/// - `paths` is never empty. Every path is inspectable in the UI down to the
///   full path string (mono type token).
/// - `byteSize` is the allocated (on disk) byte total across `paths`, because
///   it feeds the reclaimable estimate. See GRAPH.md open questions.
/// - `explanation` is a plain sentence saying what this is and why it is
///   safe, reviewable or dangerous. Never empty.
/// - Preselection rules by module are binding:
///   Cleanup, Clutter and Space Lens findings may be preselected only when
///   risk is `.safe`. Protection malware and adware findings are preselected
///   (quarantine is reversible). Privacy cleanup findings are never
///   preselected. Leftover sweep findings are never preselected.
/// - For `duplicateSet` and `similarPhotoSet`, `keptPath` is a member of
///   `paths` and `paths.count >= 2`. The kept copy is shown before anything
///   moves and no plan ever targets it (see C21).
public struct Finding: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let sessionID: UUID
    public let category: FindingCategory
    public let paths: [AbsolutePath]
    public let byteSize: UInt64
    public let risk: RiskLevel
    public let explanation: String
    public let isPreselected: Bool
}

public enum RiskLevel: String, Codable, Sendable, Equatable {
    case safe, review, dangerous
}

public enum FindingCategory: Codable, Sendable, Equatable, Hashable {
    // Cleanup
    case userCache, applicationCache, log, brokenDownload
    case xcodeDerivedData, simulatorCache, browserCache, temporaryFile
    case mailAttachmentLocalCopy
    case trashBin(volume: AbsolutePath)
    // Clutter
    case largeFile, oldFile, downloadsTriage
    case duplicateSet(keptPath: AbsolutePath)
    case similarPhotoSet(keptPath: AbsolutePath)
    // Protection
    case malware(signatureIdentifier: String)
    case adwareLaunchItem, suspiciousBrowserExtension, unwantedAppPath
    // Privacy
    case browserHistory(browser: String)
    case browserCookies(browser: String)
    case browserSiteData(browser: String)
    case recentItemsList
    case wifiNetworkHistory
    // Applications
    case applicationBundle(bundleID: String)
    case applicationLeftover(bundleID: String)
    case orphanedLeftover
    // Space Lens
    case spaceLensSelection
}
```

### C6. OperationPlan

```swift
/// An ordered, executable description of destructive work, derived from the
/// user's reviewed selection. The only input the executor accepts.
///
/// Guarantees:
/// - `operations` preserves order and executes in order (C17).
/// - `totalBytes` equals the sum of the byte sizes of all operations that
///   reclaim space.
/// - A plan containing any `deletePermanently` operation must carry a
///   `permanentDeletionConfirmation` whose fileCount and byteTotal exactly
///   match the permanent operations in the plan. The executor refuses the
///   plan otherwise (C17). This types the DESIGN.md rule that permanent
///   delete is gated by an explicit confirmation naming counts.
/// - Plans are immutable once built. Deselecting in the UI builds a new plan.
/// - No operation in a plan targets a path the denylist blocks. Engines
///   filter at plan time and the executor and helper re check at run time,
///   three independent enforcement points.
public struct OperationPlan: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let sessionID: UUID
    public let operations: [Operation]
    public let totalBytes: UInt64
    public let permanentDeletionConfirmation: PermanentDeletionConfirmation?
}

/// Evidence that the user saw and confirmed the exact scope of a permanent
/// deletion. Constructed by the UI at confirmation time, validated by the
/// executor.
public struct PermanentDeletionConfirmation: Codable, Sendable, Equatable {
    public let fileCount: UInt32
    public let byteTotal: UInt64
    public let confirmedAt: Date
}
```

### C7. Operation, OperationResult, ExecutionReport, MaintenanceTask

```swift
/// One atomic action. The unit of atomicity for the whole safety story: an
/// operation either fully completes or leaves its target untouched.
///
/// Guarantees:
/// - `kind` is a closed set. There is no generic "run this" operation
///   anywhere in MacGleam, including the helper.
/// - `privilege` is decided by the path ownership policy (C16) at plan time
///   and re decided by the helper at execution time. The two must agree or
///   the helper refuses (C31).
/// - Every operation carries the finding it came from, so the result screen
///   can say exactly which reviewed item succeeded, failed or was skipped.
public struct Operation: Identifiable, Codable, Sendable, Equatable {
    public enum Kind: Codable, Sendable, Equatable {
        case moveToTrash(target: AbsolutePath)
        case deletePermanently(target: AbsolutePath)
        /// Move into the SafetyNet store, source malware quarantine.
        case quarantine(target: AbsolutePath)
        /// Move into the SafetyNet store, source uninstall archive,
        /// grouped so an uninstall restores as one unit.
        case archive(target: AbsolutePath, groupID: UUID)
        case setLaunchItemEnabled(item: LaunchItemID, enabled: Bool)
        case runMaintenance(task: MaintenanceTask)
    }
    public enum Privilege: String, Codable, Sendable, Equatable {
        case user, root
    }
    public let id: UUID
    public let findingID: UUID
    public let kind: Kind
    public let privilege: Privilege
}

/// The outcome of one operation.
///
/// Guarantees:
/// - `skippedDenylisted` is a success of the safety system, not a failure of
///   the run. It is reported distinctly so the result screen can say why the
///   item stayed.
/// - `failed` reasons are plain sentences: what failed, what was and was not
///   done.
public enum OperationResult: Codable, Sendable, Equatable {
    case completed(bytesReclaimed: UInt64)
    case failed(reason: String)
    case skippedDenylisted
    case notStarted
}

/// The complete, ordered account of a plan run. The result screen renders
/// this and nothing else.
///
/// Guarantees:
/// - Contains exactly one entry per operation in the plan, in plan order,
///   whatever happened, including cancellation (untouched operations report
///   `notStarted`). "The result screen says exactly which is which" is this
///   type.
public struct ExecutionReport: Codable, Sendable, Equatable {
    public let planID: UUID
    public let results: [(operationID: UUID, result: OperationResult)]
    public let bytesReclaimed: UInt64
    public let startedAt: Date
    public let finishedAt: Date
}

/// The closed set of maintenance tasks. Non destructive by design.
///
/// Guarantees:
/// - `clearsUserVisibleData` is true for any task whose effect a user can
///   notice as lost data (the Domain Name System cache flush). The UI must
///   say so before running such a task.
/// - Tasks are idempotent: running one twice is safe and equivalent to once.
public enum MaintenanceTask: String, Codable, Sendable, CaseIterable, Equatable {
    case flushDomainNameSystemCache
    case rebuildLaunchServicesDatabase
    case triggerSpotlightReindex
    case purgeMemoryPressure
    case runPeriodicMaintenance
    public var clearsUserVisibleData: Bool { fatalError("contract") }
}
```

### C8. SafetyNetItem

```swift
/// One quarantined or archived file in the SafetyNet store.
///
/// Guarantees:
/// - `expiresAt` is exactly 30 days after `storedAt`. Expiry marks purge
///   eligibility only; nothing is ever purged without explicit confirmation
///   (C18).
/// - `metadata` snapshots everything restore fidelity needs: permission
///   mode, extended attributes, creation and modification dates, owning
///   account name where resolvable.
/// - `groupID` links the items of one uninstall so they restore as one unit.
/// - `isRestored` items remain listed (history), are excluded from restore,
///   and their stored payload has been moved back, not copied.
public struct SafetyNetItem: Identifiable, Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable, Equatable {
        case malwareQuarantine
        case uninstallArchive
    }
    public let id: UUID
    public let originPath: AbsolutePath
    public let storedPath: AbsolutePath
    public let source: Source
    public let groupID: UUID?
    public let metadata: FileMetadataSnapshot
    public let storedAt: Date
    public let expiresAt: Date
    public var isRestored: Bool
}

public struct FileMetadataSnapshot: Codable, Sendable, Equatable {
    public let posixPermissions: UInt16
    public let ownerAccountName: String?
    public let extendedAttributes: [String: Data]
    public let created: Date?
    public let modified: Date?
}
```

### C9. AppInventoryEntry

```swift
/// One installed application and everything MacGleam knows belongs to it.
///
/// Guarantees:
/// - `leftoverPaths` is itemised by kind so the uninstall review can group
///   preferences, caches, containers, application support and launch agents.
/// - Discovery never includes a path outside the recognised leftover
///   locations for the bundle identifier; a false association here becomes a
///   deleted stranger's file, so the association rule is conservative and
///   its tests are adversarial (shared containers, bundle identifier
///   prefixes that collide).
public struct AppInventoryEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public let version: String
    public let installLocation: AbsolutePath
    public let leftoverPaths: [LeftoverPath]
}

public struct LeftoverPath: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case preferences, cache, container, applicationSupport, launchAgent, launchDaemon, log
    }
    public let path: AbsolutePath
    public let kind: Kind
    public let byteSize: UInt64
}
```

### C10. RuleCatalog and Denylist

```swift
/// The versioned, signed knowledge base: safe to clean paths, adware
/// signatures and the denylist.
///
/// Guarantees:
/// - `version` is strictly monotonic across updates (C19).
/// - `signature` is an Ed25519 signature over the canonical encoding of the
///   catalogue content. A catalogue that fails verification is never
///   adopted and never partially read into rules.
/// - Denylist supremacy: `Denylist.blocks(_:)` is consulted by engines at
///   plan time, by the executor before every operation, and by the helper
///   before every privileged operation. A path it blocks is unremovable
///   whatever any rule, selection or helper request says.
/// - The effective denylist in any process is the union of the embedded
///   baseline denylist and the currently adopted catalogue's denylist. An
///   update can extend the denylist and can never shrink it below the
///   baseline. This is how a bad rules update cannot cross it.
/// - `blocks(_:)` is pure, total and fast enough to sit on the per
///   operation hot path. It blocks a path when the path matches a pattern
///   or is a descendant of a blocked directory.
public struct RuleCatalog: Codable, Sendable, Equatable {
    public let version: RuleCatalogVersion
    public let signature: Data
    public let cleanupRules: [CleanupRule]
    public let adwareRules: [AdwareRule]
    public let denylist: Denylist
}

public struct RuleCatalogVersion: Codable, Sendable, Equatable, Comparable {
    public let value: UInt32
}

public struct CleanupRule: Codable, Sendable, Equatable {
    public let identifier: String
    public let category: FindingCategory
    public let pathPatterns: [PathPattern]
    public let risk: RiskLevel
    public let preselectable: Bool     // only honoured when risk is safe
    public let explanation: String
}

public struct AdwareRule: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case launchAgent, launchDaemon, browserExtension, applicationPath
    }
    public let identifier: String
    public let kind: Kind
    public let pathPatterns: [PathPattern]
    public let explanation: String
}

public struct Denylist: Codable, Sendable, Equatable {
    public let patterns: [PathPattern]
    public func blocks(_ path: AbsolutePath) -> Bool { fatalError("contract") }
}

/// A restricted glob over absolute paths. Supports literal components, a
/// single component wildcard and a trailing subtree wildcard. Deliberately
/// not a regular expression: patterns are reviewable by a human.
public struct PathPattern: Codable, Sendable, Equatable {
    public let pattern: String
    public func matches(_ path: AbsolutePath) -> Bool { fatalError("contract") }
}
```

### C11. LicenceState

```swift
/// Where this install stands with trial and licence.
///
/// Guarantees:
/// - Trial is 14 days from first launch, full featured. No feature gates
///   exist during trial anywhere in the app.
/// - Licence validation is offline: a signed licence file verified against
///   a public key embedded in the app. No network call is needed to reach
///   `.licensed`.
/// - `invalid` carries a plain sentence, and an invalid licence file never
///   crashes or blocks the app from reporting its state.
public enum LicenceState: Codable, Sendable, Equatable {
    case trial(startedAt: Date, endsAt: Date)
    case trialExpired(endedAt: Date)
    case licensed(SignedLicence)
    case invalid(reason: String)
}

public struct SignedLicence: Codable, Sendable, Equatable {
    public let licenceKey: String
    public let issuedAt: Date
    /// The highest major version this licence unlocks. Paid major upgrades
    /// issue a new licence.
    public let majorVersionCeiling: UInt16
    public let signature: Data      // Ed25519 over the canonical fields
}
```

### C12. Settings

```swift
/// User preferences. One store, loaded once, validated on load.
///
/// Guarantees:
/// - `deletionMode` defaults to `.trash`. Switching to `.permanent` is an
///   explicit opt in and every permanent run still confirms with counts
///   (C6).
/// - Invalid persisted settings load as defaults with a logged warning,
///   never a crash and never a silent permanent deletion mode.
/// - Thresholds are user tunable per DESIGN.md (large and old files).
/// - Scan schedules are deliberately absent: DESIGN.md lists them in the
///   data model but defers scheduled background scanning. See GRAPH.md open
///   questions.
public struct Settings: Codable, Sendable, Equatable {
    public enum DeletionMode: String, Codable, Sendable, Equatable {
        case trash, permanent
    }
    public var deletionMode: DeletionMode
    public var largeFileThresholdBytes: UInt64
    public var oldFileThresholdDays: UInt32
    public var menuBar: MenuBarPreferences
    public var motion: MotionPreferences
    public static let defaults: Settings
}

public struct MenuBarPreferences: Codable, Sendable, Equatable {
    public var showsStorage: Bool
    public var showsMemory: Bool
    public var showsProcessorLoad: Bool
}

/// Motion follows the system Reduce Motion setting. `reduceMotionOverride`
/// lets a user force reduced motion on while the system setting is off;
/// nothing can force full motion on when the system asks for reduced.
public struct MotionPreferences: Codable, Sendable, Equatable {
    public var reduceMotionOverride: Bool?
}
```

---

## GleamCore: boundaries

### C13. FileSystemReading

```swift
/// The read side of the file system. The only view of the disk any engine
/// ever gets, which is what makes every engine testable against an in memory
/// implementation.
///
/// Guarantees:
/// - Reading only. No method in this protocol mutates anything, and engines
///   receive `any FileSystemReading`, never the mutating side (C14), so
///   "engines never delete" is a compile time property.
/// - `enumerate` streams records as discovered so results can stream and
///   aggregate; callers never need the full listing in memory (the 500
///   megabyte scan ceiling depends on this).
/// - Deduplication: `enumerate` never yields the same (volumeID, fileID)
///   pair twice, even when the underlying platform repeats entries (the
///   macOS Sequoia getattrlistbulk regression). This carries a dedicated
///   regression test with a repeating fake.
/// - Cancellation: cancelling the consuming task ends the stream promptly
///   and touches nothing.
/// - Errors: a directory that cannot be read (permissions) is skipped and
///   reported through `EnumerationEvent.inaccessible`, not thrown, so one
///   locked folder never sinks a scan. Only volume level failures throw.
/// - Order is not guaranteed and tests must not depend on it.
public protocol FileSystemReading: Sendable {
    func enumerate(
        root: AbsolutePath,
        options: EnumerationOptions
    ) -> AsyncThrowingStream<EnumerationEvent, Error>

    func metadata(at path: AbsolutePath) async throws -> FileRecord
    /// Reads at most maxBytes. Used by hashing and YARA scanning.
    func readData(at path: AbsolutePath, maxBytes: UInt64) async throws -> Data
    func extendedAttributes(at path: AbsolutePath) async throws -> [String: Data]
    func exists(_ path: AbsolutePath) async -> Bool
    func volumeInfo(at path: AbsolutePath) async throws -> VolumeInfo
}

public enum EnumerationEvent: Sendable, Equatable {
    case record(FileRecord)
    case inaccessible(AbsolutePath, reason: String)
}

public struct EnumerationOptions: Sendable, Equatable {
    public var includesHiddenFiles: Bool
    public var descendsIntoPackages: Bool
    public var skipSubtrees: [AbsolutePath]
    public static let `default`: EnumerationOptions
}

public struct FileRecord: Sendable, Equatable {
    public let path: AbsolutePath
    public let fileID: UInt64
    public let volumeID: UInt64
    /// Allocated bytes on disk, the basis of every reclaimable estimate.
    public let allocatedBytes: UInt64
    public let isDirectory: Bool
    public let isExecutable: Bool
    public let created: Date?
    public let modified: Date?
    public let lastOpened: Date?
}

public struct VolumeInfo: Sendable, Equatable {
    public let root: AbsolutePath
    public let volumeID: UInt64
    public let capacityBytes: UInt64
    public let availableBytes: UInt64
    public let isInternal: Bool
}
```

### C14. FileSystemMutating

```swift
/// The write side. Held only by the executor (C17) and the SafetyNet store
/// (C18) in the user process, and by the helper's own implementation in the
/// root process. Engines can never reach it.
///
/// Guarantees:
/// - `moveToTrash` uses the platform trash for the item's volume and returns
///   the resulting trash location, so the result screen can link it.
/// - `move` is atomic per item: on any failure the source is intact at its
///   original path. Cross volume moves preserve metadata and extended
///   attributes or fail whole, never a partial copy left behind.
/// - `delete` is permanent and is only reachable from a plan carrying a
///   permanent deletion confirmation (enforced in C17, not here; this layer
///   stays mechanism).
/// - All methods throw typed `FileSystemError` values whose messages are
///   plain sentences.
public protocol FileSystemMutating: Sendable {
    func moveToTrash(_ path: AbsolutePath) async throws -> AbsolutePath
    func move(_ source: AbsolutePath, to destination: AbsolutePath) async throws
    func delete(_ path: AbsolutePath) async throws
    func createDirectory(at path: AbsolutePath) async throws
    func setPosixPermissions(_ mode: UInt16, at path: AbsolutePath) async throws
    func setExtendedAttributes(_ attributes: [String: Data], at path: AbsolutePath) async throws
}

public typealias FileSystem = FileSystemReading & FileSystemMutating

public enum FileSystemError: Error, Sendable, Equatable {
    case notFound(AbsolutePath)
    case permissionDenied(AbsolutePath)
    case destinationOccupied(AbsolutePath)
    case volumeUnavailable(AbsolutePath)
    case ioFailure(AbsolutePath, description: String)
}
```

### C15. GleamEngine

```swift
/// The shape every engine shares. Scan streams findings; plan turns the
/// user's selection into an operation plan; execution belongs to the
/// executor. Engines never delete anything themselves.
///
/// Guarantees:
/// - `scan` is read only (it only holds `FileSystemReading`) and side effect
///   free. Running it twice against the same file system state yields the
///   same findings (identifiers aside).
/// - `scan` emits `phase` transitions per C4 and `progress` counters that
///   are monotonic. Findings stream as discovered, grouped by category at
///   the consumer.
/// - `scan` respects `context.hasFullDiskAccess`: when false the engine
///   scans what the user domain allows and reports what it skipped through
///   `ScanEvent.degraded`, so the honest banner has real content.
/// - `plan` includes only selected findings, expands each finding into one
///   operation per path, never emits an operation for a denylisted path,
///   and chooses operation kinds per module contract (C20 to C29) and
///   `context.settings.deletionMode`.
/// - `plan` throws `PlanningError` rather than producing a partial plan.
public protocol GleamEngine: Sendable {
    var module: GleamModule { get }
    func scan(_ context: ScanContext) -> AsyncThrowingStream<ScanEvent, Error>
    func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan
}

public struct ScanContext: Sendable {
    public let sessionID: UUID
    public let fileSystem: any FileSystemReading
    public let rules: RuleCatalog
    public let settings: Settings
    public let hasFullDiskAccess: Bool
}

public struct PlanContext: Sendable {
    public let sessionID: UUID
    public let rules: RuleCatalog
    public let settings: Settings
    public let ownership: any PathOwnershipPolicy
}

public enum ScanEvent: Sendable {
    case phase(ScanPhase)
    case progress(ScanCounters)
    case finding(Finding)
    case degraded(unavailable: String)   // plain sentence naming what was skipped
}

public enum PlanningError: Error, Sendable, Equatable {
    case emptySelection
    case findingFromDifferentSession(UUID)
    case keptCopyMissing(findingID: UUID)
}
```

### C16. PathOwnershipPolicy

```swift
/// Decides which process may touch a path. Shared by the app executor and
/// GleamHelperCore so app and helper cannot drift.
///
/// Guarantees:
/// - `userDomain` means the current user can mutate the path without
///   privilege escalation: the user's home, the user's trash directories,
///   user owned temporary locations, and user writable locations on
///   external volumes.
/// - Everything else is `systemDomain` and routes to the helper: system
///   library locations, other users' homes, root owned files anywhere.
/// - Pure function of the path and the environment snapshot. Same inputs,
///   same answer, in both processes. A shared fixture suite runs the same
///   cases against the app build and the helper build of this policy.
public protocol PathOwnershipPolicy: Sendable {
    func ownership(of path: AbsolutePath, environment: OwnershipEnvironment) -> PathOwnership
}

public enum PathOwnership: String, Codable, Sendable, Equatable {
    case userDomain
    case systemDomain
}

public struct OwnershipEnvironment: Codable, Sendable, Equatable {
    public let currentUserHome: AbsolutePath
    public let currentUserID: UInt32
}
```

### C17. PlanExecuting

```swift
/// The only component that performs destructive work in the user process.
/// Routes each operation to the user process file system or to the helper
/// by path ownership, atomically per item.
///
/// Guarantees:
/// - Operations run in plan order, one at a time. An operation either fully
///   completes or its target is untouched; there is no partial file
///   operation at any point, including crash and cancellation.
/// - Before every operation, in this order: denylist check (skip as
///   `skippedDenylisted` when blocked), ownership routing (userDomain runs
///   in process, systemDomain goes to the helper as a typed request, C30).
/// - A plan with any `deletePermanently` operation and a missing or
///   mismatched `permanentDeletionConfirmation` is refused whole with
///   `ExecutionRefusal.permanentDeletionUnconfirmed` before anything runs.
/// - Cancellation takes effect between operations, never mid item.
///   Completed items stay completed, untouched items report `notStarted`,
///   and the final report says exactly which is which.
/// - The stream always terminates with exactly one `planCompleted` carrying
///   the full `ExecutionReport`, whatever happened, including refusal and
///   cancellation.
/// - Helper replies are validated against C30 before being trusted; a
///   malformed reply fails that operation, never the process.
/// - `quarantine` and `archive` operations route through the SafetyNet
///   store (C18); the executor never invents storage paths itself.
public protocol PlanExecuting: Sendable {
    func execute(_ plan: OperationPlan) -> AsyncStream<ExecutionEvent>
}

public enum ExecutionEvent: Sendable, Equatable {
    case refused(ExecutionRefusal)
    case operationStarted(operationID: UUID)
    case operationFinished(operationID: UUID, result: OperationResult)
    case planCompleted(ExecutionReport)
}

public enum ExecutionRefusal: Sendable, Equatable {
    case permanentDeletionUnconfirmed
    case helperUnavailable(reason: String)
}
```

### C18. SafetyNetStoring

```swift
/// The quarantine and archive store. Reversibility is the trust feature;
/// this contract is where it lives.
///
/// Guarantees:
/// - `store` moves the file into the store (never copies and deletes as two
///   visible steps), snapshots metadata per C8, strips execute permissions
///   on the stored payload so quarantined malware cannot run, and preserves
///   extended attributes for restore fidelity.
/// - `restore` reinstates the payload at its origin path with its original
///   permission mode, extended attributes and dates. If the origin path is
///   now occupied it throws `originOccupied` and changes nothing.
/// - `restoreGroup` restores every unrestored item of the group or throws
///   before moving anything if any origin is occupied; an uninstall restores
///   as one unit or not at all.
/// - Retention: items become purge eligible 30 days after storage. Nothing
///   is purged automatically. `purge` requires a confirmation whose counts
///   match the items being purged, mirroring C6.
/// - Reinstall survival: the manifest and payloads live in Application
///   Support. Deleting and reinstalling the app then listing items returns
///   the same items. This is a tested behaviour, not a hope.
/// - The store refuses to store a path the denylist blocks (defence in
///   depth; such a path should never reach it).
/// - All mutations are serialised within the store (it is an actor or
///   equivalent); concurrent quarantine and restore cannot corrupt the
///   manifest.
public protocol SafetyNetStoring: Sendable {
    func store(
        _ path: AbsolutePath,
        source: SafetyNetItem.Source,
        groupID: UUID?
    ) async throws -> SafetyNetItem

    func items(includingRestored: Bool) async throws -> [SafetyNetItem]
    func restore(itemID: UUID) async throws
    func restoreGroup(groupID: UUID) async throws
    func purge(itemIDs: [UUID], confirmation: PurgeConfirmation) async throws
    func purgeEligibleItems(asOf now: Date) async throws -> [SafetyNetItem]
}

public struct PurgeConfirmation: Codable, Sendable, Equatable {
    public let itemCount: UInt32
    public let byteTotal: UInt64
    public let confirmedAt: Date
}

public enum SafetyNetError: Error, Sendable, Equatable {
    case originOccupied(AbsolutePath)
    case itemNotFound(UUID)
    case alreadyRestored(UUID)
    case confirmationMismatch
    case denylistedPath(AbsolutePath)
}
```

### C19. RuleCatalogProviding

```swift
/// Owns the current rule catalogue: the embedded baseline plus signed
/// channel updates.
///
/// Guarantees:
/// - `current` is always available. First launch with no network returns
///   the embedded baseline.
/// - `refreshFromChannel` fetches the channel manifest, verifies the
///   Ed25519 signature against the pinned rules public key, and adopts the
///   catalogue only if the signature verifies and the version is strictly
///   greater than the current one. Any failure leaves `current` exactly as
///   it was and throws a typed error.
/// - Adoption is atomic: no observer ever sees a half applied catalogue.
/// - The effective denylist exposed to C10 consumers is the union described
///   there; this provider computes it and a test proves an update can never
///   remove a baseline denylist entry.
/// - Network: the rules channel is one of exactly three permitted outbound
///   endpoints. This provider talks to nothing else.
public protocol RuleCatalogProviding: Sendable {
    var current: RuleCatalog { get async }
    func refreshFromChannel() async throws -> RuleCatalogUpdate
}

public enum RuleCatalogUpdate: Sendable, Equatable {
    case alreadyCurrent
    case updated(from: RuleCatalogVersion, to: RuleCatalogVersion)
}

public enum RuleCatalogError: Error, Sendable, Equatable {
    case signatureInvalid
    case versionNotNewer(current: RuleCatalogVersion, offered: RuleCatalogVersion)
    case malformedCatalog(description: String)
    case channelUnreachable(description: String)
}
```

---

## Engines

Every engine conforms to `GleamEngine` (C15). Each contract below adds the
engine's categories, its specific invariants and its specific errors. All
engine tests run against an in memory `FileSystemReading` with fixture trees.

### C20. CleanupEngine

```swift
/// System junk scanning: caches, logs, broken downloads, Xcode derived data
/// and simulator caches, browser caches, temporary files, local mail
/// attachment copies, and every trash bin including external volume trashes.
///
/// Guarantees:
/// - Emits only Cleanup categories from C5. Categories are itemised: a
///   cache finding lists the actual paths, never a directory total the user
///   cannot inspect.
/// - Preselection follows the rules catalogue: a finding is preselected
///   only when its rule says preselectable and its risk is safe. Nothing
///   risky is ever preselected, whatever the catalogue says (the engine
///   enforces the conjunction).
/// - Mail attachment findings cover local copies only; removing one never
///   touches server state, and the explanation says so.
/// - Trash bin findings are per volume so the review shows where each bin
///   lives.
/// - `plan` maps findings to `moveToTrash` when settings.deletionMode is
///   trash, `deletePermanently` when permanent. Trash bin contents always
///   plan as `deletePermanently` (moving trash to trash is meaningless),
///   and this is the one Cleanup case allowed to do so; it still requires
///   the confirmation from C6.
/// - Performance: the full scan of a typical 512 gigabyte system disk
///   completes in under 60 seconds on Apple silicon. Enforced by a
///   performance test against a generated fixture tree in M2.
public struct CleanupEngine: GleamEngine { /* module == .cleanup */ }
```

### C21. ClutterEngine

```swift
/// Large and old files, downloads triage, duplicates by content hash,
/// similar photos.
///
/// Guarantees:
/// - Large and old thresholds come from Settings (C12) and are honoured
///   exactly: a file at threshold minus one byte or one day is not a
///   finding.
/// - Duplicate sets are grouped by full content hash; two files of equal
///   size and different content are never in one set. Each set is one
///   Finding with category `duplicateSet(keptPath:)`.
/// - Keep one invariant: `plan` never emits an operation targeting the kept
///   path of any set, and throws `PlanningError.keptCopyMissing` if a
///   selection somehow excludes it. At least one copy always survives, by
///   construction, and a test attacks this with hostile selections.
/// - Similar photo sets carry the same kept path mechanics. Similarity
///   grouping is implementation; the contract is only that every member is
///   an image file and sets never overlap.
/// - Old file findings use last opened date where the volume records it,
///   falling back to modification date, and the explanation names which.
public struct ClutterEngine: GleamEngine { /* module == .clutter */ }
```

### C22. SpaceLensEngine

```swift
/// The streaming disk map. Scan of any volume the app can read.
///
/// Guarantees:
/// - `map` streams nodes as the tree is discovered so the map builds
///   outward from the root while scanning; consumers never wait for the
///   full tree.
/// - `sizeRevision` events only ever increase a node's subtree total
///   (the map grows, matching the motion design), and totals converge to
///   the true allocated byte totals when the stream completes.
/// - Mapping a full volume completes in under 30 seconds on Apple silicon.
///   Enforced by a performance test in M2.
/// - Selecting nodes for deletion produces ordinary Findings with category
///   `spaceLensSelection` and risk `review` (never preselected), then the
///   standard `plan` path applies: Trash by default, identical to Cleanup.
/// - The map never offers selection of a denylisted path; such nodes render
///   but are not selectable.
public struct SpaceLensEngine: GleamEngine {
    /// In addition to GleamEngine.scan, the streaming map surface:
    public func map(
        volume: AbsolutePath,
        context: ScanContext
    ) -> AsyncThrowingStream<SpaceLensUpdate, Error>
}

public enum SpaceLensUpdate: Sendable, Equatable {
    case node(SpaceLensNode)
    case sizeRevision(path: AbsolutePath, subtreeBytes: UInt64)
    case completed
}

public struct SpaceLensNode: Sendable, Equatable {
    public let path: AbsolutePath
    public let parent: AbsolutePath?
    public let isDirectory: Bool
    public let subtreeBytes: UInt64
    public let isSelectable: Bool   // false for denylisted paths
}
```

### C23. PerformanceEngine

```swift
/// Maintenance tasks, login and background items, live load view. Three
/// concerns, one module.
///
/// Guarantees:
/// - `scan` reports maintenance opportunities and login item inventory as
///   findings (risk safe for maintenance, review for third party launch
///   items); the live process view is not a scan, it is C25.
/// - `plan` for maintenance selections emits `runMaintenance` operations
///   with privilege root (maintenance tasks are the helper's job) and for
///   login item selections emits `setLaunchItemEnabled` with
///   enabled false. Disable, never delete: no PerformanceEngine plan ever
///   contains a file removal operation. A test asserts this over the whole
///   generated plan space.
/// - Tasks that clear user visible data are flagged per C7 and the finding
///   explanation says what will be cleared before the user runs it.
public struct PerformanceEngine: GleamEngine { /* module == .performance */ }
```

### C24. LaunchItemManaging

```swift
/// Inventory and state changes for login and background items: SMAppService
/// registrations and legacy launch agents and daemons, per owning app.
///
/// Guarantees:
/// - `list` attributes every item to its owning app where the owner is
///   resolvable, with the item's kind, scope and current enabled state, and
///   the path that can be revealed in Finder.
/// - `setEnabled` disables or enables, never deletes, and returns a
///   `LaunchItemChange` recording the prior state. The app persists these
///   records so re enabling is one click and survives relaunch.
/// - User scope items change in process; system scope items route through
///   the helper (C30). The caller does not choose; the implementation
///   routes by scope.
/// - Changing an item that no longer exists throws `itemNotFound` and
///   changes nothing.
public protocol LaunchItemManaging: Sendable {
    func list() async throws -> [LaunchItem]
    func setEnabled(_ enabled: Bool, item: LaunchItemID) async throws -> LaunchItemChange
}

public struct LaunchItemID: Codable, Sendable, Hashable {
    public let value: String   // stable identifier: label plus scope
}

public struct LaunchItem: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case appService          // SMAppService registration
        case legacyLaunchAgent
        case legacyLaunchDaemon
    }
    public enum Scope: String, Codable, Sendable, Equatable {
        case user, system
    }
    public var id: LaunchItemID { identifier }
    public let identifier: LaunchItemID
    public let label: String
    public let kind: Kind
    public let scope: Scope
    public let owningAppBundleID: String?
    public let owningAppName: String?
    public let path: AbsolutePath
    public let isEnabled: Bool
}

public struct LaunchItemChange: Codable, Sendable, Equatable {
    public let item: LaunchItemID
    public let previousEnabled: Bool
    public let newEnabled: Bool
    public let changedAt: Date
}
```

### C25. ProcessMonitoring

```swift
/// The live memory and processor view, and confirmed process quit.
///
/// Guarantees:
/// - `samples` streams snapshots sorted heaviest first (by memory footprint)
///   at a steady cadence suitable for a live view; the stream never blocks
///   the main actor.
/// - Monitoring never quits, signals or otherwise affects any process.
/// - `quit` requires the caller to have shown a confirmation naming the
///   process; `force` is a second, separate confirmation. The API takes the
///   process identifier and name together and throws `nameMismatch` if the
///   identifier now belongs to a different process, so a recycled process
///   identifier can never kill the wrong process.
public protocol ProcessMonitoring: Sendable {
    func samples() -> AsyncStream<[ProcessSample]>
    func quit(processIdentifier: Int32, expectedName: String, force: Bool) async throws
}

public struct ProcessSample: Sendable, Equatable {
    public let processIdentifier: Int32
    public let name: String
    public let bundleID: String?
    public let memoryFootprintBytes: UInt64
    public let processorLoadFraction: Double   // 0.0 to 1.0 per core aggregate
}

public enum ProcessQuitError: Error, Sendable, Equatable {
    case processNotFound(Int32)
    case nameMismatch(expected: String, actual: String)
    case notPermitted(String)
}
```

### C26. ApplicationsEngine

```swift
/// App inventory, full uninstall, leftover sweep.
///
/// Guarantees:
/// - `inventory` discovers installed apps and their leftovers per C9.
/// - Uninstall findings itemise the bundle and every leftover before
///   removal; nothing is hidden inside a total.
/// - Archive first: `plan` for an uninstall emits only `archive` operations
///   (into SafetyNet, one shared groupID per uninstall). There is no
///   separate delete step; the archive move is the removal, so the whole
///   uninstall is reversible for 30 days as one unit and there is no window
///   where a file is deleted but not archived. A test asserts no uninstall
///   plan ever contains `moveToTrash` or `deletePermanently`.
/// - The running app's own bundle and MacGleam itself are never offered for
///   uninstall.
/// - Leftover sweep: `scan` finds orphaned files from apps already deleted
///   (category `orphanedLeftover`, risk review, never preselected), using
///   the same conservative association rule as C9.
public struct ApplicationsEngine: GleamEngine {
    public func inventory(context: ScanContext) async throws -> [AppInventoryEntry]
    /// module == .applications
}
```

### C27. ProtectionEngine

```swift
/// Malware and adware scanning over Apple's published XProtect YARA rules
/// plus the curated adware list, and privacy cleanup. Honest labelling:
/// malware and adware removal, not antivirus.
///
/// Guarantees:
/// - Detection targets exactly: known malware binaries by YARA signature,
///   adware launch agents and daemons, suspicious browser extensions, known
///   unwanted app paths.
/// - Malware findings carry the matching signature identifier in the
///   category and a plain explanation. Risk is `dangerous` and they are
///   preselected (quarantine is reversible; see C5 preselection rules).
/// - `plan` for malware and adware findings emits only `quarantine`
///   operations. A Protection plan never contains `moveToTrash` or
///   `deletePermanently` for a detection finding: quarantine only, never
///   silent delete, typed into the plan shape and tested.
/// - Privacy findings (browser history, cookies, site data per browser,
///   recent item lists, Wi-Fi network history) are never preselected; each
///   is an explicit user selection. Privacy selections plan as
///   `deletePermanently` (there is no meaningful trash for a history
///   database row) and the explanation names exactly what is cleared.
/// - A YARA rule compile failure disables that rule with a logged warning
///   and never aborts the whole scan.
public struct ProtectionEngine: GleamEngine { /* module == .protection */ }
```

### C28. YaraScanning

```swift
/// The boundary to the vendored YARA library, kept narrow so ProtectionEngine
/// tests can run against a fake matcher with scripted matches.
///
/// Guarantees:
/// - `compile` accepts YARA rule source (the XProtect published rules and
///   our curated additions) and throws `compileFailed` with the offending
///   rule identifier rather than a library error string.
/// - `match` reads the candidate file through `FileSystemReading` (bounded
///   by maxBytes from C13) and returns every matching rule identifier.
///   No match is not an error; it returns an empty array.
/// - Thread safety: compiled rules are immutable and may be matched against
///   concurrently.
public protocol YaraScanning: Sendable {
    func compile(rulesSource: String) throws -> CompiledYaraRules
    func match(
        file: AbsolutePath,
        against rules: CompiledYaraRules,
        fileSystem: any FileSystemReading
    ) async throws -> [YaraMatch]
}

public struct CompiledYaraRules: Sendable {
    public let ruleCount: Int
}

public struct YaraMatch: Sendable, Equatable {
    public let ruleIdentifier: String
}

public enum YaraError: Error, Sendable, Equatable {
    case compileFailed(ruleIdentifier: String, description: String)
    case fileUnreadable(AbsolutePath)
}
```

### C29. SmartCareOrchestrating

```swift
/// One scan composing deep clean (Cleanup), storage declutter (Clutter large
/// and old files plus downloads triage) and performance boost (Performance
/// maintenance) concurrently, with one combined result and per job detail.
///
/// Guarantees:
/// - Exactly the jobs in `SmartCareJob` run. No stub jobs, ever: threat
///   scan and software updates do not appear in any form until their
///   modules ship and this enum gains cases.
/// - Jobs run concurrently; events interleave, each tagged with its job.
/// - One job failing does not sink the others: the combined result carries
///   the failure as that job's outcome, named in a plain sentence, and the
///   remaining jobs' findings are fully usable.
/// - `summary` is emitted exactly once, after all jobs finish, with the one
///   combined number pair the hub presents: bytes reclaimable and issue
///   count.
/// - The combined review supports deselection per finding, and `plan`
///   produces one combined OperationPlan whose operations preserve each
///   underlying engine's plan invariants (C20, C21, C23).
public protocol SmartCareOrchestrating: Sendable {
    func scan(_ context: ScanContext) -> AsyncThrowingStream<SmartCareEvent, Error>
    func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan
}

public enum SmartCareJob: String, Codable, Sendable, CaseIterable, Equatable {
    case deepClean
    case storageDeclutter
    case performanceBoost
}

public enum SmartCareEvent: Sendable {
    case job(SmartCareJob, ScanEvent)
    case jobFailed(SmartCareJob, reason: String)
    case summary(SmartCareSummary)
}

public struct SmartCareSummary: Codable, Sendable, Equatable {
    public let bytesReclaimable: UInt64
    public let issueCount: UInt32
    public let perJob: [SmartCareJobOutcome]
}

public struct SmartCareJobOutcome: Codable, Sendable, Equatable {
    public enum Outcome: Codable, Sendable, Equatable {
        case completed(findingCount: UInt32, bytes: UInt64)
        case failed(reason: String)
    }
    public let job: SmartCareJob
    public let outcome: Outcome
}
```

---

## GleamHelperCore

### C30. Helper message contract

```swift
/// The complete XPC (inter process communication) message set between
/// MacGleam.app and GleamHelper. Defined once, in a package both link, so the
/// contract cannot drift. Every type here is Codable, Sendable and Equatable
/// and round trips through the wire encoding losslessly (a property test
/// asserts encode then decode is identity).
///
/// Guarantees:
/// - Closed set. The helper is not a general file service: there is no
///   request carrying a command string, a shell fragment or an arbitrary
///   verb. Adding a case is an API review event in both processes.
/// - Every mutating request names the plan and operation it belongs to, so
///   the helper's log and the app's report reconcile one to one.
/// - `remove` carries an explicit destination; the helper never chooses
///   where a file goes.
/// - Version handshake: the app sends `handshake` first; a helper whose
///   contract version differs refuses all further requests with
///   `versionMismatch` and the app prompts for helper update. Neither
///   process assumes the other is current.
public enum HelperRequest: Codable, Sendable, Equatable {
    case handshake(contractVersion: UInt16)
    case remove(target: AbsolutePath, destination: HelperRemovalDestination,
                planID: UUID, operationID: UUID)
    case setLaunchItemEnabled(item: LaunchItemID, enabled: Bool,
                              planID: UUID, operationID: UUID)
    case runMaintenance(task: MaintenanceTask, planID: UUID, operationID: UUID)
}

public enum HelperRemovalDestination: Codable, Sendable, Equatable {
    /// Move into the requesting user's trash, transferring ownership so the
    /// user can restore it. See GRAPH.md open questions for the unresolved
    /// design point on root owned items and the Trash default.
    case userTrash(userHome: AbsolutePath)
    /// Move into the SafetyNet store directory provided by the app.
    case safetyNetStore(storeDirectory: AbsolutePath)
    case permanent
}

public enum HelperResponse: Codable, Sendable, Equatable {
    case handshakeAccepted(contractVersion: UInt16)
    case success(operationID: UUID, bytesReclaimed: UInt64)
    case launchItemChanged(operationID: UUID, change: LaunchItemChange)
    case refused(operationID: UUID?, reason: HelperRefusal)
    case failed(operationID: UUID, reason: String)
}

public enum HelperRefusal: String, Codable, Sendable, Equatable {
    case denylisted              // target blocked by the helper's own denylist
    case notSystemDomain         // target is user domain; least privilege cuts both ways
    case versionMismatch
    case identityRejected        // connecting client failed code signing verification
    case malformedRequest
}
```

### C31. Helper policy

```swift
/// The helper's own gate. Runs inside GleamHelper before any request is
/// acted on. This is the security model made executable.
///
/// Guarantees, in evaluation order:
/// - Identity: the connection's audit token must satisfy the code signing
///   requirement (exact team identifier and bundle identifier of
///   MacGleam.app). Anything else is dropped before message decoding, and
///   a decoded message on a rejected connection is impossible by
///   construction.
/// - Handshake: contract versions must match (C30).
/// - Domain: `remove` and `setLaunchItemEnabled` targets must be
///   systemDomain under the shared PathOwnershipPolicy (C16). User domain
///   targets are refused `notSystemDomain`; the helper never does work the
///   user process could do itself.
/// - Denylist: the target is checked against the helper's own effective
///   denylist (embedded baseline united with any catalogue the helper has
///   itself verified per C10 and C19). The app's opinion is not trusted; a
///   compromised app process cannot make the helper cross the denylist.
/// - Only then does the operation run, atomically per item, with the same
///   atomicity guarantee as C17.
/// - The helper performs no network activity, ever.
/// - Contract tests run the full policy against a test double transport in
///   continuous integration, and a smaller smoke suite runs against the
///   real daemon on a real machine before release.
public protocol HelperPolicy: Sendable {
    func admit(_ request: HelperRequest, from client: ClientIdentity) -> HelperAdmission
}

public struct ClientIdentity: Sendable, Equatable {
    public let teamIdentifier: String
    public let bundleIdentifier: String
    public let codeSigningValid: Bool
}

public enum HelperAdmission: Sendable, Equatable {
    case admitted
    case refused(HelperRefusal)
}
```

---

## App services

### C32. FullDiskAccessMonitoring

```swift
/// Full Disk Access state for the onboarding flow and the degraded mode
/// banner.
///
/// Guarantees:
/// - `isGranted` reflects the real, current grant, probed in a way that
///   does not itself trigger a permission prompt.
/// - `updates` emits when the grant changes while the app runs, so the
///   onboarding flow advances by itself when the user flips the toggle in
///   System Settings. Emission within two seconds of the change.
/// - `openPrivacySettings` deep links to the Privacy and Security pane.
/// - The app never nags on a schedule: this service reports state, it never
///   prompts.
public protocol FullDiskAccessMonitoring: Sendable {
    var isGranted: Bool { get async }
    func updates() -> AsyncStream<Bool>
    @MainActor func openPrivacySettings()
}
```

### C33. SystemStatsProviding

```swift
/// Storage, memory and processor figures for the menu bar scene and the hub
/// card live figures.
///
/// Guarantees:
/// - `samples` streams at a cadence suitable for a glanceable display and
///   never blocks the main actor.
/// - Storage figures agree with `VolumeInfo` (C13) for the boot volume; the
///   menu bar and Space Lens never show contradictory numbers for the same
///   volume at the same instant of sampling.
/// - Memory pressure buckets match the platform's own notion (normal,
///   warning, critical) so the hub card never invents a fourth state.
public protocol SystemStatsProviding: Sendable {
    func samples() -> AsyncStream<SystemStats>
}

public struct SystemStats: Sendable, Equatable {
    public enum MemoryPressure: String, Sendable, Equatable {
        case normal, warning, critical
    }
    public let bootVolumeCapacityBytes: UInt64
    public let bootVolumeAvailableBytes: UInt64
    public let memoryPressure: MemoryPressure
    public let memoryUsedBytes: UInt64
    public let processorLoadFraction: Double
    public let sampledAt: Date
}
```

### C34. LicenceValidating

```swift
/// Trial and licence lifecycle.
///
/// Guarantees:
/// - `currentState` is a pure function of the persisted record and `now`;
///   passing a controlled clock makes every trial boundary testable.
/// - Trial starts at first launch and runs 14 days. The recorded start
///   never moves backwards; reinstalling within the window resumes the same
///   trial where the record survives (see GRAPH.md open questions on trial
///   persistence).
/// - `verify` is offline, against the embedded public key, and constant
///   with respect to network availability.
/// - `activate` is the only network call in this contract and one of the
///   three permitted outbound endpoints. It exchanges a key for a
///   SignedLicence; any server failure leaves the persisted state
///   untouched and reports a plain sentence.
public protocol LicenceValidating: Sendable {
    func currentState(now: Date) async -> LicenceState
    func verify(_ licence: SignedLicence) -> Bool
    func activate(licenceKey: String) async throws -> LicenceState
}

public enum LicenceActivationError: Error, Sendable, Equatable {
    case keyRejected(reason: String)
    case serverUnreachable(description: String)
    case malformedResponse
}
```

### C35. SettingsStoring

```swift
/// Loads and persists Settings (C12).
///
/// Guarantees:
/// - Loaded once at startup, validated on load. A corrupt or missing store
///   yields `Settings.defaults`, never a crash, and never a permanent
///   deletion mode the user did not choose (deletionMode falls back to
///   trash on any validation doubt).
/// - `save` is atomic: a crash mid save leaves either the old or the new
///   settings, never a torn file.
/// - Observation: `updates` emits the new value after each successful save
///   so the menu bar scene and open modules react without polling.
public protocol SettingsStoring: Sendable {
    func load() async -> Settings
    func save(_ settings: Settings) async throws
    func updates() -> AsyncStream<Settings>
}
```

---

## Cross contract invariants

These span boundaries and get their own always true tests:

- No path, file name or scan content ever leaves the machine. The only
  outbound endpoints in the whole codebase are the Sparkle appcast, the rules
  channel (C19) and licence activation (C34). A test walks the dependency
  graph for network capable types and asserts they exist only in those three
  places.
- The denylist is enforced at three independent points: engine plan time
  (C15), executor run time (C17), helper admission (C31). Removing any one
  enforcement still leaves a blocked path unremovable.
- Engines hold `FileSystemReading` only (C13). No engine package links the
  mutating side. This is checked at the package dependency level, not by
  review.
- Every destructive operation is reversible or explicitly confirmed: Trash
  (restorable by the user), SafetyNet (C18, 30 days), or a
  PermanentDeletionConfirmation with exact counts (C6). There is no fourth
  path to deletion.
- All animation resolves through C2 tokens and honours Reduce Motion. A
  lint level test fails on any direct animation constructor outside
  GleamDesign.
- Counters shown to the user only count up during a scan (C4), and phases
  only advance (C4).
