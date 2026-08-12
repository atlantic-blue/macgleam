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
- Contracts are numbered C1 to C39. GRAPH.md maps contracts to slices and
  carries each slice's verification tier.
- Nothing here says how. Enumeration strategy, hashing algorithm choice, shader
  code and storage engines are implementation, except where DESIGN.md locked a
  decision that is observable in behaviour (for example file id deduplication).

Package layout, restated from DESIGN.md: GleamDesign (C1, C2), GleamCore
(C3 to C19), engine packages (C20 to C29), GleamHelperCore (C30, C31), app
services (C32 to C35), hub interface (C36, C37), module interfaces (C38,
C39).

---

## GleamDesign

### C1. Design tokens

```swift
import SwiftUI

/// The complete visual token set. Every colour, size, radius and elevation in
/// the app resolves through these types. There is no other source of visual
/// constants.
///
/// Revised 2026-08-10 to carry the Lumina Utility design specification
/// (`.desings/lumina_utility/DESIGN.md`), and again 2026-08-11 when light
/// became a specified appearance in its own right. The guarantees below are
/// the current ones.
///
/// Guarantees:
/// - Colour tokens resolve for both dark and light appearances from day one,
///   and each appearance has its own specification: Lumina Utility for dark,
///   Clinical Precision (`.desings/lumina_utility/DESIGN-light.md`) for light.
///   Neither appearance is derived from the other, and no token is the same
///   colour in both.
/// - Dark resolves every token the Lumina specification names to that hex
///   exactly, asserted token by token. Light does the same for the Clinical
///   Precision hexes that serve the role, and departs where the prose
///   governs: a card is white, and the canvas and the two text roles are
///   pinned to hold the contrast the prose demands. Every departure is a
///   pinned value with its own assertion, never a value free to drift. The
///   three health colours are ours in both appearances, because neither
///   specification names them.
/// - Where a specification's palette and its prose disagree, the prose wins,
///   because the prose is the part that says what a colour is for.
/// - Semantic colours (safe, review, dangerous) and every text role meet Web
///   Content Accessibility Guidelines AA contrast against the surfaces they
///   appear on, in both appearances. This is a testable threshold, not an
///   aspiration: safe, review, dangerous, textPrimary, textSecondary, primary
///   and accent each hold at least 4.5 to 1 over baseBackground, surfaceLow,
///   surface and surfaceHigh, and onPrimary holds it over primary.
///   surfaceLowest and surfaceBright are wells that hold a glyph or an image,
///   never running text, so they are outside that matrix.
/// - Layout spacing is an 8 point grid. `GleamSpacing.points(n)` returns
///   exactly `n * 8`. Control level padding may sit on the half step,
///   `GleamSpacing.half(n)` returning exactly `n * 4`, because the
///   specification pads cards and controls at 20 and 4 points. No view uses a
///   spacing value off both steps.
/// - Exactly three corner radii and three elevation levels exist. The radii
///   nest: control (6) inside item (8) inside card (12).
/// - The type scale has exactly eight roles. Every role carries its point
///   size, weight, tracking and line height, so a view never restates them.
///   The text roles descend in size with no two the same (mono sits outside
///   that ordering), only the three largest carry negative tracking, and every
///   role resolves a distinct font. SF Pro and SF Mono only; the specification
///   names Inter and JetBrains Mono solely because a web page cannot use SF
///   Pro, and a native app can.
public enum GleamColorToken: CaseIterable, Sendable {
    // Canvas and surfaces, lowest to highest. Hexes are the dark values.
    case baseBackground      // #0A0E1A, the canvas
    case surfaceLowest       // #050E1E
    case surfaceLow          // #121C2C, the navigation rail
    case surface             // #141A2E, the card
    case surfaceHigh         // #202A3B, an inactive icon well
    case surfaceBright       // #303A4B, the avatar well
    // Accents. Two distinct roles, both cyan, never interchangeable.
    case primary             // #A9F9FF, titles, active navigation, filled controls
    case onPrimary           // #00373A, text and glyphs on a primary fill
    case accent              // #6FE0E8, glow, strokes, progress, live figures
    // Text.
    case textPrimary         // #D9E3F9
    case textSecondary       // #BCC9CA
    // Lines.
    case outline             // #869394
    case outlineVariant      // #3D494A
    // Semantic health.
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
    /// Returns count multiplied by half the grid unit. Traps on negative
    /// counts. `half(2)` and `points(1)` are the same distance.
    public static func half(_ count: Int) -> CGFloat { fatalError("contract") }
}

public enum GleamRadius: CaseIterable, Sendable {
    case card                // 12, containers
    case item                // 8, rows and wells inside a container
    case control             // 6, buttons and inputs
    public var value: CGFloat { fatalError("contract") }
}

/// A surface's shadow, as data, so a test asserts on it rather than on a
/// screenshot.
public struct GleamShadow: Sendable, Equatable {
    public let color: Color
    public let opacity: Double
    public let radius: CGFloat
    public let offsetY: CGFloat
    public init(color: Color, opacity: Double, radius: CGFloat, offsetY: CGFloat)
    /// No shadow at all, which is what a resting surface casts in dark.
    public static let none: GleamShadow
}

/// How far a surface sits above the one behind it.
///
/// Elevation is appearance aware, and this is not a detail that can be
/// averaged: the two specifications genuinely disagree. Dark separates layers
/// by tone and a luminous hairline, so a resting card casts nothing and only a
/// lifted one casts, sharply. Light has no tone left to spend above white, so
/// every level casts, softly and in the text navy rather than in black.
///
/// Guarantees, each of them a value a test reads directly:
/// - `low.shadow(for: .dark)` is exactly `GleamShadow.none`. Dark's lifted
///   levels cast black at opacity 0.5, radius 12, offset 4.
/// - Every level casts something in light: opacity and radius are both above
///   zero, at 0.05 / 12 / 4 resting, 0.08 / 20 / 8 hovered and
///   0.12 / 32 / 12 floating.
/// - A light shadow's colour is the text navy #16213A; a dark one's is black.
/// - Shadow opacity and radius never fall as the level rises, in either
///   appearance.
/// - A resting surface draws an edge in both appearances, white in dark and
///   the specified separator #E1E5ED in light, and a dark edge never exceeds
///   0.2 opacity, so it reads as an edge rather than as a border.
public enum GleamElevation: CaseIterable, Sendable {
    case low                 // a resting card
    case medium              // a hovered or focused card
    case high                // a floating menu, popover or modal
    /// The hairline at the surface's edge, already carrying its opacity.
    public func edge(for appearance: ColorScheme) -> Color { fatalError("contract") }
    public func shadow(for appearance: ColorScheme) -> GleamShadow { fatalError("contract") }
}

public enum GleamTypeToken: CaseIterable, Sendable {
    case display     // 56 over 64
    case heading     // 34 over 40
    case title       // 22 over 28, view and card headings
    case headline    // 15 over 20, the brand line
    case label       // 14 over 20, navigation and control labels
    case body        // 13 over 18, descriptions and list items
    case caption     // 11 over 14, metadata
    case mono        // 12 over 16, file paths
    public var font: Font { fatalError("contract") }
    public var size: CGFloat { fatalError("contract") }
    public var weight: Font.Weight { fatalError("contract") }
    public var tracking: CGFloat { fatalError("contract") }
    /// Line height minus point size, which is what SwiftUI's lineSpacing takes.
    public var lineSpacing: CGFloat { fatalError("contract") }
}

extension View {
    /// Applies a text role whole: its face, its tracking and its line height,
    /// so no view restates a metric.
    public func gleamType(_ role: GleamTypeToken) -> some View
    /// Applies an elevation's shadow for the given appearance.
    public func gleamShadow(_ level: GleamElevation, for appearance: ColorScheme) -> some View
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
///   itemCount never decrease. The motion design (counters only count up)
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

/// Amended 2026-08-09 in s2e: `findingCount` becomes `itemCount` and counts
/// path entries rather than findings. A streaming scan emits a category as
/// several findings (C15), so a count of findings moves with a constant
/// inside the engine: the same disk would report 57 or 114 depending on the
/// batch size, and the scan progress line would show a number nobody outside
/// the engine can interpret. A count of items is what the person reading it
/// already thinks it is, and it does not move when the batch size does.
public struct ScanCounters: Codable, Sendable, Equatable {
    public var filesSeen: UInt64
    public var bytesReclaimable: UInt64
    /// Path entries across the findings emitted so far, not findings. Rises
    /// by a finding's entry count in the same step that emits that finding,
    /// and by one for a finding that carries no entries (C5), where the
    /// finding is itself the item.
    public var itemCount: UInt32
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
    case fullSweep, cleanup, protection, performance, applications, leftovers, diskMap
}
```

### C5. Finding

Amended 2026-08-11 in s3d: the pathless exception is stated over the
Performance module rather than over a list of categories, and the new
Performance category `launchItem` joins it. Adds that category to
`FindingCategory`. Neither clause changes the stored shape of an existing
finding, so nothing migrates; the source level cost of the new case is in
C24's migration note.

Amended 2026-08-11 in s3c: a finding may carry no path entries, and
the categories that carry none are named exactly. Adds the Performance
category `maintenanceTask`, without which s3c has no finding to emit,
and the preselection rule for tasks that clear user visible data. Both
clauses are below; neither changes the stored shape of an existing
finding, so nothing migrates.

Amended 2026-08-09 in s2e: a finding is a bounded batch, not a whole
category. See the second migration note after this contract.

Amended 2026-08-09 in s2d: findings carry per path allocated byte sizes.
This retires the s2b ScannedAllocationCache pattern and is a breaking
change to the Finding initialiser and its Codable encoding. The migration
note after this contract lists the existing test pins that change.

```swift
/// The unit of user review. Everything a user can select, inspect and act on
/// is a Finding.
///
/// Guarantees:
/// - `entries` is empty exactly for the categories that name no file,
///   and never empty for any other. The rule is stated over the module,
///   not over a list of cases: no Performance finding names a path
///   (C23), so every Performance category is pathless, and a category
///   added to that module inherits the exception with no further
///   amendment here. Today the Performance categories are
///   `maintenanceTask` (C7, C23), which names a task the machine
///   performs rather than files it removes, and `launchItem` (C24,
///   C23), which names a registration to disable rather than a file to
///   delete. No category of any other module is pathless.
/// - A launch item does have a path, and it never travels as a finding
///   entry. `LaunchItem.path` (C24) exists so the row can be revealed in
///   Finder, and it stays on the item. A `PathEntry` is a removal target
///   and a byte source, and a launch item is neither: disabling a
///   registration reclaims nothing and removes nothing. So the pathless
///   rule is about what a finding offers for action, not about whether
///   the module knows where anything lives.
/// - The test form is an exhaustive switch over `FindingCategory` in the
///   suite, classifying every case as pathless or path carrying, with a
///   finding built for each case and asserted against its
///   classification. A case added later fails to compile until somebody
///   classifies it. Listing the pathless cases by hand instead would let
///   a Performance category be added and quietly missed, which is the
///   one failure this clause exists to prevent.
/// - The exception is deliberate and load bearing, not an oversight. A
///   Performance finding that carried a path would be one careless plan
///   builder away from becoming a file removal. With no path to expand,
///   "no PerformanceEngine plan ever contains a file removal" (C23) is
///   a structural property of the data rather than a rule somebody has
///   to keep obeying, and it holds for code nobody has written yet.
/// - Every entry of every other finding is inspectable in the UI down
///   to the full path string (mono type token).
/// - A finding is a bounded unit of review, never a whole category. Every
///   finding a scan emits carries at most
///   `ScanStreamPolicy.maximumFindingEntries` entries (C15), so one category
///   is normally spread over several findings. `paths` and `byteSize` are
///   this finding's own; a category's path list, file count and byte total
///   are sums across its findings. Nothing that consumes findings may assume
///   one finding per category.
/// - `PathEntry.allocatedBytes` is the allocated (on disk) byte total that
///   removing the entry's path reclaims: the allocated size of a file, the
///   subtree allocated total of a directory. Allocated, never logical, so
///   sparse and cloned files do not inflate the promise (GRAPH.md open
///   question 9).
/// - `byteSize` and `paths` are pure derivations of `entries`: byteSize is
///   the sum of allocatedBytes over entries, paths is the entries' paths in
///   entry order. There are no stored copies to drift.
/// - The derivation needs no special case for a finding with no
///   entries, and reads correctly for one: `paths` is empty and
///   `byteSize` is the empty sum, zero. Zero here is an exact promise,
///   not a missing measurement. The task reclaims nothing because it
///   removes nothing, so nothing may read the zero as unknown,
///   substitute an estimate for it, or drop such a finding from a byte
///   total on the grounds that its size has not been computed yet.
/// - A finding with no entries counts as one item toward
///   `ScanCounters.itemCount` (C4): the finding is its own item.
///   Counting its entries instead would report five maintenance rows
///   as zero items.
/// - Byte totals derive from the finding's own entries, at scan, review and
///   plan time alike. A finding is self contained; no process wide cache
///   carries sizes from scan to plan. (Retired invariant: the s2b
///   ScannedAllocationCache, which existed only because paths carried no
///   sizes.)
/// - `explanation` is a plain sentence saying what this is and why it is
///   safe, reviewable or dangerous. Never empty.
/// - Preselection rules by module are binding:
///   Cleanup, Leftovers and Disk Map findings may be preselected only when
///   risk is `.safe`. Protection malware and adware findings are preselected
///   (quarantine is reversible). Privacy cleanup findings are never
///   preselected. Leftover sweep findings are never preselected.
/// - A finding that clears user visible data is never preselected,
///   whatever its risk. Concretely: `isPreselected` is false for any
///   finding whose selection would run a `MaintenanceTask` whose
///   `clearsUserVisibleData` is true (C7). Risk `.safe` describes what
///   the task does to the machine, not what the person loses, so safe
///   alone does not license preselection here and this rule overrides
///   it. Preselection is consent inferred from somebody having read the
///   row, and a preselected finding is swept into the Full Sweep
///   performance boost job (C29) and planned without its row ever being
///   opened, so the warning C23 requires before such a task runs would
///   never be seen. The rule is stated over the flag rather than over
///   today's task list, so a task added later inherits it with no
///   further amendment.
/// - For `duplicateSet` and `similarPhotoSet`, `keptPath` is a member of
///   `paths` and `entries.count >= 2`. The kept copy is shown before
///   anything moves and no plan ever targets it (see C21).
public struct Finding: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let sessionID: UUID
    public let category: FindingCategory
    public let entries: [PathEntry]
    public let risk: RiskLevel
    public let explanation: String
    public let isPreselected: Bool

    /// Derived: the entries' paths in entry order.
    public var paths: [AbsolutePath] { get }
    /// Derived: the sum of allocatedBytes over entries.
    public var byteSize: UInt64 { get }
}

/// One path a finding covers, with the allocated bytes its removal reclaims.
public struct PathEntry: Codable, Sendable, Equatable, Hashable {
    public let path: AbsolutePath
    public let allocatedBytes: UInt64
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
    // Leftovers
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
    // Disk Map
    case diskMapSelection
    // Performance
    case maintenanceTask(task: MaintenanceTask)
    case launchItem(item: LaunchItemID, scope: LaunchItem.Scope)
}
```

Migration note for the C5 amendment (s2d). Findings are session scoped:
nothing persists them across launches and no helper message carries one
(C30), so no stored data migrates. The cost is source level: the memberwise
initialiser loses `paths:` and `byteSize:` and gains `entries:`, and the
Codable encoding replaces the `paths` and `byteSize` keys with `entries`.
The s1a pins that change, for the test writer to update deliberately in
s2d:

- Tests/GleamCoreTests/DomainFixtures.swift, the `makeFinding` factory: its
  `paths:` and `byteSize:` parameters become `entries:`.
- Tests/GleamCoreTests/FindingTests.swift, "a finding round trips
  losslessly with every field populated".
- Tests/GleamCoreTests/FindingTests.swift, "a zero byte finding round trips
  losslessly".
- Tests/GleamCoreTests/FindingTests.swift, "a duplicate set finding keeps
  its kept path and members through coding".
- Tests/GleamCoreTests/FindingTests.swift, "a multi path finding preserves
  path order through coding".

Later suites construct findings through their own factories and break at
compile time, not behaviourally: CleanupEngineTests (makeCleanupFinding and
CleanupPlanTests), LeftoversEngineTests (makeLeftoversFinding, plus the hostile
findings built directly in SimilarPhotosKeptPathTests and
DuplicatesPlanInvariantTests), CleanupModuleTests
(CleanupModuleTestSupport). Their assertions stand; only construction
changes, and DuplicatesPlanInvariantTests' totalBytes assertion becomes
exact by construction rather than by cache.

### C6. OperationPlan

```swift
/// An ordered, executable description of destructive work, derived from the
/// user's reviewed selection. The only input the executor accepts.
///
/// Guarantees:
/// - `operations` preserves order and executes in order (C17).
/// - `totalBytes` equals the sum, over the operations that reclaim space,
///   of the `allocatedBytes` of the finding entry each operation targets
///   (C5). When plan time denylist filtering excludes an entry, its bytes
///   are excluded exactly; nothing is apportioned or estimated.
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
/// - The flag, not a list of task names, is what every rule about these
///   tasks is stated over, so a case added to this enum inherits those
///   rules by setting it. Two of them bind now: such a task is never
///   preselected (C5, C23) and never runs inside a Full Sweep (C29).
///   The warning is the point of the flag, and a task selected on
///   somebody's behalf is a task whose warning was never read.
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

Amended 2026-08-11 in s4a: `FileMetadataSnapshot` loses `ownerAccountName`.
Nothing can read it (C13 offers no owner accessor) and nothing can write it
(C14 offers no owner setter, and changing a file's owner to another account
needs root, which this store does not have), so the field could only ever hold
nil inside a struct documented as everything restore fidelity needs. A promise
nothing can keep is worse than a smaller promise, so the snapshot now carries
exactly what restore reinstates. The reversal is cheap on the day privileged
restore exists (GRAPH.md open question 11). The migration note after this
contract lists the source level costs.

Amended 2026-08-11 in s4e: `SafetyNetItem` gains `allocatedBytes`, the size the
payload occupied at the moment it was stored. C18 strips execute from every
payload it holds so a quarantined bundle cannot run, and on a real volume that
also removes traversal of a directory payload, so the store cannot read inside
its own payload afterwards. A size the store can never read again is a fact to
record once and not a value to recompute, so it is recorded here and the purge
total is the sum of these (C18). The migration note after this contract answers
the data question: nothing persisted, so nothing migrates.

```swift
/// One quarantined or archived file in the SafetyNet store.
///
/// Guarantees:
/// - `expiresAt` is exactly 30 days after `storedAt`. Expiry marks purge
///   eligibility only; nothing is ever purged without explicit confirmation
///   (C18).
/// - `metadata` snapshots exactly what restore reinstates and nothing more:
///   permission mode, extended attributes, creation and modification dates.
///   Every field in the snapshot is a field `restore` puts back (C18), so
///   restore fidelity is the whole struct rather than a subset somebody has
///   to keep track of.
/// - The owning account is deliberately absent. There is no way to read it
///   (C13) and no way to write it (C14, and changing a file's owner to
///   another account needs root), and no privileged restore path exists (C30
///   carries no restore request), so a snapshot field for it could only ever
///   be nil while sitting in a struct that claims to carry what restore
///   needs. A restore therefore lands the file owned by whoever ran it, which
///   for the user domain items this store holds is the account that owned it
///   before. Ownership joins the promise when privileged restore does, as a
///   reader, a setter and an optional field added in one change; old manifest
///   entries would decode as nil, so that is an added property rather than a
///   data migration.
/// - `allocatedBytes` is the allocated size the payload occupied at the moment
///   it was stored: the allocated size of a file, the whole subtree allocated
///   total of a directory. Allocated and never logical, C5's and C6's basis,
///   so one number means one thing across the app.
/// - It is a fact recorded once and never a value to recompute. Nothing may
///   re-derive it by reading the store, because the store deliberately makes
///   its own payloads unreadable: it strips execute from what it holds, and on
///   a real volume a directory without execute cannot be traversed (C13), so a
///   later reading of a directory payload returns an absence rather than the
///   truth. The measurement therefore happens at the origin path, before the
///   payload moves and before the strip, in the same pass that snapshots the
///   metadata above.
/// - There is no absent, partial or zero case to interpret. An item exists
///   only if its size was measured exactly; a payload the walk could not read
///   whole is refused rather than stored against a short figure, and C18 says
///   what `store` does when the measurement fails.
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
    /// The allocated bytes the payload occupied when it was stored, measured
    /// before the move and before the execute strip. Recorded, never
    /// recomputed: see the guarantees above and C18's purge total.
    public let allocatedBytes: UInt64
    public let storedAt: Date
    public let expiresAt: Date
    public var isRestored: Bool
}

public struct FileMetadataSnapshot: Codable, Sendable, Equatable {
    /// The mode read through `FileSystemReading.posixPermissions` (C13)
    /// before the file was moved into the store. Exact, because C18 restores
    /// exactly this.
    public let posixPermissions: UInt16
    public let extendedAttributes: [String: Data]
    public let created: Date?
    public let modified: Date?
}
```

Migration note for the C8 amendment (s4a). No shipped build has persisted this
type: the SafetyNet store does not exist yet, so no manifest anywhere holds an
owning account name and nothing migrates. The source level costs against the
tree as it stands:

- `FileMetadataSnapshot` loses the stored property and its initialiser
  parameter.
- The domain fixture drops its `ownerAccountName` default and the one snapshot
  built by hand in the C8 suite drops the argument. Neither asserts the field,
  so no assertion changes.

Migration note for the C8 amendment (s4e). This one is a genuine data question
rather than a formality, because SafetyNet items are meant to outlive a launch:
findings are session scoped and these are not. Checked on 2026-08-11 rather
than assumed, and the answer is that nothing migrates:

- No build has been distributed. The repository carries no tag and no release,
  so no copy of MacGleam exists anywhere that could have written a manifest.
- No `SafetyNetStore` is constructed outside the tests. The app hands the store
  directory to the helper as a removal destination and builds no store, so the
  only manifests that have ever existed were written by in memory file systems
  that lived for the length of a test.
- There is no store directory on the one machine that runs this app. Nothing
  sits under Application Support to read, convert or discard.

So `allocatedBytes` is not optional and carries no absent case. There is no old
entry that could decode as nil, and an optional that could only ever be nil in
a struct claiming to carry a fact is the exact shape the s4a amendment removed
from this same type. The source level costs:

- `SafetyNetItem` gains a stored property and an initialiser parameter, so
  every construction site moves: the store and the test fixtures today.
- The store measures the payload before it moves it, in the pass that already
  reads the mode, the extended attributes and the record.
- Nothing that reads an item has to handle a missing size, which is the point
  of not making it optional.

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

Amended 2026-08-11 in s4a: adds `posixPermissions(at:)`. The read side had no
way to observe a permission mode, while C18 requires the SafetyNet store to
snapshot one before it moves a file and to reinstate exactly that mode on
restore, so the store was contractually bound to restore a value it had no
contract visible way to read. `FileRecord.isExecutable` is not that value and
never was: it is a derived convenience for scanning that collapses every mode
sharing an execute bit onto one boolean, so 0o755 and 0o700 are the same
through it and setuid is invisible. Read only, so C13 stays a read only
protocol and the surface split holds. The migration note after this contract
lists the source level costs.

Amended 2026-08-11 in s4e: says what clearing a directory's execute bits does
to reading it, because the fake and the real disk disagreed about it and a
defect lived in the gap. C18 strips execute from every payload it stores so a
quarantined bundle cannot run; on a real volume that removes traversal, so
nothing inside the directory can be reached through it. The in memory file
system traversed such a directory happily, which is a fake looser than the disk
it stands in for, so the SafetyNet store sized its own directory payloads to
nothing on a real machine while every test stayed green. The behaviour is
stated here and the shared conformance suite gains the case; a fake looser than
reality is the failure mode that suite exists to prevent. The migration note
after this contract lists the source level costs.

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
/// - `posixPermissions` returns the twelve meaningful bits of the mode (the
///   three permission triples plus setuid, setgid and the sticky bit) and
///   never the file type bits. It is the observation side of C18's restore
///   fidelity promise, so it is exact by definition: a restore reinstates the
///   value this method returned, bit for bit. `FileRecord.isExecutable` is a
///   lossy derivation of the same source, kept because scanning asks only
///   whether a file can run, and it is never the basis of a restore.
/// - `posixPermissions` throws for the reasons `metadata` throws, `notFound`
///   for an absent path and `permissionDenied` for an unreadable parent, and
///   it never substitutes a default. A mode nobody could read is an error and
///   not 0o644, because a guessed mode written back onto somebody's file is a
///   silent permission change.
/// - A directory whose execute bits are all clear cannot be traversed, and
///   every implementation of this protocol answers that way. The directory
///   itself still reads: `metadata` and `posixPermissions` for the directory
///   answer as before, because reaching it needs permission on its parent and
///   not on itself. Nothing inside it reads: `metadata` and `posixPermissions`
///   for a path inside it throw `permissionDenied`, and `enumerate` rooted at
///   it yields no record for anything inside it, reporting it through
///   `inaccessible` per the clause above.
/// - A byte total summed over such an enumeration is an absence and never a
///   measurement. A caller that adds up `record` events and ignores
///   `inaccessible` reads an unreadable subtree as zero bytes, and zero bytes
///   looks exactly like a true small number. Anything computing a total over
///   an enumeration treats an `inaccessible` event as a failed measurement,
///   which is why C18 measures a payload before it strips it and never after.
/// - Both behaviours are carried by the shared conformance suite, anchored on
///   the disk: an in memory implementation that traverses a stripped directory
///   is wrong, however convenient it is to seed. This is the case that hid the
///   SafetyNet sizing defect of 2026-08-11 (GRAPH.md s4e).
/// - Order is not guaranteed and tests must not depend on it.
public protocol FileSystemReading: Sendable {
    func enumerate(
        root: AbsolutePath,
        options: EnumerationOptions
    ) -> AsyncThrowingStream<EnumerationEvent, Error>

    func metadata(at path: AbsolutePath) async throws -> FileRecord
    /// The file's permission mode, exact. The only way to observe what C18
    /// snapshots and restores.
    func posixPermissions(at path: AbsolutePath) async throws -> UInt16
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

Migration note for the C13 amendment (s4a). Adding a method to a protocol
breaks every conformance at compile time. Nothing is persisted and no format
changes.

- Both implementations already hold the value the method returns, so neither
  gains a lookup it was not already making.
- The in memory implementation's seeding surface needs a way to set a mode
  directly rather than deriving one from an executable flag. A mode the fake
  cannot hold is a mode no test can prove restored, which is the whole point
  of the addition.
- The shared conformance suite (s1b) gains the method, and the surface split
  test gains it on the reading side.

Migration note for the C13 amendment (s4e). The protocol gains no method,
nothing is persisted and no format changes. The costs are behavioural and they
all land on the fake:

- The in memory file system decides readability from the owner read bit alone,
  so a directory stripped of execute stays readable in it and its children come
  back regardless. Search permission has to join that decision for the fake to
  refuse what the disk refuses.
- The shared conformance suite (s1b) gains the case: clear execute from a
  directory holding a file, then assert the directory itself still reads, that
  a path inside it throws `permissionDenied`, and that an enumeration rooted at
  it yields no record from inside. The disk is the reference; the fake is the
  side that moves.
- Any seeding helper that sets a directory mode has to be able to express a
  directory without execute, or the case above cannot be written.

### C14. FileSystemMutating

Amended 2026-08-11 in s4a: adds `writeData(_:to:)`. C18 requires the SafetyNet
store to persist its manifest through the file system it was constructed with
rather than through a private path, and the write side offered no way to write
a byte anywhere: it could move, delete, create directories and set attributes
only. Without this method that requirement cannot be implemented and the
reinstall survival guarantee cannot be tested. The migration note after this
contract lists the source level costs.

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
/// - `writeData` replaces the whole contents of the destination, creating it
///   when absent, and it is atomic: a reader through C13 sees the previous
///   contents or the new contents and never a prefix of the new ones. On any
///   failure the previous contents are intact. This is what makes a manifest
///   safe to rewrite on every mutation (C18); a torn manifest is a lost
///   SafetyNet.
/// - `writeData` writes a file and only a file. It creates no intermediate
///   directories and throws `notFound` when the parent is missing, so a
///   mistyped path cannot quietly grow a tree. `createDirectory` stays the
///   only way a directory comes into existence.
/// - All methods throw typed `FileSystemError` values whose messages are
///   plain sentences.
public protocol FileSystemMutating: Sendable {
    func moveToTrash(_ path: AbsolutePath) async throws -> AbsolutePath
    func move(_ source: AbsolutePath, to destination: AbsolutePath) async throws
    func delete(_ path: AbsolutePath) async throws
    func createDirectory(at path: AbsolutePath) async throws
    /// Replaces the file's contents whole and atomically. The manifest of
    /// C18 is written with this and nothing else.
    func writeData(_ data: Data, to path: AbsolutePath) async throws
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

Migration note for the C14 amendment (s4a). Adding a method to a protocol
breaks every conformance at compile time. Nothing is persisted and no wire
format changes.

- The disk implementation writes to a temporary file in the destination's own
  directory and renames it into place, which is where the atomicity comes
  from. A temporary file on another volume would be a copy, not a rename, and
  would defeat the guarantee.
- The in memory implementation replaces the node's contents, creates the node
  when absent, and throws `notFound` when the parent directory is not there,
  so the fake refuses the same mistyped path the disk refuses. A fake looser
  than the real thing manufactures a green suite over a broken write.
- The helper's own implementation gains the method. It is reachable from no
  `HelperRequest`, so the message set does not change and
  `HelperContract.version` does not move.
- The shared conformance suite (s1b) gains it: write, read back through C13,
  overwrite, read back again, and a write into a missing directory that throws
  rather than creating one.

### C15. GleamEngine

```swift
/// The shape every engine shares. Scan streams findings; plan turns the
/// user's selection into an operation plan; execution belongs to the
/// executor. Engines never delete anything themselves.
///
/// Guarantees:
/// - `scan` is read only (it only holds `FileSystemReading`) and side effect
///   free. Running it twice against the same file system state yields the
///   same findings (identifiers aside), as far as the ordering clause below
///   allows: the entries are the same, their partition into findings is the
///   same only where the file system enumerates in the same order.
/// - `scan` emits `phase` transitions per C4 and `progress` counters that
///   are monotonic: filesSeen, itemCount and bytesReclaimable only ever
///   count up, and a finding's entries and bytes are added in the same step
///   that emits it, never before.
/// - Findings stream, and streaming here is a testable guarantee rather
///   than a description of intent. A finding is emitted the moment its
///   batch is complete, while the walk is still running; no engine holds a
///   category's matches until the walk ends, so the first finding never
///   waits on the last file. Concretely:
///   - Every finding a scan emits carries at most
///     `ScanStreamPolicy.maximumFindingEntries` entries, all of one
///     category. The cap is a contract guarantee, not an implementation
///     choice, and that is the point: it makes the DESIGN.md memory ceiling
///     a property of the design rather than of whichever disk the scan
///     happens to meet. The one exemption is set shaped categories, named
///     in C21.
///   - An open batch flushes when it reaches the cap, and every open batch
///     flushes when the walk ends. A category's first batch additionally
///     flushes at the first `ScanStreamPolicy.firstFindingCheckpointFiles`
///     boundary of `filesSeen` at or after its first match, however few
///     entries it holds, so a sparse category streams a row early instead
///     of waiting for the end of the walk. Later batches of that category
///     flush on the cap or at the end.
///   - So a scan that matches anything emits its first finding within
///     `firstFindingCheckpointFiles` files of its first match. Two things
///     follow that a test asserts directly: the first `.finding` event
///     arrives before the walk finishes, and the elapsed time to it is a
///     small fraction of the run rather than nearly all of it.
/// - Several findings may share one category. Consumers aggregate by
///   category: nothing may assume one finding per category, address a
///   category by taking the first of its findings, or read a category's
///   whole path list, file count or byte total off any single finding.
///   Those three are sums across the category's findings.
/// - Beyond its open batches a scan retains nothing proportional to files
///   seen: no full file list kept for a later matching pass, no per rule
///   match list held to the end. Live memory during a scan is bounded by
///   the number of open batches times the entry cap, which is what lets the
///   500 megabyte ceiling hold on a disk nobody has measured. The one
///   exemption is C21's content hashing.
/// - Entries within one finding are ordered by path. Which entries land in
///   which finding follows enumeration order. That is the honest cost of
///   streaming: a global sort over a category's whole match list cannot
///   survive without the buffer it was sorting, so the ordering promise
///   shrinks from "a category's paths are sorted" to "each finding's paths
///   are sorted".
/// - `scan` respects `context.hasFullDiskAccess`: when false the engine
///   scans what the user domain allows and reports what it skipped through
///   `ScanEvent.degraded`, so the honest banner has real content.
/// - `plan` includes only selected findings, expands each finding into one
///   operation per path (or into exactly one operation for a finding that
///   carries no path entries, C5 and C23), never emits an operation for a
///   denylisted path, and chooses operation kinds per module contract
///   (C20 to C29) and `context.settings.deletionMode`.
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
    /// The identifier of the OFFENDING FINDING, never of the session it
    /// came from. The error is named for the finding, and a caller
    /// reconciling a refusal needs to know which finding to drop, which
    /// the session identifier cannot tell them. Every engine carries the
    /// same identifier here; two carried the finding and one the session
    /// before this was written down, and nothing failed either way, which
    /// is exactly why it is stated rather than left to each engine.
    case findingFromDifferentSession(UUID)
    case keptCopyMissing(findingID: UUID)
}

/// The streaming shape every engine's scan obeys. Two numbers, both asserted
/// against by name, so a change to either is a contract change and not a
/// tuning pass.
public enum ScanStreamPolicy {
    /// The most entries any one finding a scan emits may carry.
    ///
    /// 2,000 is chosen from both ends. Memory: an entry is a path string plus
    /// a byte count, on the order of 128 bytes on a real tree, so one open
    /// batch costs roughly 256 kilobytes and a catalogue of 50 rules matching
    /// concurrently holds under 13 megabytes against a 500 megabyte ceiling.
    /// Review: 110,003 matching files become a little under sixty findings
    /// rather than five unopenable ones, and 2,000 rows is still a list a
    /// person can scroll. Ten times smaller turns one category into hundreds
    /// of groups; ten times larger puts a 1.25 megabyte buffer behind every
    /// rule and makes the flush granularity coarser than the review needs.
    public static let maximumFindingEntries = 2_000

    /// How often, in files enumerated, a category that has emitted nothing
    /// yet flushes its first partial batch.
    ///
    /// 1,000 files is tens of milliseconds of walking on any disk the app
    /// supports, which is what puts the first finding at the start of a scan
    /// rather than the end, and it is small enough that an ordinary fixture
    /// crosses it in a unit test rather than only in a performance gate.
    /// Only the first batch of a category uses it, so a scan of two million
    /// files does not emit two thousand fragments per category.
    public static let firstFindingCheckpointFiles: UInt64 = 1_000
}
```

Migration note for the C15 amendment (s2e). The measured problem: on a
120,000 file fixture the Cleanup scan collected every matching file, then
emitted 110,003 entries as five findings at 99.2 per cent of the run. The
scan itself was fast (2.03 seconds); the shape was structurally non
streaming, because a per rule aggregate cannot exist before the walk ends,
and at a real disk's match count the accumulated buffer is what would
eventually meet the 500 megabyte ceiling. Batching fixes both, and it costs
the following, stated rather than absorbed:

- `ScanCounters.findingCount` becomes `itemCount` and counts entries (C4),
  because a count of batches is a number that moves with a constant inside
  the engine.
- A category's totals are now sums. Any consumer reading a whole category
  off one finding is wrong, including the review screen's category header.
- Two scans of the same tree agree on entries and on each finding's internal
  order, not necessarily on where the batch boundaries fall.
- `duplicateSet` and `similarPhotoSet` are exempt from the cap and stay
  unbounded, and duplicate grouping still indexes across the whole walk
  (C21). Leftovers therefore has no memory guarantee by construction, and no
  gate covers it yet.

The existing test pins this breaks, for the test writer to update
deliberately in s2e. Three assertions become false, and the rest is a
rename that the compiler finds.

Behavioural, the assertion is wrong under the amended contract:

- Tests/CleanupEngineTests/CleanupScanMechanicsTests.swift, "the final
  counters equal the sum of the yielded findings":
  `final.findingCount == UInt32(outcome.findings.count)`. Becomes
  `final.itemCount` equals the entry count across the yielded findings. The
  old equality is false by design once a category spans several findings.
- Tests/LeftoversEngineTests/LeftoversScanMechanicsTests.swift, "counters only
  count up and the final counters equal the yielded findings": the same
  line, the same fix.
- Tests/CleanupEngineTests/CleanupCategoryDiscoveryTests.swift, "scanning
  the same file system state twice yields the same findings, identifiers
  aside": `Set(FindingShape)` equality, where `FindingShape` carries an
  ordered path array. It would still go green, because the JunkTree fixture
  never fills a batch and the in memory enumerator iterates one dictionary
  in one order within a process, so it would be passing for a reason the
  contract no longer promises. Restate it as what the amended contract does
  promise: equal entry unions, equal category multiset, and each finding's
  entries sorted by path.

Mechanical, from `ScanCounters.findingCount` becoming `itemCount`. Behaviour
under test is unchanged in every one:

- Tests/GleamCoreTests/DomainFixtures.swift, `makeScanCounters`: the
  `findingCount` parameter and its default.
- Tests/GleamCoreTests/ScanSessionTests.swift: "zero has every counter at
  zero", "round trips losslessly at the extremes", "increasing counters
  apply to a running session", "counters never decrease when a wholly lower
  update arrives", "no counter decreases under a mixed update", "no counter
  decreases across a sequence of updates".
- Tests/CleanupEngineTests/CleanupEngineFixtures.swift and
  Tests/LeftoversEngineTests/LeftoversEngineFixtures.swift,
  `countersAreMonotonic`.
- Tests/LeftoversEngineTests/SimilarPhotosSessionAndDeterminismTests.swift,
  "progress counters never decrease during a similar photos scan".
- Tests/LeftoversEngineTests/DuplicatesSessionMechanicsTests.swift,
  "duplicate findings ride the scan session with advancing phases and
  counters that only count up".
- Tests/CleanupModuleTests/CleanupModuleTestSupport.swift, `makeCounters`
  and the fake engine's per finding counter step. The third positional
  argument stops meaning findings and starts meaning items, so every call
  site still compiles while reading differently. Those sites, each of which
  wants its third argument reread rather than merely recompiled:
  CleanupModuleHappyPathTests "the first clean end to end: scan, review
  down to file paths, deselect, execute in trash mode, result,
  acknowledge" (including the exact
  `counters == makeCounters(10, 500, 1)` assertion) and "the next scan
  revises the hub estimate kept from the last result";
  CleanupModuleCancellationTests "cancelling a scan discards the partial
  findings and returns to idle" and "events from a cancelled scan never
  resurface"; CleanupModuleCommandTotalityTests "every command outside its
  table is the identity while scanning, including another startScan" and
  "startScan from reviewing discards the findings and selection and mints a
  fresh session"; CleanupModuleFailureTests "a failing scan stream lands
  idle with a plain sentence"; CleanupModuleDegradedNoticesTests "the next
  scan replaces the banner with the provider's current state".

New surface with no pin yet, so it is new test work rather than a break:
`CleanupReviewCategory.byteTotal` and `.pathCount` (C38), the entry cap and
the first finding checkpoint (C15), and a Cleanup fixture large enough to
cross both. Sources/MacGleam/CleanupScanProgressView.swift's counter line
says "N findings" today and must say items, which is the whole reason the
counter was renamed.

Not broken, and worth saying rather than leaving the test writer to check
for themselves. Every Cleanup engine assertion that unions a category's
paths or sums its bytes holds unchanged, because
Tests/CleanupEngineTests/CleanupEngineFixtures.swift's `ScanOutcome` already
returns arrays per category (`findings(in:)`, `trashBinFindings`,
`itemisedPaths`, `reclaimableByteTotal`) and every caller already unions or
sums across them: CleanupCategoryDiscoveryTests, CleanupDegradedModeTests,
CleanupRuleDrivenDiscoveryTests, CleanupScanDenylistTests and
CleanupPreselectionTests. The JunkTree fixture is a handful of files per
category, far under the cap and under one checkpoint, so batching never
splits anything there. Every Cleanup plan test constructs its findings
directly and is untouched. Every CleanupModule test already drives two
findings of one category (`cacheFinding` and `spareCacheFinding`) through
the model, so C38's amended wording describes behaviour those tests already
pin, including "the review groups findings by category in the order the
first of each streamed" and "toggling a category selects every member when
one is unselected, then deselects every member".

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

Amended 2026-08-11 in s3d: launch item operations are handed to C24 rather
than routed by path ownership, and they carry the plan and the operation as
attribution. One clause, below.

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
/// - `setLaunchItemEnabled` operations are the exception to that routing,
///   because a launch item names no path and path ownership has nothing to
///   decide from. The executor hands every one of them to
///   `LaunchItemManaging` (C24) carrying
///   `ChangeAttribution.operation(planID:operationID:)`, and that contract
///   routes by the item's scope. So the app has one privileged launch item
///   path rather than one for planned changes and another for a switch in
///   the interface, and the executor supplies the attribution because it is
///   the only thing that knows both identifiers. The helper still re checks
///   the domain itself (C31), so the two enforcement points stay
///   independent.
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

Amended 2026-08-11 in s4a: five points the suite could not test as written,
each a decision rather than a clarification. The expiry boundary is inclusive.
`PurgeConfirmation.byteTotal` gets a basis, the allocated bytes of the stored
payloads read through C13, which is C6's basis. A restored item is not purge
eligible and purging one is an error. `restoreGroup` on an identifier naming
nothing to restore is an error, and `SafetyNetError` gains `groupNotFound` for
it. The manifest is persisted through the injected file system as a
requirement of this contract, which is what makes the reinstall survival
clause testable and what `writeData` was added to C14 for. The store's
construction is stated with it, because every one of those clauses is about
the file system and the directory the store was handed. The migration note
after this contract lists the costs.

Amended 2026-08-11 in s4e: the purge total changes basis. It was the allocated
bytes of the stored payloads read through C13 when the confirmation is built,
which cannot be done, because this store strips execute from what it holds and
a directory without execute cannot be traversed on a real volume (C13). The
store could not read inside its own payload, so every uninstall archive, which
is every directory, hit the clause that says an unreadable payload fails the
purge. The total is now the sum of the sizes the items recorded when they were
stored (C8), measured before the strip, and purge reads no payload at all. The
strip stays: it is the containment, and the clause below says so plainly so
nobody reconciles the two by dropping it. The migration note after this
contract carries the data question and what the tree still owes.

```swift
/// The quarantine and archive store. Reversibility is the trust feature;
/// this contract is where it lives.
///
/// The store is constructed with a `FileSystem` (C13 and C14 together) and
/// one store directory. Everything it reads and writes, payloads and manifest
/// alike, goes through that file system and lives under that directory. It
/// holds no second path and no private handle.
///
/// Guarantees:
/// - `store` moves the file into the store (never copies and deletes as two
///   visible steps), snapshots metadata per C8, records the payload's
///   allocated size per C8, strips execute permissions on the stored payload
///   so quarantined malware cannot run, and preserves extended attributes for
///   restore fidelity. The snapshotted mode is what C13's `posixPermissions`
///   returns for the origin path before the move, read exactly. Stripping
///   execute changes the stored payload and never the snapshot, so the mode
///   restore puts back is the mode the file had.
/// - The size is measured before anything moves, and it is exact or nothing is
///   stored. `store` reads the payload's allocated size at the origin path, in
///   the same pass that snapshots its metadata and before the move and the
///   strip, and records it on the item (C8). If any part of the payload cannot
///   be read while measuring, `store` throws and moves nothing, so the file
///   stays where it was and the store never holds a payload whose size it had
///   to guess. A directory the walk could not enter is a failed measurement
///   and never a zero contribution: a subtree total that quietly skipped what
///   it could not read is a smaller number that looks exactly like a true one
///   (C13).
/// - The strip and the sizing pull against each other, and the strip wins.
///   Stripping execute from a directory removes traversal on a real volume
///   (C13), so the store cannot read inside a directory payload it holds, and
///   that is the containment rather than a side effect: the binary inside a
///   quarantined bundle cannot be reached through the directory that holds it.
///   The sizing moved to store time for that reason, and not the other way
///   round. Restoring execute to a payload, or skipping the strip for
///   directories, would make the purge arithmetic easy again and would put a
///   runnable quarantined bundle back on the disk, which is the one thing this
///   store exists to prevent, so nobody may reconcile the two that way.
///   Restore never noticed any of it, because a rename needs permission on the
///   parent directory and not on the directory being moved, which is why this
///   cost a defect: the in memory file system traversed a stripped directory
///   happily until C13's amendment, and the shared conformance suite now
///   carries the case that hid it.
/// - `restore` reinstates the payload at its origin path with its original
///   permission mode, extended attributes and dates. The mode is the
///   snapshotted value bit for bit, never one inferred from
///   `FileRecord.isExecutable`, which cannot tell 0o755 from 0o700. If the
///   origin path is now occupied it throws `originOccupied` and changes
///   nothing.
/// - `restoreGroup` restores every unrestored item of the group or throws
///   before moving anything if any origin is occupied; an uninstall restores
///   as one unit or not at all.
/// - `restoreGroup` on an identifier that names nothing to restore is an
///   error and never a quiet success: `groupNotFound` when no item carries
///   the identifier at all, `alreadyRestored` naming the group when the group
///   exists and every item in it has already been restored. A caller reads a
///   success as its uninstall being back on disk, so nothing may answer that
///   way without having moved a file.
/// - Retention: items become purge eligible 30 days after storage. Nothing
///   is purged automatically. `purge` requires a confirmation whose counts
///   match the items being purged, mirroring C6.
/// - The expiry boundary is inclusive. An item is purge eligible when the
///   instant asked about is at or after its `expiresAt`, so
///   `purgeEligibleItems(asOf:)` returns an item whose `expiresAt` equals
///   that instant exactly. `expiresAt` is the moment the 30 days are up, and
///   an item that is not yet expired at the instant it expires would make the
///   field name a lie. Eligibility is not removal: the confirmation still
///   gates the purge, so the inclusive edge costs nobody a file.
/// - `PurgeConfirmation.byteTotal` is the sum, over the items named in the
///   purge, of the sizes those items recorded when they were stored (C8).
///   Purge sizes nothing and reads no payload: the store measured what each
///   payload occupied as it took it in, and that recorded figure is what the
///   confirmation carries and what the purge reclaims. `itemCount` is the
///   number of identifiers in the purge. The basis is C6's `totalBytes` and
///   C5's entries, allocated never logical, so one number means one thing
///   across the app. Nothing is apportioned or estimated.
/// - A payload whose size is unknown still fails the purge and never counts as
///   zero, and the way a size can be unknown has changed. It cannot be missing
///   from a stored item: the size is recorded at store time, `allocatedBytes`
///   has no absent case, a payload that could not be measured exactly was
///   never stored, and no manifest predating the field exists anywhere,
///   because no build has been distributed and the type has never been
///   persisted outside a test (the migration note carries the evidence). What
///   remains is a manifest entry carrying no size at all, which fails to
///   decode, and an unreadable manifest is already an error: the store reports
///   it and purges nothing rather than confirming a total it invented. Zero is
///   only ever an exact promise here, never a measurement that did not happen.
/// - Both sides of the arithmetic read the same recorded facts. Whatever
///   builds the confirmation sums the `allocatedBytes` of the items `items`
///   listed it, and the store checks that sum against the same values, so the
///   confirmation is an agreement about a recorded fact rather than two
///   readings of a disk that may have changed between them.
/// - The recorded figure is the payload's allocation on the volume it came
///   from. Origin and store share the user's home volume on every path this
///   store is used on today, so the figure is the space the volume gets back.
///   Where one ever does not, the figure is still what the rest of the app
///   showed for that path, which is the consistency worth keeping over a
///   rounding difference nobody can observe.
/// - A restored item is outside the purge story entirely. Its payload has
///   already moved back to its origin, so the store holds nothing to reclaim
///   for it: `purgeEligibleItems` never returns one whatever its dates say,
///   and `purge` throws `alreadyRestored` naming the first restored
///   identifier and changes nothing. A silent success would let a caller
///   believe it reclaimed space that was not there, and there is no honest
///   byte total it could have been shown to confirm.
/// - `purge` validates in a fixed order and changes nothing until all of it
///   passes: every identifier exists (`itemNotFound`), none is restored
///   (`alreadyRestored`), then the confirmation matches
///   (`confirmationMismatch`). The counts come last because a total computed
///   over a set the store has already rejected means nothing, and a caller
///   told its arithmetic was wrong would go and correct the arithmetic.
/// - `SafetyNetError`'s identifier payloads name an item, except in the two
///   cases that are about a group, `groupNotFound` and an `alreadyRestored`
///   thrown by `restoreGroup`, where they name the group. Every throw site is
///   named in the guarantee that raises it, so which one a case carries is
///   never left to be inferred.
/// - Reinstall survival: the manifest and payloads live under the store
///   directory, which the app locates in Application Support so it outlives
///   the application bundle. Deleting and reinstalling the app then listing
///   items returns the same items. This is a tested behaviour, not a hope.
/// - The manifest is persisted through the injected file system, at a path
///   inside the store directory. That is a requirement of this contract and
///   not an implementation detail, because it is what makes the clause above
///   testable: a second store constructed over the same file system and the
///   same directory lists everything the first one wrote, and a deleted and
///   reinstalled app is exactly that. A store keeping its manifest somewhere
///   the injected file system cannot see would satisfy every other clause
///   here, lose a user's quarantine on reinstall, and no test could say so.
/// - The manifest is written whole with C14's `writeData`, atomically, after
///   every mutation that changes it, so an interrupted store, restore or
///   purge leaves a readable manifest describing either the state before it
///   or the state after it.
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
    /// The number of identifiers in the purge.
    public let itemCount: UInt32
    /// The allocated bytes the purge reclaims, on C5's and C6's basis: the
    /// sum of the `allocatedBytes` the purged items recorded when they were
    /// stored (C8). Nothing re-reads the store to size a payload. See the
    /// guarantees above.
    public let byteTotal: UInt64
    public let confirmedAt: Date
}

public enum SafetyNetError: Error, Sendable, Equatable {
    case originOccupied(AbsolutePath)
    case itemNotFound(UUID)
    /// No item carries this group identifier. Names a group.
    case groupNotFound(UUID)
    /// The item has already been restored, or, from `restoreGroup`, every
    /// item of the group has. Names an item in the first case and a group in
    /// the second; the guarantee that raises it says which.
    case alreadyRestored(UUID)
    case confirmationMismatch
    case denylistedPath(AbsolutePath)
}
```

Migration note for the C18 amendment (s4a). No implementation of
`SafetyNetStoring` exists and no manifest has ever been written, so nothing
migrates. The costs land in the slice being written now:

- `SafetyNetError` gains a case, so an exhaustive switch over it gains an arm.
  None exists yet outside the s4a suite.
- The store's construction takes a store directory as well as a file system.
  A test supplies a temporary directory inside the in memory file system;
  Application Support is where the app supplies it, not where the contract
  puts it.
- The suite's expiry cases sit one second either side of `expiresAt`, so they
  assert neither boundary. The inclusive instant needs a case of its own
  (GRAPH.md s4a).

Migration note for the C18 amendment (s4e). Nothing migrates, and that was
checked rather than assumed: no build has been distributed, no `SafetyNetStore`
is constructed outside the tests, and no store directory exists under
Application Support, so no manifest written by an older version can be waiting
anywhere. C8's migration note carries the evidence in full. The costs land in
the slice being written now:

- `store` measures before it moves, and a measurement that could not read the
  whole payload fails the store rather than recording a short figure. The
  subtree walk that skipped what it could not read has to treat that as a
  failure (C13).
- `purge` stops touching the file system to size anything. It sums recorded
  sizes, so the store's private payload sizing helper goes.
- Whatever builds a `PurgeConfirmation` sums the recorded sizes of the items it
  was listed, rather than asking the disk.

What this amendment does and does not close. The KNOWN DEFECT annotation that
sat on the byte total clause is gone, because the contract no longer asks for a
reading the disk cannot give. The tree still owes the work: as of this
amendment the merged store sizes payloads at purge time by reading them,
`SafetyNetItem` carries no recorded size, and the in memory file system still
traverses a stripped directory, so a real purge of a real uninstall archive
would still report nothing reclaimed. Closed in the contract, open in the code
until slice s4e lands (GRAPH.md s4e).

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
/// - Emits only Cleanup categories from C5. Itemisation is per finding
///   entry, not per category: every entry names a real file path the user
///   can inspect, never a directory total. A category is not one finding.
///   A rule's matches stream as a series of capped findings (C15), so a
///   category's paths, file count and byte total are sums across its
///   findings, and a scan that used to end with one finding per rule now
///   emits many while it runs. What that changes, on the s2e fixture of
///   120,000 files with 110,003 matches across five categories: the
///   measured behaviour before was five findings arriving at 99.2 per cent
///   of a 2.03 second scan; the shape the contract now requires is a little
///   under sixty findings, arithmetic from the cap rather than a
///   measurement, the first of them within
///   `ScanStreamPolicy.firstFindingCheckpointFiles` files of the first
///   match rather than at the end of the walk.
/// - Preselection follows the rules catalogue: a finding is preselected
///   only when its rule says preselectable and its risk is safe. Nothing
///   risky is ever preselected, whatever the catalogue says (the engine
///   enforces the conjunction).
/// - Mail attachment findings cover local copies only; removing one never
///   touches server state, and the explanation says so.
/// - Trash bin findings are per volume so the review shows where each bin
///   lives, and batching never loses that: the volume is part of the
///   category (C5 `trashBin(volume:)`), so every batch of a bin carries its
///   own volume however many batches the bin takes.
/// - `plan` maps findings to `moveToTrash` when settings.deletionMode is
///   trash, `deletePermanently` when permanent. Trash bin contents always
///   plan as `deletePermanently` (moving trash to trash is meaningless),
///   and this is the one Cleanup case allowed to do so; it still requires
///   the confirmation from C6.
/// - Performance: the full scan of a typical 512 gigabyte system disk
///   completes in under 60 seconds on Apple silicon; the first finding
///   arrives within two seconds of the scan starting and within the first
///   half of the run; resident memory stays under the DESIGN.md ceiling
///   throughout. All three are enforced by gates against a generated
///   fixture tree in M2 (s2e). The middle one is C15's streaming clause
///   stated as a number, and it is the one that catches the regression this
///   engine actually had: an engine that buffers and then emits puts its
///   first finding at essentially the whole of the run, so the absolute two
///   second bound alone would pass it on fast hardware.
public struct CleanupEngine: GleamEngine { /* module == .cleanup */ }
```

### C21. LeftoversEngine

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
///   Finding with category `duplicateSet(keptPath:)`, whatever its size.
/// - Set shaped categories are the one exemption from C15's entry cap.
///   `duplicateSet` and `similarPhotoSet` are never split, because a split
///   would break C5's guarantee that the kept path is a member of the
///   finding's own paths, and would leave members sitting in a finding
///   whose category names a kept copy it does not contain. The cost is
///   stated rather than hidden: a pathological set, thousands of copies of
///   one file, is the one finding in MacGleam whose size is not bounded by
///   construction, and duplicate grouping is also the one scan that must
///   index candidates across the whole walk, so C15's "retains nothing
///   proportional to files seen" does not hold here either. Neither is
///   covered by the s2e gates, which cover Cleanup and Disk Map. A
///   Leftovers performance gate is separate work and these two are what it
///   should measure.
/// - Large file, old file and downloads triage findings carry one entry
///   each, far under the cap, and already stream as the walk runs. C15's
///   rule that a category spans many findings has always been true here:
///   `largeFile` is one finding per file, so a consumer assuming one
///   finding per category was wrong before batching existed.
/// - Keep one invariant: `plan` never emits an operation targeting the kept
///   path of any set, and throws `PlanningError.keptCopyMissing` if a
///   selection somehow excludes it. At least one copy always survives, by
///   construction, and a test attacks this with hostile selections.
/// - Member byte sizes ride on the finding itself: a duplicate or similar
///   photo set finding carries one entry per member with that member's
///   allocated bytes (C5). Plan totals for any selection are exact sums of
///   the entries its operations target; the kept path's entry is never
///   counted; no scan state outlives the finding.
/// - Similar photo sets carry the same kept path mechanics. Similarity
///   grouping is implementation; the contract is only that every member is
///   an image file and sets never overlap.
/// - Old file findings use last opened date where the volume records it,
///   falling back to modification date, and the explanation names which.
public struct LeftoversEngine: GleamEngine { /* module == .leftovers */ }
```

### C22. DiskMapEngine

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
/// - Mapping a full volume completes in under 30 seconds on Apple silicon,
///   and the first node arrives within two seconds of the map starting and
///   within the first half of the run. Enforced by gates in M2 (s2e).
/// - Selecting nodes for deletion produces ordinary Findings with category
///   `diskMapSelection` and risk `review` (never preselected), one entry
///   per selected node. The category therefore spans as many findings as
///   the user selected nodes, and its totals are sums across them (C15);
///   each finding is already far under the entry cap, so nothing here
///   batches. Then the standard `plan` path applies: Trash by default,
///   identical to Cleanup.
/// - The map never offers selection of a denylisted path; such nodes render
///   but are not selectable.
public struct DiskMapEngine: GleamEngine {
    /// In addition to GleamEngine.scan, the streaming map surface:
    public func map(
        volume: AbsolutePath,
        context: ScanContext
    ) -> AsyncThrowingStream<DiskMapUpdate, Error>
}

public enum DiskMapUpdate: Sendable, Equatable {
    case node(DiskMapNode)
    case sizeRevision(path: AbsolutePath, subtreeBytes: UInt64)
    case completed
}

public struct DiskMapNode: Sendable, Equatable {
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
/// - A Performance finding never names a path. Every finding this
///   engine emits carries no path entries (C5): a maintenance finding
///   names a task, a login item finding names a registration. So there
///   is nothing for a plan builder to turn into a removal, which is
///   what makes the clause above structural rather than a promise, and
///   `plan` emits one operation per selected finding rather than one
///   per path (C15).
/// - A maintenance task whose `clearsUserVisibleData` is true (C7) is
///   never preselected, whatever its risk. Maintenance findings sit at
///   risk `.safe`, which would otherwise permit preselection; this rule
///   overrides it (C5). A preselected finding is swept into the Full
///   Sweep performance boost job (C29) and planned without its row
///   being opened, so the person would never see the warning the clause
///   below requires. The rule binds any task that clears user visible
///   data, not only today's Domain Name System cache flush.
/// - Tasks that clear user visible data are flagged per C7 and the finding
///   explanation says what will be cleared before the user runs it.
public struct PerformanceEngine: GleamEngine { /* module == .performance */ }
```

### C24. LaunchItemManaging

Amended 2026-08-11 in s3d, the slice that implements it. Three changes, all
of them closing a gap the contract described but gave nothing to stand on.
Attribution: `setEnabled` requires a `ChangeAttribution`, so a change that
reaches the privileged boundary can always be tied back to what asked for it,
including a switch a person flipped outside any plan. Boundaries: the
inventory source, the two changing sides and the store of prior state are
declared rather than referred to. Errors: `LaunchItemError` is declared, so
the `itemNotFound` this contract has always named has a type. The migration
note after the contract lists the source level costs, including the
`FindingCategory` case added by C5 in the same slice.

```swift
/// Inventory and state changes for login and background items: SMAppService
/// registrations and legacy launch agents and daemons, per owning app.
///
/// Guarantees:
/// - `list` attributes every item to its owning app where the owner is
///   resolvable, with the item's kind, scope and current enabled state, and
///   the path that can be revealed in Finder.
/// - `LaunchItemID.value` is opaque. It is built from the label and the
///   scope so that it is stable across launches, and nothing anywhere takes
///   it apart again. Everything that needs the scope reads it from the
///   `LaunchItem`, or from the `launchItem` finding category that carries it
///   (C5), which is why that category carries a scope that looks redundant
///   beside the identifier and is not.
/// - `setEnabled` disables or enables, never deletes, and returns a
///   `LaunchItemChange` recording the prior state. The app persists these
///   records through `LaunchItemChangeRecording` so re enabling is one click
///   and survives relaunch.
/// - User scope items change in process; system scope items route through
///   the helper (C30). The caller does not choose; the implementation routes
///   by scope, and it reads the scope from the current inventory rather than
///   from the plan or the view that asked, so a stale caller cannot decide
///   which side of the privileged boundary a change lands on.
/// - Every change is attributable, and the type system is what makes it so.
///   `setEnabled` requires a `ChangeAttribution`; the parameter carries no
///   default and the type has no case meaning none, so the unattributed call
///   does not compile. The manager cannot fill it in on the caller's behalf,
///   because attribution is knowledge only the caller has. The caller cannot
///   decide it is unnecessary, because the caller does not know the item's
///   scope and therefore cannot know whether this change is about to cross
///   the privileged boundary.
/// - The two callers, and what each supplies. The executor (C17) supplies
///   `.operation(planID:operationID:)` for a change it is running as part of
///   a plan, because it is the only thing that knows both identifiers. The
///   Performance module supplies `.directChange(changeID:)` for a switch a
///   person flipped in the interface, which belongs to no plan. A direct
///   change is attributable to itself: the identifier is minted at the
///   moment of the change and names nothing else, and no plan is fabricated
///   to carry it. A synthetic single operation plan would put an identifier
///   in the helper's log that matches no plan the app ever built, which is a
///   worse answer than no attribution at all, because it reconciles to
///   something that did not happen.
/// - On the privileged path the attribution travels to the helper as C30's
///   `setLaunchItemEnabled` attribution, and the helper echoes it back as
///   the reply's `correlationID`. So every refusal reconciles with the thing
///   that caused it: a plan operation for a planned change, the change
///   itself for a direct one.
/// - Changing an item that no longer exists throws `itemNotFound` and
///   changes nothing. On the user scope path that is the manager failing to
///   find the item in the current inventory before it attempts anything. On
///   the system scope path it is the helper refusing `malformedRequest`
///   because it cannot resolve the item (C31); this contract maps that
///   refusal onto `itemNotFound`, so the caller is told the item is gone
///   rather than shown a protocol error.
/// - Every other helper refusal (denylisted, notSystemDomain,
///   versionMismatch, identityRejected) surfaces as `changeRefused` with a
///   plain sentence. Refusal reasons are helper vocabulary and stay in
///   GleamHelperCore; nothing in GleamCore imports them, which is also why
///   `LaunchItemError` names none of them.
///
/// Boundaries. This contract described behaviour with nothing to hang it on:
/// it named an inventory, a privileged side and a store of records without
/// declaring any of them. All four are declared below and the manager holds
/// them; it discovers, mutates and stores nothing itself.
/// `LaunchItemEnumerating` is the inventory source.
/// `UserScopeLaunchItemChanging` and `PrivilegedLaunchItemChanging` are the
/// two sides the manager routes between. `LaunchItemChangeRecording` is the
/// store of prior state. The two changing sides are separate protocols
/// rather than one protocol with a scope property, so a manager built with
/// two user scope sides does not compile, and the routing test reads as two
/// test doubles, one of which must stay untouched.
///
/// Types landing ahead of this slice: `LaunchItemID` and `LaunchItemChange`
/// are plain value types carrying no behaviour, and both ship into GleamCore
/// before this contract is implemented, because contracts built earlier name
/// them. `LaunchItemID` landed with the domain model, which needed it for
/// C7's `Operation.Kind`. `LaunchItemChange` lands with s3a, which needs it
/// for C30's `launchItemChanged` reply: it arrives exactly as declared below,
/// Codable, Sendable and Equatable, carrying `item`, `previousEnabled`,
/// `newEnabled` and `changedAt` and nothing else. Every guarantee about how a
/// change is produced, recorded, persisted or replayed belongs to this
/// contract's slice; s3a adds none of it and asserts none of it beyond the
/// round trip through the wire encoding.
///
/// `ChangeAttribution` goes the other way. It is declared here because this
/// is the contract that needs it, and it lands in GleamCore during this
/// slice, below C30 in the package graph, so GleamHelperCore can carry it on
/// the wire. GleamCore does not import GleamHelperCore and this does not
/// change that.
public protocol LaunchItemManaging: Sendable {
    func list() async throws -> [LaunchItem]
    func setEnabled(
        _ enabled: Bool,
        item: LaunchItemID,
        attribution: ChangeAttribution
    ) async throws -> LaunchItemChange
}

/// What a change is attributable to. There is no case meaning unknown and no
/// optional field: which of the two it is, is a fact about how the change was
/// asked for, recorded at that moment, never inferred afterwards.
public enum ChangeAttribution: Codable, Sendable, Equatable, Hashable {
    /// One operation of a plan the executor is running (C6, C17).
    case operation(planID: UUID, operationID: UUID)
    /// One change a person made directly in the interface, outside any plan.
    /// `changeID` is minted at the moment of the change and identifies
    /// nothing else: no plan carries it and no `ExecutionReport` names it.
    case directChange(changeID: UUID)

    /// The identifier a reply echoes to tie itself to the request that caused
    /// it: the operation identifier for a plan operation, the change
    /// identifier for a direct change. Never nil, so reconciliation needs no
    /// special case for either kind.
    public var correlationID: UUID { get }
}

public struct LaunchItemID: Codable, Sendable, Hashable {
    public let value: String   // stable identifier: label plus scope, opaque
}

public struct LaunchItem: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, Equatable, Hashable {
        case appService          // SMAppService registration
        case legacyLaunchAgent
        case legacyLaunchDaemon
    }
    /// Hashable because `FindingCategory` is Hashable and now carries a scope
    /// (C5).
    public enum Scope: String, Codable, Sendable, Equatable, Hashable {
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

/// The inventory source. Reads registrations and their current state and
/// mutates nothing. The manager's `list` is this plus owner resolution.
public protocol LaunchItemEnumerating: Sendable {
    func enumerate() async throws -> [LaunchItem]
}

/// The in process side, for user scope items only. It takes no attribution:
/// nothing privileged happens here, no log outside this process records it,
/// and the change it returns is recorded by the manager either way. The
/// attribution the manager was given is dropped on this path deliberately,
/// which is why it is absent from the signature rather than ignored in the
/// body.
public protocol UserScopeLaunchItemChanging: Sendable {
    func setEnabled(
        _ enabled: Bool,
        item: LaunchItem
    ) async throws -> LaunchItemChange
}

/// The privileged side, for system scope items only. Sends C30's
/// `setLaunchItemEnabled` to the helper and maps the reply onto this
/// contract's errors. It is the only place in the app that can change a
/// system scope registration, and it cannot build the request without an
/// attribution because the request case requires one.
public protocol PrivilegedLaunchItemChanging: Sendable {
    func setEnabled(
        _ enabled: Bool,
        item: LaunchItem,
        attribution: ChangeAttribution
    ) async throws -> LaunchItemChange
}

/// The store of prior state. Lives in Application Support beside the
/// SafetyNet manifest, so it survives relaunch, and survives reinstall the
/// same way the manifest does (C18, C34).
///
/// Guarantees:
/// - `record` is append only. Nothing is deleted or rewritten, so a change a
///   person later reverses leaves both records.
/// - `changes` returns the most recent record per item, which is what one
///   click re enabling needs: a row can say what MacGleam changed and when
///   without reading a history.
/// - A missing or corrupt store reads as empty and never as a crash. Losing
///   the records loses the convenience, never the items, which the inventory
///   always reports live.
public protocol LaunchItemChangeRecording: Sendable {
    func record(_ change: LaunchItemChange) async throws
    func changes() async throws -> [LaunchItemID: LaunchItemChange]
}

public enum LaunchItemError: Error, Sendable, Equatable {
    /// The item is not on the machine any more. On the system scope path this
    /// is the helper's `malformedRequest` mapped on.
    case itemNotFound(LaunchItemID)
    /// The privileged side refused for a reason that is not the item being
    /// gone. A plain sentence that names no path.
    case changeRefused(reason: String)
    /// The helper is unreachable or not registered yet (C17).
    case privilegedChangeUnavailable(reason: String)
    /// The change reached the machine and did not take effect.
    case changeFailed(reason: String)
}
```

Migration note for the C24 amendment (s3d). Three source level costs, none
behavioural, all landing in this slice.

- `FindingCategory` gains `launchItem` (C5), so every exhaustive switch over
  it stops compiling until the new case is handled. That is a mechanical
  break and it is expected: whoever hits it has not found a defect, and the
  fix is to write the arm. Against the tree as it stands the break does not
  bite, because the three switch sites over `FindingCategory` outside
  GleamCore all carry a `default`: `CleanupEngine.isCleanupCategory`,
  `LeftoversEngine`'s plan builder, and `FindingCategory.cleanupTitle` in
  `CleanupReviewView`. So the thing to check at those sites is the quieter
  one. A launch item finding falls into the default arm and renders under the
  generic title, which is right for a cleanup review screen it never reaches,
  and wrong anywhere a `default` was standing in for a case nobody had
  written yet.
- `LaunchItem.Scope` gains `Hashable`, because `FindingCategory` is Hashable
  and now carries a scope. `Kind` gains it for symmetry. `LaunchItemID` is
  already Hashable.
- `HelperContract.version` goes from 1 to 2 with C30's attribution change, in
  the same commit, as C30 requires.

### C25. ProcessMonitoring

Amended 2026-08-11 in s3e, the slice that implements it. Five changes, every
one of them a contract change rather than an implementation choice, plus the
safety property of the slice written out properly instead of left inside a
sentence about an API taking an identifier and a name together.

Confirmation. `quit` takes a `QuitConfirmation` value rather than a process
identifier, a name and a `force` flag. A flag makes force quitting an
escalation of the ordinary confirmation: the same call, the same data, one
argument flipped, so a person could arrive at a force quit by pressing the
same control twice. The value has two initialisers, no public memberwise
initialiser and no setter on its kind, so there is no path from one to the
other and a force quit without its own confirmation does not compile.

Where the name is read. On the signalling boundary, `ProcessTerminating`, not
on the listing boundary. A name read anywhere else is already stale by the
time the signal goes out, which is the entire defect this slice exists to
prevent. Both the name read and the terminate land on the same boundary, so
"checked, then killed" is an ordering a test can assert rather than two
unrelated calls whose sequence nothing records.

Cadence. An injected boundary yielding a tick per sample due, rather than a
timer inside the monitor, because otherwise a test has to sleep, and a
sleeping test is a wall clock by another name.

Ordering. Ties break by the lower process identifier. Heaviest first by memory
footprint and nothing further leaves the order non total, so equal rows swap
position between ticks and the list becomes something nobody can aim a pointer
at.

A refused snapshot. Skipped, not repeated. The stream carries no error, so the
only other answer is to present the previous list again, which shows a stale
list as though it were current.

Nothing implements this contract today, in Sources or in tests, so the
amendment costs no migration. Every declaration below lands in this slice.

```swift
/// The live memory and processor view, and confirmed process quit.
///
/// Guarantees:
/// - `samples` streams snapshots sorted heaviest first (by memory footprint)
///   at a steady cadence suitable for a live view; the stream never blocks
///   the main actor. Nothing is read before the first tick, one snapshot is
///   taken per tick, and the stream finishes when the cadence does, so a view
///   a person has closed leaves nothing sampling behind it.
/// - The ordering is total: heaviest first by memory footprint, and equal
///   footprints order by the lower process identifier. The tie rule is not a
///   tidy up. Two processes of equal footprint under a partial order may swap
///   places on every tick, and a row that moves while somebody is reaching
///   for it is a row nobody can aim a pointer at, which matters most for the
///   one control on it that ends a process. The order is therefore a function
///   of the snapshot alone: the same processes reported in any order produce
///   the same order on screen, whatever order the machine happened to answer
///   in. Sorting drops nothing, invents nothing and edits no field.
/// - Monitoring never quits, signals or otherwise affects any process. The
///   two boundaries are what make that structural rather than a promise the
///   sampling loop keeps: `ProcessListing` declares one method and it reads,
///   so the sampler holds a type with no way to end anything. A whole
///   sampling run sends no signal and does not even ask who holds an
///   identifier.
/// - A snapshot the machine refuses is skipped, and the view carries on. The
///   stream carries no error case, so a read that fails cannot be reported as
///   one; the only two answers left are to skip the sample or to emit the
///   previous list again, and emitting it again presents a stale list as
///   though it were current, which is the one answer a live view may not
///   give. The tick is still spent: the refused read was attempted, not
///   skipped over, and the next tick reads again.
/// - A machine with nothing running yields an empty snapshot, never no
///   snapshot. Showing nothing is an answer; showing the last list is not.
/// - The live view is not a scan (C23) and the monitor is not an engine: it
///   conforms to neither `GleamEngine` nor `PlanExecuting`, so nothing that
///   routes engines, Full Sweep included (C29), can route it. A
///   `ProcessSample` carries the five fields below and no path, so there is
///   nothing in the live view for a plan builder to turn into a removal,
///   which is C5's pathless rule holding here by the shape of the data rather
///   than by a rule somebody has to keep obeying.
/// - `quit` takes a `QuitConfirmation` and nothing else. The value is the
///   evidence that a person was shown a named process and answered; there is
///   no overload that takes a bare identifier, so a quit with no confirmation
///   behind it cannot be written down. A quit confirmation produces the
///   graceful signal and only that: no number of quit confirmations, in any
///   order, over any process, ever produces a force signal. A force quit is a
///   second, separate confirmation with its own value and its own full check,
///   never a shortcut earned by the first.
///
/// A recycled process identifier kills nothing. This is the safety property of
/// the slice, and it is why `quit` takes a name at all.
///
/// An operating system hands a process identifier back out once the process
/// holding it has gone, and a live view is a list of numbers a person read a
/// moment ago. Between the row being drawn and the confirmation being
/// answered, the number under `Xcode` can become somebody else's compile,
/// somebody else's export, somebody else's unsaved work. The monitor holds a
/// number; the person confirmed a name. So a monitor holding a stale
/// identifier can name one process on screen and signal a different one that
/// inherited the number.
///
/// - The confirmation carries the name the row was shown under, recorded at
///   the moment the question was asked.
/// - That name is read again from `ProcessTerminating` immediately before the
///   signal, and from nowhere else. Not from the sample the row was drawn
///   from, not from the monitor's last snapshot, not from a cache: a monitor
///   that trusts its own most recent listing satisfies every example and
///   fails the one case this exists for.
/// - Any difference aborts and signals nothing. `nameMismatch` carries both
///   names, because a person who confirmed one thing and nearly reached
///   another is owed both. There is no second attempt at a lower level: one
///   look, one refusal.
/// - Comparison is exact. Case, surrounding whitespace and prefixes are all
///   mismatches, and an empty confirmed name matches nothing, because a
///   confirmation with no name in it was never shown to anybody. A signal is
///   sent exactly when the confirmed name equals the live name, and the
///   process survives every other pairing.
/// - The check fails closed. A name the machine will not give up is
///   `notPermitted` and signals nothing: a check that could not be made is
///   not a check that passed. An identifier nothing holds is
///   `processNotFound` and signals nothing, whatever name was confirmed
///   against it; a missing name is never read as no objection.
/// - The name confirms the target; the identifier is the target. Two
///   processes sharing a name are two processes, and quitting one leaves the
///   other running.
///
/// What this does not guarantee. The window between the check and the signal
/// belongs to the operating system, and nothing can close it from here. The
/// name read and the terminate are two calls on one boundary and no
/// arrangement of them from this side makes them one: a process can end, and
/// its identifier be handed on, in between. The signalling boundary takes a
/// number, not a name, so there is nothing to hand it that would carry the
/// check with it. What is promised is that a mismatch which is visible at the
/// moment of the signal is refused and nothing is signalled. What is not
/// promised is that the race is impossible. Narrowing the window further
/// would be a change to what `ProcessTerminating` can express, not a stronger
/// reading of this clause.
///
/// Boundaries. The monitor reads nothing, signals nothing and keeps no time of
/// its own; it holds the three protocols below and is built from them. Reading
/// and signalling are two protocols rather than one with a terminate method,
/// so a sampler cannot signal by construction, and the name lookup sits with
/// the signal rather than with the listing so the check cannot be satisfied by
/// stale knowledge.
public protocol ProcessMonitoring: Sendable {
    func samples() -> AsyncStream<[ProcessSample]>
    func quit(_ confirmation: QuitConfirmation) async throws
}

/// What a person answered, and the only thing `quit` accepts. It carries the
/// identifier of the row, the name that row was shown under, and which of the
/// two questions was answered.
///
/// There is no path from one kind to the other. The memberwise initialiser is
/// not public, `kind` has no setter, and the two initialisers below are the
/// only ways to build one, so a force quit that nobody confirmed as a force
/// quit does not compile. That is a stronger statement than a rule about how
/// to call the API: it is the absence of any call that could express the
/// thing. A `force` flag would have made the two answers one value with a
/// switch on it, and one press could then stand for either.
///
/// Not `Decodable`, and deliberately. A confirmation is a fact about something
/// a person did a moment ago. One that could be revived from bytes could be
/// stored, replayed, or written by anything that can write a file, and the
/// force quit of an application would be one restore away from happening with
/// nobody having answered anything. A confirmation is minted where it is
/// answered, never restored.
public struct QuitConfirmation: Sendable, Equatable {
    /// Two ways to confirm and no third. A third case would be a door nobody
    /// has had to write a question for.
    public enum Kind: Sendable, Equatable, CaseIterable {
        case quit
        case forceQuit
    }

    public let processIdentifier: Int32
    /// The name the row was shown under when the question was asked. This is
    /// what the live name is checked against, exactly.
    public let name: String
    public let kind: Kind

    /// Ask the process to end.
    public init(quitOf processIdentifier: Int32, named name: String)
    /// Force the process to end. Its own question, answered on its own.
    public init(forceQuitOf processIdentifier: Int32, named name: String)
}

public struct ProcessSample: Sendable, Equatable {
    public let processIdentifier: Int32
    public let name: String
    public let bundleID: String?
    public let memoryFootprintBytes: UInt64
    public let processorLoadFraction: Double   // 0.0 to 1.0 per core aggregate
}

/// The reading side. Answers what is running and affects nothing. This is the
/// only boundary the sampling loop holds, which is what makes "monitoring
/// never signals" a property of a type rather than a habit.
public protocol ProcessListing: Sendable {
    func snapshot() async throws -> [ProcessSample]
}

/// The signalling side, and the only side that can say who holds an identifier
/// right now.
///
/// The name lookup lives here rather than on the listing side deliberately. A
/// name read anywhere else is already stale by the time the signal goes out.
/// Both calls landing on one boundary is also what makes the ordering
/// assertable: the check and the signal are two entries on one journal, so
/// "the name was read, then the process was signalled" is a fact about a
/// sequence rather than two counts that happen to both be one.
///
/// `name` answers nil when nothing holds the identifier and throws when the
/// machine will not say. The two are different answers and the contract keeps
/// them apart: nil is `processNotFound`, a throw is `notPermitted`, and
/// neither is a signal.
public protocol ProcessTerminating: Sendable {
    func name(ofProcessIdentifier processIdentifier: Int32) async throws -> String?
    func terminate(processIdentifier: Int32, force: Bool) async throws
}

/// When a sample is due: one tick, one snapshot. Production supplies a steady
/// cadence suitable for a live view; a test supplies the ticks it wants.
///
/// It is a boundary rather than a timer inside the monitor because a timer in
/// a test is a wall clock, and a suite that sleeps for a cadence reports on how
/// fast the machine running it happened to be that morning. Finishing the tick
/// stream is how the view says it has gone, and the sample stream finishes with
/// it.
public protocol ProcessSampleCadence: Sendable {
    func ticks() -> AsyncStream<Void>
}

public enum ProcessQuitError: Error, Sendable, Equatable {
    /// Nothing holds that identifier now. Signals nothing, whatever name was
    /// confirmed against it.
    case processNotFound(Int32)
    /// The identifier is held by something other than what was confirmed.
    /// Both names travel: the one the person answered and the one that is
    /// there now.
    case nameMismatch(expected: String, actual: String)
    /// The check could not be made, or the signal was refused by the machine.
    /// A plain sentence naming the process the person confirmed, and no path.
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

### C29. FullSweepOrchestrating

```swift
/// One scan composing deep clean (Cleanup), storage declutter (Leftovers large
/// and old files plus downloads triage) and performance boost (Performance
/// maintenance) concurrently, with one combined result and per job detail.
///
/// Guarantees:
/// - Exactly the jobs in `FullSweepJob` run. No stub jobs, ever: threat
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
/// - Full Sweep never selects what an engine did not preselect. The
///   combined review starts from each finding's own `isPreselected`
///   (C5) and offers deselection only. The orchestrator holds no
///   preselection policy of its own, so it cannot widen one, and that
///   is what stops the sweep reintroducing from its end what C5 and
///   C23 forbid at the engine's end.
/// - No plan this orchestrator produces contains a `runMaintenance`
///   operation whose task has `clearsUserVisibleData` true (C7). A Full
///   Sweep runs without anybody opening a single row, so a task that
///   needs its warning read is unreachable here by construction, and it
///   stays available in the Performance module where the warning is
///   shown. A test asserts this over the whole generated plan space,
///   not over the selection path alone.
public protocol FullSweepOrchestrating: Sendable {
    func scan(_ context: ScanContext) -> AsyncThrowingStream<FullSweepEvent, Error>
    func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan
}

public enum FullSweepJob: String, Codable, Sendable, CaseIterable, Equatable {
    case deepClean
    case storageDeclutter
    case performanceBoost
}

public enum FullSweepEvent: Sendable {
    case job(FullSweepJob, ScanEvent)
    case jobFailed(FullSweepJob, reason: String)
    case summary(FullSweepSummary)
}

public struct FullSweepSummary: Codable, Sendable, Equatable {
    public let bytesReclaimable: UInt64
    public let issueCount: UInt32
    public let perJob: [FullSweepJobOutcome]
}

public struct FullSweepJobOutcome: Codable, Sendable, Equatable {
    public enum Outcome: Codable, Sendable, Equatable {
        case completed(findingCount: UInt32, bytes: UInt64)
        case failed(reason: String)
    }
    public let job: FullSweepJob
    public let outcome: Outcome
}
```

---

## GleamHelperCore

### C30. Helper message contract

Amended 2026-08-11 in s3d: `setLaunchItemEnabled` carries a
`ChangeAttribution` (C24) in place of the plan and operation identifier pair,
because it is the only request with a caller outside any plan, and every
reply names a `correlationID` in place of an `operationID` so that caller's
replies reconcile too. `HelperContract.version` goes to 2 in the same commit,
as the last guarantee below requires. `remove` and `runMaintenance` are
unchanged: the executor is their only source, so a plan and an operation
always exist for them. The migration note after the contract lists the source
level costs.

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
/// - Every mutating request names what it is attributable to, so the helper's
///   log and the app's report reconcile one to one. For `remove` and
///   `runMaintenance` that is the plan and the operation, which always exist,
///   because the executor is the only thing that sends them. For
///   `setLaunchItemEnabled` it is a `ChangeAttribution` (C24), which is
///   either a plan operation or a direct change somebody made in the
///   interface, because that request has a caller outside any plan. No case
///   means unattributed and no field is optional, so an unattributed
///   privileged change cannot be encoded.
/// - `correlationID` is the identifier a reply echoes to tie itself to the
///   request that caused it: the operation identifier where the request
///   belongs to a plan, the change identifier where it is a direct change.
///   One name and one rule across every reply, so nothing has to remember
///   which reply carries which kind, and no reply names an operation that
///   does not exist.
/// - `remove` carries an explicit destination; the helper never chooses
///   where a file goes.
/// - Version handshake: the app sends `handshake` first, naming the version
///   it compiles against, and the helper answers naming the version it
///   compiles against, whether the two agree or not. A helper whose contract
///   version differs refuses every further request on that connection with
///   `versionMismatch`. Neither process assumes the other is current.
/// - The handshake exchange carries both versions by construction, so a
///   disagreement is never reported to the app as a bare mismatch. The app
///   compares the two numbers, says which side is behind, and prompts to
///   update that side. Nothing else in the message set carries a version,
///   and nothing else needs to.
/// - `HelperContract.version` is the single declaration of the version both
///   processes compile against. Any change to this message set bumps it in
///   the same commit as the change.
public enum HelperRequest: Codable, Sendable, Equatable {
    case handshake(contractVersion: UInt16)
    case remove(target: AbsolutePath, destination: HelperRemovalDestination,
                planID: UUID, operationID: UUID)
    case setLaunchItemEnabled(item: LaunchItemID, enabled: Bool,
                              attribution: ChangeAttribution)
    case runMaintenance(task: MaintenanceTask, planID: UUID, operationID: UUID)
}

/// Not a message: the one place the contract version is declared, in the
/// package both processes link, so app and helper cannot disagree about what
/// the current contract is without one of them being an older build.
public enum HelperContract {
    public static let version: UInt16 = 2
}

/// Which reply answers which request. In the shared package rather than in
/// the daemon, so the echo is testable: the daemon is an executable target
/// and nothing links it.
///
/// Guarantees:
/// - A reply carries the `correlationID` of the request that caused it, for
///   every request that performs work and both kinds of attribution.
/// - A handshake's completion is its acceptance, naming the version in force.
/// - No reply to a handshake claims work was done, and a launch item change
///   is never answered to a request that did not ask for one: both come back
///   as `malformedRequest`, because a reply of the wrong kind is worse than
///   no reply.
/// - A version disagreement is the one refusal that names numbers. Every
///   other refusal, on any request, names no version at all.
public struct HelperReplyRouter: Sendable {
    public init()
    public func completed(
        _ request: HelperRequest,
        bytesReclaimed: UInt64,
        contractVersion: UInt16 = HelperContract.version
    ) -> HelperResponse
    public func changed(_ request: HelperRequest, to change: LaunchItemChange) -> HelperResponse
    public func failed(_ request: HelperRequest, because reason: String) -> HelperResponse
    public func refused(
        _ request: HelperRequest,
        because refusal: HelperRefusal,
        mismatch: HelperVersionMismatch?
    ) -> HelperResponse
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
    /// The versions agreed. The value is the version now in force, which is
    /// the helper's own and, by that agreement, the app's too.
    case handshakeAccepted(contractVersion: UInt16)
    /// The versions disagreed. Sent for that reason and no other, and it
    /// names both by construction, so the app never has to infer which side
    /// is behind: a helper version below the client's means the helper is
    /// the old one and the update prompt is for the helper, above it means
    /// the app is the old one and the prompt is for the app. The two are
    /// never equal in this reply.
    case handshakeRefused(helperContractVersion: UInt16,
                          clientContractVersion: UInt16)
    case success(correlationID: UUID, bytesReclaimed: UInt64)
    case launchItemChanged(correlationID: UUID, change: LaunchItemChange)
    /// Every refusal that is not a version disagreement, including a
    /// handshake refused on identity. It names what it refused where there is
    /// something to name, so the app's report reconciles, and it names no
    /// version: a client the helper could not verify is told nothing about
    /// the helper. The identifier is nil only where no request was decoded,
    /// which is the handshake and identity cases.
    case refused(correlationID: UUID?, reason: HelperRefusal)
    case failed(correlationID: UUID, reason: String)
}

public enum HelperRefusal: String, Codable, Sendable, Equatable {
    case denylisted              // target blocked by the helper's own denylist
    case notSystemDomain         // target is user domain; least privilege cuts both ways
    /// No version agreed on this connection, or the agreed versions differ.
    case versionMismatch
    case identityRejected        // connecting client failed code signing verification
    case malformedRequest
}
```

Migration note for the C30 amendment, carried out in s3f on 2026-08-12. The
wire encoding changed, which is what the version bump is for. Nothing is
stored and no message is persisted, so nothing migrated. What it cost at the
source level, all of it now done:

- `HelperRequest`'s `planID` accessor cannot answer for every mutating
  request any more, because a direct change has no plan. It becomes a
  `correlationID` accessor that always answers, plus an optional `planID` for
  the two requests that still carry one.
- The helper's message handler read an operation identifier out of
  `setLaunchItemEnabled` to build its reply. Deciding which reply answers
  which request moved out of the daemon into `HelperReplyRouter` in the shared
  package, because the echo is a contract promise and the daemon is an
  executable target that no test links, so the promise had nowhere to be
  proved. The handler does the work and the router shapes the answer.
- The helper client builds `setLaunchItemEnabled` from an operation and a
  plan identifier. Under C17's amendment it does not build this request from
  an operation at all: it takes an item and an attribution, and it is the
  privileged side C24 declares.
- Every `HelperResponse` construction and pattern match takes the new label.

### C31. Helper policy

```swift
/// The helper's own gate. Runs inside GleamHelper before any request is
/// acted on. This is the security model made executable.
///
/// One policy instance guards one connection. The agreed version is
/// connection state: it is created with the connection and dies with it, so
/// nothing another client did can change what this connection may do.
///
/// Guarantees, in evaluation order:
/// - Identity: the connection's audit token must satisfy the code signing
///   requirement (the exact team identifier and bundle identifier of
///   MacGleam.app, `ExpectedClientIdentity.macGleamApp`). Anything else is
///   dropped before message decoding, and a decoded message on a rejected
///   connection is impossible by construction.
/// - Handshake: the first request on a connection must be `handshake`, and
///   the version it names must equal the helper's own (C30). Two cases the
///   evaluation order alone does not settle:
///   - A request of any other kind arriving before any handshake is refused
///     `versionMismatch`. No version has been agreed, so the helper cannot
///     know the app speaks its contract, and it treats no agreement exactly
///     as it treats disagreement. The app can always tell the two apart
///     locally, because it knows whether it sent a handshake on this
///     connection, and it prompts the user to update only on a
///     `handshakeRefused` that named the versions.
///   - A connection that has once been refused stays refused. Every later
///     request is refused `versionMismatch`, including a second handshake
///     naming the correct version, so a stale app cannot retry its way in.
/// - The app learns the numbers from the exchange, never from the helper's
///   own records: a version disagreement is answered with C30's
///   `handshakeRefused`, which names the helper's version and the version
///   the client claimed. The policy also exposes the mismatch it recorded
///   for the connection; that record is helper side diagnostics and never
///   crosses the process boundary.
/// - Domain: `remove` and `setLaunchItemEnabled` targets must be
///   systemDomain under the shared PathOwnershipPolicy (C16). User domain
///   targets are refused `notSystemDomain`; the helper never does work the
///   user process could do itself.
/// - Resolution, inside the domain stage: a `setLaunchItemEnabled` names an
///   item, never a path, so the helper resolves the item to the file it
///   would mutate through its own `HelperLaunchItemLocating` before it can
///   place that file in a domain. An item the helper cannot resolve is
///   refused `malformedRequest`, before the denylist is consulted: the
///   helper cannot verify least privilege for something it cannot find, and
///   it refuses rather than guessing. C24 maps that refusal onto its
///   `itemNotFound` so the user is told the item is gone.
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

/// The one client identity the helper serves. Compiled into the helper
/// rather than read from a file, so nothing on disk can widen it.
///
/// The team identifier is a launch milestone dependency. It is the team
/// identifier of the Developer ID certificate the app and the helper are
/// signed with, and that certificate does not exist yet (ROADMAP M7, s7b in
/// GRAPH.md). Until it does, `macGleamApp` carries the real bundle
/// identifier and a stand in team identifier, and the tests assert only that
/// the team identifier is not empty.
///
/// This is the one value in the codebase that fails silently when it is
/// wrong. A placeholder team identifier compiles, passes every identity test
/// and still admits any signed client that copies the bundle identifier,
/// which turns the whole client verification into a formality while the
/// suite stays green. So the release pipeline fails the build when this
/// value is not the Developer ID team (s7b): it cannot ship by being
/// forgotten, only by being overruled.
public struct ExpectedClientIdentity: Sendable, Equatable {
    public let teamIdentifier: String
    public let bundleIdentifier: String
    public static let macGleamApp: ExpectedClientIdentity
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
///   menu bar and Disk Map never show contradictory numbers for the same
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

## Hub interface

### C36. Hub shell model

```swift
import Foundation
import Observation
import GleamDesign

/// The orb's five moods. The complete set from DESIGN.md, closed from the
/// start so the appearance mapping below is total. s0b reaches only the two
/// idle moods through HubModel; scanning, result and cleanSweep become
/// reachable when Full Sweep wires in (s6b), by extending the derivation
/// inputs, never by adding cases.
public enum OrbMood: String, CaseIterable, Sendable, Equatable {
    case idleHealthy
    case idleAttention
    case scanning
    case result
    case cleanSweep
}

/// The six modules in their fixed rail order. The order of
/// `allCases` is the layout order and is part of the contract: a test
/// asserts this exact sequence and the hub never reorders at runtime.
/// `leftovers` presents the `GleamModule.leftovers` engine (C4). Disk Map
/// and Settings are rail destinations without a module behind them, so they
/// have no case here; HubDestination (C37) is the full rail.
public enum HubModule: String, CaseIterable, Sendable, Equatable {
    case fullSweep
    case cleanup
    case protection
    case performance
    case applications
    case leftovers
}

/// One module card on the hub.
///
/// Guarantees:
/// - `figure` is the card's live figure line (for example a reclaimable
///   estimate or a last scan time). Empty is allowed while the module is a
///   placeholder; it is never filler text.
/// - `isEnabled` false means the module is reachable and says so in its
///   pane, but offers no action.
public struct HubModuleSummary: Sendable, Equatable, Identifiable {
    public var id: HubModule { module }
    public let module: HubModule
    public let figure: String
    public let isEnabled: Bool
}

/// Everything the hub shell derives its presentation from. A plain value so
/// tests construct any machine condition directly.
///
/// Guarantees:
/// - `now` is the instant all recency wording is reckoned against. It is
///   always an input; nothing downstream of this type reads a clock.
/// - `attentionReason`, when present, is one plain sentence naming the top
///   issue, suitable for display as the status line.
public struct HubMachineState: Sendable, Equatable {
    public let lastScanFinishedAt: Date?
    public let reclaimableEstimateBytes: UInt64?
    public let attentionReason: String?
    public let moduleFigures: [HubModule: String]
    public let enabledModules: Set<HubModule>
    public let now: Date
}

/// The hub view model, on the macOS 14 Observation framework. The SwiftUI
/// hub renders this and adds no state of its own.
///
/// Guarantees:
/// - Mood derivation is deterministic and total over its inputs:
///   `mood(for:)` returns a value for every HubMachineState and equal
///   states always give equal moods. In s0b the range is the idle pair:
///   `idleAttention` exactly when `attentionReason` is present,
///   `idleHealthy` otherwise.
/// - Derivation is pure: no timers, no clock reads, no hidden state. `now`
///   arrives in the input, never from `Date()` inside, so a test can pin
///   any instant.
/// - The status line is never empty. With an attention reason it is exactly
///   that sentence. Otherwise it names the last scan recency (reckoned
///   against `now`) and the reclaimable estimate; before any scan exists it
///   is a plain sentence inviting the first scan.
/// - `cards` always holds exactly six entries, one per HubModule, in
///   `HubModule.allCases` order, whatever the state says. A module missing
///   from `moduleFigures` gets an empty figure. The order never changes
///   at runtime.
/// - `apply` is the only mutation path, and after it `orbMood`,
///   `statusLine` and `cards` equal the pure functions of the applied
///   state.
/// - The static functions are nonisolated so tests drive them without a
///   view or a main actor hop.
@MainActor @Observable
public final class HubModel {
    public private(set) var orbMood: OrbMood
    public private(set) var statusLine: String
    public private(set) var summaries: [HubModuleSummary]

    public init(state: HubMachineState)
    public func apply(_ state: HubMachineState)

    public nonisolated static func mood(for state: HubMachineState) -> OrbMood
    public nonisolated static func statusLine(for state: HubMachineState) -> String
    public nonisolated static func summaries(for state: HubMachineState) -> [HubModuleSummary]
}

/// The orb's surface tint. Exactly two cases and neither is the dangerous
/// colour: an alarmed orb is unrepresentable by construction, which is how
/// the design's "never red, never alarmist" survives every refactor.
public enum OrbSheen: String, Sendable, Equatable {
    case iridescent        // healthy
    case warmedToReview    // attention: the review colour token
}

/// What the orb does for a mood, as data. Views interpret this; tests
/// assert on it directly, which is what makes the Reduce Motion guarantee a
/// unit test rather than a screenshot.
public enum OrbAppearance: Sendable, Equatable {
    /// Idle, full motion: breathing scale at `period` with a C2 spring.
    case breathing(spring: GleamSpring, period: Duration, sheen: OrbSheen)
    /// Reduce Motion for every mood except scanning: a static gradient
    /// whose mood changes crossfade with a C2 fade token.
    case staticGradient(sheen: OrbSheen, moodChangeFade: GleamFade)
    /// Scanning, full motion: the shimmer band orbits the orb.
    case shimmerBand
    /// Scanning under Reduce Motion: a determinate progress ring.
    case determinateRing
    /// Result, full motion: one pulse with the given spring.
    case resultPulse(spring: GleamSpring)
    /// Clean sweep, full motion: the calm lustre bloom.
    case lustreBloom
}

/// Pure mapping from mood and Reduce Motion flag to appearance.
///
/// Guarantees:
/// - Total: every (mood, reduceMotion) pair returns an appearance. All ten
///   combinations are asserted in one table test.
/// - With reduceMotion false: idleHealthy is breathing with a period of
///   exactly 6 seconds and the iridescent sheen; idleAttention is breathing
///   with a strictly shorter period and the warmedToReview sheen (the
///   breathing quickens, the sheen warms, nothing turns dangerous);
///   scanning is shimmerBand; result is resultPulse with the lively spring
///   (the hub shell's only lively use); cleanSweep is lustreBloom.
/// - With reduceMotion true the result never contains a spring: scanning
///   is determinateRing, every other mood is staticGradient with the
///   standard fade. There is no input for which reduceMotion true yields
///   breathing or resultPulse.
/// - Every animation named in a returned appearance is a C2 token. No raw
///   curve or duration appears anywhere in this mapping.
public enum OrbAppearanceResolver {
    public static func appearance(
        for mood: OrbMood,
        reduceMotion: Bool
    ) -> OrbAppearance { fatalError("contract") }
}
```

### C37. Rail navigation model

Revised 2026-08-10. The hexagon of six cards and the hub to module zoom are
gone; the rail replaces them. `HubZoomDirection` and `HubZoomResolver` stay
because Disk Map drills into folders with the same grammar (C39).

Both parts that this contract specified and did not wire are wired as of
s2i, 2026-08-12.

- `HubIntent`. The rail resolves a key press through
  `HubKeyResolver.outcome(_:applying:pane:)`, which takes what the open pane
  can actually do, and returns a moved state, an intent the pane runs, or
  ignored. A press is claimed only when it moves the rail or carries an
  intent the pane can run, so a key that does nothing is reported as ignored
  and the system gives its own feedback. Return runs the pane's primary
  action, escape runs a dismissal where one exists and never cancels or
  destroys work.
- `ModuleStateSlot` and `HubNavigationState.storingSlot`, through
  `ModuleStateExchange.navigate(_:to:preservers:)`. Every rail move, from the
  pointer or from an arrow key, goes through that one function: it asks the
  departing module for a slot, stores it, and hands the arriving module back
  whatever it left. A module that preserves nothing answers nil and its slots
  are untouched; a module that preserves anything answers a slot every time,
  so leaving with an empty state overwrites the last one rather than letting
  a stale fold return two visits later. Cleanup is the first module with a
  slot: it carries which review categories the user folded away, which the
  rail used to destroy by rebuilding the pane. Disk Map has no slot and needs
  none, because it is rail chrome rather than a module and its model outlives
  the pane (C39).

```swift
import Foundation
import GleamDesign

/// The keys the rail understands. A closed set: full operation without a
/// pointer means these six reach every destination and act on it.
public enum HubKeyEvent: String, CaseIterable, Sendable, Equatable {
    case arrowLeft
    case arrowRight
    case arrowUp
    case arrowDown
    case `return`
    case escape
}

/// Everywhere the rail can take you, in rail order.
///
/// Guarantees:
/// - `allCases` is every module in `HubModule.allCases` order, then
///   diskMap, then settings. The order is fixed; the rail never reorders
///   at runtime.
/// - Every destination has a non empty title and symbol, and no two share
///   either.
/// - Groups are contiguous and the work group comes first, so the rail draws
///   at most one gap.
public enum HubDestination: Hashable, Codable, Sendable, CaseIterable {
    case module(HubModule)
    case diskMap
    case settings

    public static let allCases: [HubDestination]
    public var group: HubDestinationGroup { fatalError("contract") }
    public var title: String { fatalError("contract") }
    public var symbolName: String { fatalError("contract") }
}

public enum HubDestinationGroup: CaseIterable, Sendable, Equatable {
    case work
    case apart
}

/// One module's preserved state, opaque to the rail. The module encodes its
/// own Codable state into `payload` on leaving and decodes it on re entry;
/// the rail stores and returns bytes and never interprets them.
///
/// Opaque data rather than a generic parameter is deliberate: a generic
/// would make the navigation state's type depend on every module's state
/// type. The cost is stated plainly: nothing at compile time proves a module
/// decodes the type it encoded. Each module owns that round trip, and a
/// payload a module cannot read leaves it exactly as it was.
public struct ModuleStateSlot: Codable, Sendable, Equatable {
    public let payload: Data
    public init(payload: Data)
}

/// Where the user is, and every module's preserved state.
///
/// Guarantees:
/// - Exactly one destination is selected at all times, by construction: the
///   selection is a non optional HubDestination and no unselected state is
///   representable. There is no overview screen and no unfocused state.
/// - `initial` is the first destination in rail order, `.module(.fullSweep)`,
///   with no stored slots.
/// - Values are immutable. `storingSlot` returns a copy with that module's
///   slot replaced and everything else identical; it is the only operation
///   anywhere that changes `moduleStateSlots`.
public struct HubNavigationState: Codable, Sendable, Equatable {
    public let selection: HubDestination
    public let moduleStateSlots: [HubModule: ModuleStateSlot]

    public init(selection: HubDestination, moduleStateSlots: [HubModule: ModuleStateSlot])
    public static let initial: HubNavigationState
    public func storingSlot(_ slot: ModuleStateSlot, for module: HubModule) -> HubNavigationState
}

/// A module surface that keeps state the rail would otherwise destroy, since
/// the rail rebuilds the pane on every return.
///
/// Guarantees:
/// - `stateSlot` returning nil means the module preserves nothing at all, a
///   standing answer rather than "nothing changed". A module that answers a
///   slot answers one every time, so an emptied state overwrites the stored
///   slot instead of leaving a stale one to come back.
/// - `restoreState` is called only when a slot exists, so an absent slot
///   leaves the module at its own defaults, and a payload the module cannot
///   decode leaves it exactly as it was.
public protocol ModuleStatePreserving: AnyObject {
    func stateSlot() -> ModuleStateSlot?
    func restoreState(from slot: ModuleStateSlot)
}

/// One move of the rail: the departing module's state put away, the arriving
/// module's state handed back.
///
/// Guarantees:
/// - The only place a module is asked for a slot or given one, so both halves
///   of the round trip happen exactly once per move and no caller can do half
///   of it. The shell routes the pointer and the arrow keys through it alike.
/// - Moving to the destination already selected is not a move: nothing is
///   stored, nothing is restored, the state comes back identical.
/// - Only a module has a slot. Leaving Disk Map or Settings stores nothing,
///   and no module's slot is ever created, dropped or altered except the one
///   being left.
public enum ModuleStateExchange {
    public static func navigate(
        _ state: HubNavigationState,
        to destination: HubDestination,
        preservers: [HubModule: any ModuleStatePreserving]
    ) -> HubNavigationState { fatalError("contract") }
}

/// The outcome of one key press: the next state, plus what the open pane is
/// being asked to do.
///
/// Guarantees:
/// - `intent` is non nil exactly for return and escape, and nil for every
///   arrow, whether or not the arrow moved the selection.
public struct HubNavigationTransition: Sendable, Equatable {
    public let next: HubNavigationState
    public let intent: HubIntent?
}

/// What a key press asks of the pane. The rail owns the selection; anything
/// beyond moving it belongs to whatever is on screen.
public enum HubIntent: String, CaseIterable, Sendable, Equatable {
    case activatePrimaryAction
    case dismiss
}

/// The pure key transition. The whole rail navigation behaviour is this one
/// function, driven in tests without a view.
///
/// Guarantees:
/// - Total and deterministic: every (state, key) input returns a transition;
///   equal inputs return equal outputs; no clock, no randomness, no hidden
///   state. `enabledModules` is not an input: enablement decides what a pane
///   offers, never what the rail reaches.
/// - arrowUp and arrowDown move one step through `HubDestination.allCases`
///   and clamp at the ends. A clamped press returns the state unchanged.
///   Walking therefore never leaves the rail, over any key sequence, and
///   every destination is reachable from the top with down alone.
/// - arrowLeft and arrowRight are the identity: the rail is one column, and
///   horizontal movement belongs to the pane.
/// - `return` carries `.activatePrimaryAction` and `escape` carries
///   `.dismiss`; neither moves the selection.
/// - Every destination is selectable, including a module that has not been
///   built. The pane is where a module admits it has nothing to offer.
/// - No transition creates, drops or alters a module state slot:
///   `next.moduleStateSlots` always equals the input's, over any key
///   sequence, as a property test.
/// - The resolver names the intent; HubKeyResolver decides whether the open
///   pane can run it, so an intent nothing will run leaves the press
///   unclaimed rather than swallowing it.
public enum HubNavigationResolver {
    public static func transition(
        _ state: HubNavigationState,
        applying key: HubKeyEvent
    ) -> HubNavigationTransition { fatalError("contract") }
}

/// What the pane beside the rail shows. A module that is not built still gets
/// one: it says what it will do and admits it cannot do it, rather than
/// showing an empty screen or an action that does nothing.
///
/// Guarantees:
/// - Total: every destination resolves a pane whose title is the
///   destination's title and whose sentence is a full sentence.
/// - A pane carries an action exactly when its module is enabled, and a not
///   ready note exactly when it does not. Never both, never neither.
/// - Job names come from DESIGN.md, so an unshipped module still tells the
///   truth about what it is going to do. No module lists a job or a glyph
///   twice, and every job carries a glyph.
/// - The module's live figure appears on its first job and nowhere else, so
///   a figure is never shown twice or attributed to the wrong job or module.
public struct ModulePane: Sendable, Equatable {
    public let title: String
    public let sentence: String
    public let jobs: [ModulePaneJob]
    public let action: ModulePaneAction?
    public let notReadyNote: String?
}

public struct ModulePaneJob: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let symbolName: String
    public let detail: String
}

public struct ModulePaneAction: Sendable, Equatable {
    public let title: String
}

public enum ModulePaneResolver {
    public static func pane(
        for destination: HubDestination,
        summaries: [HubModuleSummary]
    ) -> ModulePane { fatalError("contract") }
}

/// Pure mapping from zoom direction and Reduce Motion flag to the animation
/// the view performs. The analogue of OrbAppearanceResolver (C36):
/// asserting on the returned value is what makes the never a spring under
/// Reduce Motion guarantee a unit test rather than a screenshot.
///
/// Guarantees:
/// - Total: all four (direction, reduceMotion) pairs return an appearance,
///   asserted in one table test.
/// - With reduceMotion false, both directions are matchedGeometry with the
///   snappy spring (C2 assigns snappy to navigation), and leaving uses the
///   same token as entering: the exact reverse, one continuous motion.
/// - With reduceMotion true, both directions are crossfade with the
///   standard fade. There is no input for which reduceMotion true returns
///   matchedGeometry, so the result never contains a spring.
/// - Every animation named in a returned appearance is a C2 token. No raw
///   curve or duration appears anywhere in this mapping.
public enum HubZoomResolver {
    public static func appearance(
        for direction: HubZoomDirection,
        reduceMotion: Bool
    ) -> HubZoomAppearance { fatalError("contract") }
}

/// What the zoom does, as data.
public enum HubZoomAppearance: Sendable, Equatable {
    /// Full motion: the matched geometry zoom with a C2 spring.
    case matchedGeometry(spring: GleamSpring)
    /// Reduce Motion: a crossfade with a C2 fade token.
    case crossfade(fade: GleamFade)
}
```

---

## Module interfaces

### C38. Cleanup module model

```swift
import Foundation
import Observation

/// What the onboarding flow (s1f, C32) hands the cleanup module about Full
/// Disk Access. A plain value so tests construct any degraded condition
/// directly.
///
/// Guarantees:
/// - `unavailable` is empty exactly when `hasFullDiskAccess` is true. Each
///   entry is a plain sentence naming something the module cannot reach,
///   renderable in the honest banner verbatim.
public struct CleanupDegradedState: Sendable, Equatable {
    public let hasFullDiskAccess: Bool
    public let unavailable: [String]
    public init(hasFullDiskAccess: Bool, unavailable: [String])
}

/// The module's view of the onboarding model's degraded state. A protocol
/// so tests script grant and decline without the real monitor.
public protocol CleanupDegradedStateProviding: Sendable {
    func current() async -> CleanupDegradedState
}

/// Mints the per session contexts of C15. The one place the file system,
/// rules catalogue and ownership policy are visible to the module wiring;
/// the model itself never holds them, which makes "the model never touches
/// the file system" a compile time property rather than a review note.
///
/// Guarantees:
/// - Every `makeScanContext` call mints a fresh session identifier. No two
///   calls return contexts sharing one.
/// - `makePlanContext(sessionID:settings:)` returns a context for exactly
///   that session, so C15's `findingFromDifferentSession` stays reachable
///   in tests and unreachable in correct wiring.
public protocol CleanupSessionProviding: Sendable {
    func makeScanContext(settings: Settings, hasFullDiskAccess: Bool) async -> ScanContext
    func makePlanContext(sessionID: UUID, settings: Settings) async -> PlanContext
}

/// Where the cleanup module is. One closed lifecycle; the degraded banner
/// is not a state here because degraded scanning still scans (C15), so it
/// rides alongside as `degradedNotices` on the model.
public enum CleanupModuleState: Sendable, Equatable {
    /// No scan this session. The entry state, and the state after a result
    /// is acknowledged or a scan fails or is cancelled.
    case idle
    case scanning(CleanupScanProgress)
    case reviewing(CleanupReviewState)
    case executing(CleanupExecutionProgress)
    case result(CleanupResultSummary)
    /// The scan completed and found nothing. The designed reward state
    /// (DESIGN.md clean sweep), never a blank panel: it says what was
    /// checked.
    case cleanSweep(filesChecked: UInt64)
}

/// Scan progress as the view renders it: the three phase choreography plus
/// the live counters.
///
/// Guarantees:
/// - `phase` only ever advances per C4 (indeterminate, determinate,
///   settling; determinate may be skipped, never revisited).
/// - `counters` are monotonic within the session per C4: filesSeen,
///   bytesReclaimable and itemCount never decrease across successive
///   scanning states. `itemCount` counts path entries, not findings, so the
///   figure the progress line shows does not move when the engine's batch
///   size does (C4, amended in s2e).
public struct CleanupScanProgress: Sendable, Equatable {
    public let sessionID: UUID
    public let phase: ScanPhase
    public let counters: ScanCounters
}

/// One category group in review: every finding of one category, in the order
/// they streamed. The group, not the finding, is what the review screen
/// shows as a category, which is what makes a streaming scan (C15) invisible
/// to the person reading the list.
///
/// Guarantees:
/// - `findings` is never empty and every member carries `category`.
/// - A category appears exactly once in a review. The group is Identifiable
///   by its category, so a second group of the same category would be a
///   duplicate identity in the list; every finding of a category lands in
///   this one group however many findings the scan emitted for it.
/// - `findings` is in arrival order, and the group's position in
///   `CleanupReviewState.categories` is fixed by the arrival of the
///   category's first finding. Neither is re sorted when later findings of
///   an existing category arrive, so rows append and the list never
///   reshuffles under the user mid scan (DESIGN.md: rows insert with a
///   staggered spring, never a jump cut).
/// - `byteTotal` and `pathCount` are the category's own figures, summed
///   across its findings. They exist because after batching no single
///   finding carries them, and a consumer deriving them separately is
///   exactly the drift this model exists to prevent.
public struct CleanupReviewCategory: Sendable, Equatable, Identifiable {
    public let category: FindingCategory
    public let findings: [Finding]
    public var id: FindingCategory { category }
    /// Derived: the sum of `byteSize` over `findings`.
    public var byteTotal: UInt64 { get }
    /// Derived: the count of paths across `findings`.
    public var pathCount: UInt32 { get }
}

/// The reviewed findings and the current selection.
///
/// Guarantees:
/// - `categories` is never empty (an empty scan lands on cleanSweep, not
///   here), holds one group per distinct category, and every finding in it
///   belongs to `sessionID`.
/// - `selectedFindingIDs` only contains identifiers of findings present in
///   `categories`.
/// - `selectedByteTotal` is exactly the sum of `byteSize` over the selected
///   findings; `selectedFileCount` is exactly the count of paths across
///   them. Pure derivations, no stored copies to drift. Both were already
///   sums over findings rather than over categories, so both hold unchanged
///   when a category spans several findings (C15).
/// - Selection is per finding identifier, never per category. A category
///   whose findings are partly selected is an ordinary state, and the
///   totals report exactly the selected part of it: a half selected
///   category contributes half its bytes, not all and not none. Reaching
///   that state takes `toggleFinding`; `toggleCategory` is all or nothing
///   across the whole group.
public struct CleanupReviewState: Sendable, Equatable {
    public let sessionID: UUID
    public let categories: [CleanupReviewCategory]
    public let selectedFindingIDs: Set<UUID>
    public var selectedByteTotal: UInt64 { get }
    public var selectedFileCount: UInt32 { get }
}

/// Execution progress as the view renders it: per operation completion and
/// the reclaimed figure ticking up.
///
/// Guarantees:
/// - `finishedOperations` and `bytesReclaimed` never decrease across
///   successive executing states, and `finishedOperations` never exceeds
///   `totalOperations`.
/// - `currentOperationID` is the operation the executor last reported
///   started and not yet finished, nil between operations.
public struct CleanupExecutionProgress: Sendable, Equatable {
    public let planID: UUID
    public let totalOperations: UInt32
    public let finishedOperations: UInt32
    public let bytesReclaimed: UInt64
    public let currentOperationID: UUID?
}

/// The execution report (C7) summarised for the result screen. Everything
/// that screen renders is here, so the screen is testable without SwiftUI.
///
/// Guarantees:
/// - Derived from exactly one ExecutionReport and consistent with it:
///   `bytesReclaimed` equals the report's total, and the per category
///   counts sum to one entry per operation in the plan.
/// - `categoryOutcomes` appear in the review's category order, only for
///   categories the plan touched.
/// - `failures` carries one plain sentence per failed operation, in plan
///   order: what failed and what was and was not done, never a code. A
///   cancelled run's untouched operations count as `notStartedCount`, which
///   is how the partial result screen says exactly which is which.
/// - `skippedDenylistedNames` carries the last path component of each
///   operation skipped by the denylist, in plan order. A skip is reported
///   as the safety system working, distinct from failure (C7).
public struct CleanupResultSummary: Sendable, Equatable {
    public let bytesReclaimed: UInt64
    public let categoryOutcomes: [CleanupCategoryOutcome]
    public let failures: [String]
    public let skippedDenylistedNames: [String]
}

public struct CleanupCategoryOutcome: Sendable, Equatable {
    public let category: FindingCategory
    public let completedCount: UInt32
    public let failedCount: UInt32
    public let skippedCount: UInt32
    public let notStartedCount: UInt32
    public let bytesReclaimed: UInt64
}

/// The exact permanent scope of the current selection under the current
/// deletion mode: what a PermanentDeletionConfirmation must name. Nil scope
/// means no confirmation is needed.
public struct PermanentDeletionScope: Sendable, Equatable {
    public let fileCount: UInt32
    public let byteTotal: UInt64
}

/// Why executeSelection did not start. Returned, never thrown, so the thin
/// view branches on it directly; the state is unchanged in every case.
public enum CleanupCommandRefusal: Sendable, Equatable {
    case notReviewing
    case emptySelection
    /// The selection plans permanent deletions and no confirmation was
    /// passed. Carries the scope the confirmation must name (C6).
    case permanentDeletionUnconfirmed(required: PermanentDeletionScope)
    /// A confirmation was passed but its counts do not match the scope.
    case confirmationMismatch(required: PermanentDeletionScope)
}

/// The cleanup module view model, on the macOS 14 Observation framework.
/// A thin SwiftUI view renders this and adds no state of its own. The
/// module's whole behaviour is this class driven against fakes of its five
/// injected protocols.
///
/// Guarantees:
///
/// State transitions are total and deterministic. Every command in every
/// state either performs its named transition or leaves the state
/// identical; equal command and event sequences produce equal state
/// sequences. The full table, everything else being the identity:
/// - `startScan`: idle, reviewing, result or cleanSweep to scanning.
///   Ignored while scanning or executing. From reviewing it discards the
///   current findings and selection and begins a fresh session (reviewing
///   would otherwise be a trap state, since escape preserves module state
///   per C37).
/// - Stream driven, while scanning: the engine's events update
///   `scanning`; a completed scan with findings moves to reviewing, with
///   none to cleanSweep carrying the final filesSeen; a thrown scan stream
///   moves to idle with `failureNotice` set to a plain sentence.
/// - `toggleFinding`, `toggleCategory`: reviewing only, selection change
///   only, never a lifecycle change. An unknown finding identifier is
///   ignored. `toggleCategory` addresses every finding in the category's
///   group, which after batching is usually several (C15): it selects all
///   of them when at least one is unselected, otherwise deselects all of
///   them. So one category toggle is all or nothing over the whole
///   category however many findings it spans, and the byte total moves by
///   the category's whole `byteTotal` either way.
/// - `executeSelection`: reviewing to executing when admitted; a non nil
///   refusal is returned and nothing changes otherwise.
/// - `cancelScan`: scanning to idle, partial findings discarded. Safe by
///   construction: a cancelled scan has no side effects on disk (C4, C13).
///   The confirmation prompt is the view's job; this command is the
///   confirmed cancellation.
/// - `cancelExecution`: cancels the running plan. Cancellation takes
///   effect between operations, never mid item (C17); the state remains
///   executing until the executor's report arrives, then moves to result,
///   whose summary is the partial result screen.
/// - `acknowledgeResult`: result or cleanSweep to idle.
///
/// Scanning:
/// - `startScan` reads current settings from the store, current degraded
///   state from the provider, mints one scan context through the session
///   provider and consumes the engine's stream. One session at a time, by
///   the transition table.
/// - `degradedNotices` is replaced at each `startScan` with the provider's
///   `unavailable` sentences, and every distinct ScanEvent.degraded
///   sentence appends in arrival order. It never contains duplicates or
///   empty strings, and is empty exactly when nothing was skipped. This is
///   the honest banner's content (C32, DESIGN.md permission states).
///
/// Review and selection:
/// - On entering reviewing, exactly the findings with `isPreselected` true
///   are selected. Risky findings are never preselected by the engine
///   (C20), and this model additionally never defaults a finding whose
///   risk is not `.safe` to selected, whatever the finding claims. Defence
///   in depth, same shape as the engine's own conjunction rule.
/// - Batching does not change which paths arrive preselected. Every finding
///   a rule produces carries that rule's own risk and preselection (C20),
///   so a Cleanup category is uniformly preselected or uniformly not, and
///   entering review still selects whole categories rather than fragments
///   of them. A category arriving half selected would mean the engine
///   broke its own conjunction rule.
/// - `permanentDeletionScope()` returns, while reviewing, the exact file
///   count and byte total of the operations the current selection would
///   plan as `deletePermanently` under the current deletion mode: every
///   selected finding when the mode is permanent, and trash bin findings
///   always, whatever the mode (C20: trash bin contents always plan
///   permanent). Nil when reviewing with no permanent operations, and nil
///   in every other state. The view uses it to put the exact counts in
///   the confirmation it shows (C6).
///
/// Execution:
/// - `executeSelection` builds the plan through the engine's `plan` method
///   with a plan context for the review session and the store's current
///   settings, so the deletion mode is honoured at the moment of the
///   command (C15, C12). The model attaches the caller's confirmation to
///   the plan; it never constructs one itself, because the confirmation is
///   evidence the user saw the counts (C6).
/// - When `permanentDeletionScope()` is non nil, a nil confirmation
///   returns `permanentDeletionUnconfirmed` and a confirmation whose
///   counts differ from the scope returns `confirmationMismatch`. Both
///   refuse before the engine or executor is touched.
/// - A `plan` throw leaves the state reviewing and sets `failureNotice`
///   to a plain sentence.
/// - The executor's stream drives executing; its terminal report (C17
///   guarantees exactly one, whatever happened) moves to result with the
///   summary derived from it. An ExecutionRefusal surfaces as a failure
///   sentence in the summary, never a crash and never a silent drop.
///
/// The figure the hub card shows:
/// - `hubEstimateBytes` is zero before the first scan and in cleanSweep;
///   the monotonic `bytesReclaimable` counter while scanning; exactly
///   `selectedByteTotal` while reviewing (it moves with every toggle); the
///   ticking `bytesReclaimed` while executing; and the report's reclaimed
///   total in result and after `acknowledgeResult`, until the next scan
///   revises it. Within any one scan or execution it never decreases.
///
/// Purity and isolation:
/// - The model holds only its five injected protocols. It never touches
///   the file system, which the wiring makes structural: nothing here
///   imports or receives FileSystemReading or FileSystemMutating (C13,
///   C14); the disk is reachable only through the engine's scan stream and
///   the executor.
/// - No clock reads. The model never calls Date(); every date it holds
///   arrived in an input (the caller's confirmation, the executor's
///   report).
/// - `failureNotice` is always a plain sentence, set only by a failed scan
///   stream or a failed plan build, and cleared by the next `startScan`.
/// - Construction traps unless `engine.module == .cleanup`.
@MainActor @Observable
public final class CleanupModuleModel {
    public private(set) var state: CleanupModuleState
    public private(set) var degradedNotices: [String]
    public private(set) var failureNotice: String?
    public private(set) var hubEstimateBytes: UInt64

    public init(
        engine: any GleamEngine,
        executor: any PlanExecuting,
        settings: any SettingsStoring,
        sessions: any CleanupSessionProviding,
        degraded: any CleanupDegradedStateProviding
    )

    public func startScan()
    public func toggleFinding(_ findingID: UUID)
    public func toggleCategory(_ category: FindingCategory)
    public func permanentDeletionScope() -> PermanentDeletionScope?
    @discardableResult
    public func executeSelection(
        permanentConfirmation: PermanentDeletionConfirmation?
    ) -> CleanupCommandRefusal?
    public func cancelScan()
    public func cancelExecution()
    public func acknowledgeResult()
}
```

### C39. Disk Map module model

```swift
import Foundation
import Observation
import GleamHub   // HubZoomDirection, HubZoomResolver, HubZoomAppearance (C37)

/// The narrow engine seam the module model consumes, so tests script the
/// streaming map and the plan without the real engine. DiskMapEngine
/// (C22) is the one production conformance; this protocol adds nothing to
/// C22 and takes nothing from it: `map` and `plan` carry C22's guarantees
/// verbatim.
public protocol DiskMapProviding: Sendable {
    var module: GleamModule { get }
    func map(
        volume: AbsolutePath,
        context: ScanContext
    ) -> AsyncThrowingStream<DiskMapUpdate, Error>
    func plan(selection: [Finding], context: PlanContext) throws -> OperationPlan
}

/// Mints the per session contexts of C15 for Disk Map. Same shape and
/// guarantees as CleanupSessionProviding (C38): every makeScanContext call
/// mints a fresh session identifier, and plan contexts are bound to exactly
/// their session. A deliberate duplicate of the C38 protocol rather than a
/// shared abstraction; the third module surface extracts the pattern.
public protocol DiskMapSessionProviding: Sendable {
    func makeScanContext(settings: Settings, hasFullDiskAccess: Bool) async -> ScanContext
    func makePlanContext(sessionID: UUID, settings: Settings) async -> PlanContext
}

/// One node of the streaming tree the thin view renders.
///
/// Guarantees:
/// - `allocatedBytesSoFar` never decreases across successive published
///   trees: the model level mirror of C22's sizeRevision monotonicity, so
///   the rendered map only ever grows.
/// - `hasConverged` flips false to true at most once and never back. When
///   the stream completes every node has converged and
///   `allocatedBytesSoFar` equals the engine's final total for the path.
/// - `isSelectable` is false for every denylisted path (C22) and always
///   false for the volume root, whatever the denylist says: the map never
///   offers deleting the volume it is mapping.
/// - `children` is sorted by allocatedBytesSoFar descending, ties broken
///   lexicographically by path, so the rendered map is a pure, reproducible
///   function of the tree.
public struct DiskMapTreeNode: Sendable, Equatable, Identifiable {
    public var id: AbsolutePath { path }
    public let path: AbsolutePath
    public let isDirectory: Bool
    public let allocatedBytesSoFar: UInt64
    public let hasConverged: Bool
    public let isSelectable: Bool
    public let children: [DiskMapTreeNode]
}

/// The map as the view renders it: the tree, where the user has drilled to,
/// and what they have selected.
///
/// Guarantees:
/// - `root` is nil only before the first node arrives; from then on it is
///   the volume root's node.
/// - In browsing, `focusPath` is always the volume root or a directory
///   node present in the tree. While mapping it may name a drill
///   intention: a directory path accepted before its node streamed,
///   reconciled onto the node when it arrives, pruned at completion if
///   it never did (see the model's drillIn).
/// - `selectedPaths` is an antichain under `isDescendant(of:)` (C3) at
///   all times: it never contains a path and a descendant of that path,
///   so no byte is ever counted twice. Every member whose node has
///   streamed is a selectable node; while mapping the set may
///   additionally hold selection intentions for paths not yet streamed
///   (see the model's toggleSelection). In browsing every member is a
///   selectable node present in the tree: unmatched intentions were
///   pruned at completion.
/// - `selectedByteTotal` is exactly the sum of `allocatedBytesSoFar` over
///   the selected paths whose nodes are present in the tree; an
///   unresolved intention contributes nothing until it resolves. A pure
///   derivation, no stored copy to drift.
public struct DiskMapState: Sendable, Equatable {
    public let sessionID: UUID
    public let volume: AbsolutePath
    public let root: DiskMapTreeNode?
    public let focusPath: AbsolutePath
    public let selectedPaths: Set<AbsolutePath>
    public var selectedByteTotal: UInt64 { get }
}

/// Where the Disk Map module is. Disk Map is hub chrome, not a card:
/// HubModule (C36) has no case for it and C37's module state slots do not
/// apply. Entry and exit of the surface is chrome wiring; this model owns
/// everything inside it.
public enum DiskMapModuleState: Sendable, Equatable {
    /// No map this session: the entry state, and the state after a result
    /// is acknowledged, a mapping fails or is cancelled. A result
    /// acknowledgement always lands here, never back on the old map: an
    /// executed plan means the tree no longer matches the disk, and a
    /// stale map is worse than no map.
    case idle
    /// The stream is running. The map grows, drill and selection work,
    /// execution is refused until completion.
    case mapping(DiskMapState)
    /// The stream completed: every total converged and true (C22). The
    /// only state that admits executeSelection, so every byte figure a
    /// confirmation names is a true allocated total, never an estimate.
    case browsing(DiskMapState)
    case executing(DiskMapExecutionProgress)
    case result(DiskMapResultSummary)
}

/// One drill step, as data, for the view to animate. Reuses the C37 zoom
/// grammar: the view resolves `direction` through HubZoomResolver, so
/// drilling into a folder runs on the shared navigation tokens (snappy
/// matched geometry, crossfade under Reduce Motion) and the whole app keeps
/// one navigation language. That grammar was written for the hub to module
/// zoom, which is gone; this is where it still runs. HubZoom itself is not
/// reused: it names a HubModule, and a folder is not a module.
public struct DiskMapDrill: Sendable, Equatable {
    public let target: AbsolutePath
    public let direction: HubZoomDirection
}

/// Execution progress, same shape and monotonicity guarantees as C38's
/// CleanupExecutionProgress: finishedOperations and bytesReclaimed never
/// decrease across successive executing states, finishedOperations never
/// exceeds totalOperations, and currentOperationID is the operation the
/// executor last reported started and not yet finished, nil between
/// operations.
public struct DiskMapExecutionProgress: Sendable, Equatable {
    public let planID: UUID
    public let totalOperations: UInt32
    public let finishedOperations: UInt32
    public let bytesReclaimed: UInt64
    public let currentOperationID: UUID?
}

/// The result screen's whole content, derived from exactly one
/// ExecutionReport (C7) and consistent with it, C38 style.
///
/// Guarantees:
/// - `bytesReclaimed` equals the report's total, and completedCount,
///   failedCount, skipped and notStartedCount sum to one entry per
///   operation in the plan.
/// - `failures` carries one plain sentence per failed operation, in plan
///   order: what failed and what was and was not done, never a code.
/// - `skippedDenylistedNames` carries the last path component of each
///   denylist skip, in plan order, reported as the safety system working,
///   distinct from failure (C7).
/// - `notStartedCount` counts a cancelled run's untouched operations,
///   which is how the partial result says exactly which is which.
public struct DiskMapResultSummary: Sendable, Equatable {
    public let bytesReclaimed: UInt64
    public let completedCount: UInt32
    public let failedCount: UInt32
    public let notStartedCount: UInt32
    public let failures: [String]
    public let skippedDenylistedNames: [String]
}

/// Why executeSelection did not start. Returned, never thrown; the state
/// is unchanged in every case (C38 precedent).
public enum DiskMapCommandRefusal: Sendable, Equatable {
    case notBrowsing
    /// The stream is still running: totals are not yet true, so no
    /// confirmation could name honest counts.
    case mappingStillRunning
    case emptySelection
    case permanentDeletionUnconfirmed(required: PermanentDeletionScope)
    case confirmationMismatch(required: PermanentDeletionScope)
}
```

PermanentDeletionScope moves from the cleanup module to GleamCore beside
PermanentDeletionConfirmation (C6) in this slice, shared by C38 and C39,
unchanged in shape. Every CleanupModuleTests file already imports GleamCore,
so the move breaks no test source.

```swift
/// The Disk Map module view model, on the macOS 14 Observation framework.
/// A thin SwiftUI view renders this and adds no state of its own; the
/// module's whole behaviour is this class driven against fakes of its five
/// injected protocols.
///
/// Guarantees:
///
/// State transitions are total and deterministic; every command in every
/// state either performs its named transition or leaves the state
/// identical. The table, everything else being the identity:
/// - `startMapping(volume:)`: idle, browsing or result to mapping with a
///   fresh session and an empty map state focused on the volume root.
///   Ignored while mapping or executing.
/// - Stream driven, while mapping: `node` and `sizeRevision` updates grow
///   the tree under the node guarantees above; `completed` prunes any
///   unmatched intentions and moves mapping to browsing with the map
///   state otherwise identical (tree, focus and every resolved
///   selection survive the transition); a thrown stream moves to idle
///   with `failureNotice` set to a plain sentence.
/// - `drillIn(to:)`: mapping or browsing. When the target is a directory
///   child of the current focus present in the tree, focus moves there
///   and the returned drill carries zoomIn. While mapping, a target
///   whose node has not yet streamed is also accepted, as a drill
///   intention: the drill is returned, the model reconciles the
///   intention onto the node when it arrives, and prunes it at
///   completion if no node matched, with focus falling back to the
///   deepest streamed ancestor (the volume root at worst). In browsing,
///   anything else returns nil and changes nothing.
/// - `drillOut()`: mapping or browsing, when focus is not the volume root:
///   focus moves to its parent and the returned drill carries zoomOut. At
///   the root it returns nil and changes nothing; leaving the module is
///   the chrome's job, not this model's.
/// - `toggleSelection(_:)`: mapping or browsing, selection change only. A
///   selected path deselects. An unselected selectable path selects, first
///   removing any selected descendants (the ancestor covers them). While
///   mapping, a path whose node has not yet streamed is accepted as a
///   selection intention rather than ignored: the model reconciles it as
///   nodes arrive and prunes it at completion if no node matched.
///   Denylisted nodes and the volume root are never selectable whenever
///   an intention resolves: such an intention is dropped at resolution,
///   never selected. A path that is unselectable, covered by a selected
///   ancestor, or unknown in browsing is the identity, which keeps the
///   antichain and the denylist rule true by construction.
/// - `executeSelection`: browsing to executing when admitted; otherwise
///   the named refusal is returned and nothing changes: mappingStillRunning
///   while mapping, notBrowsing in every other non browsing state, then
///   emptySelection, then the confirmation refusals.
/// - `cancelMapping`: mapping to idle, the partial map discarded. Safe by
///   construction: mapping is read only (C13, C15, C22) and a cancelled
///   map has no side effects on disk.
/// - `cancelExecution`: cancels the running plan; cancellation takes
///   effect between operations, never mid item (C17). The state remains
///   executing until the executor's terminal report arrives, then moves to
///   result, whose summary is the partial result screen.
/// - `acknowledgeResult`: result to idle. Never back to a map: see
///   DiskMapModuleState.idle.
///
/// Deletion, the C38 path exactly:
/// - `executeSelection` mints one Finding per selected node: category
///   `diskMapSelection`, risk `review`, never preselected (C22), the
///   map's session identifier, and exactly one entry carrying the node's
///   path and its converged `allocatedBytesSoFar` (C5). Byte totals
///   therefore derive from the finding's own entries; no cache, no second
///   source of truth.
/// - The plan is built through the engine's `plan` with a plan context for
///   the map session and the settings store's current settings, so the
///   deletion mode is honoured at the moment of the command (C15, C12):
///   Trash by default, `deletePermanently` only when the user opted in,
///   identical to Cleanup.
/// - `permanentDeletionScope()` returns, while browsing, the exact
///   operation count and byte total the current selection would plan as
///   `deletePermanently` under the current mode: every selected node when
///   the mode is permanent, nil when the mode is trash. Nil in every other
///   state. The view puts these exact counts in the confirmation it shows
///   (C6).
/// - The model attaches the caller's confirmation to the plan and never
///   constructs one itself; the confirmation is evidence the user saw the
///   counts (C6). A nil confirmation against a non nil scope returns
///   `permanentDeletionUnconfirmed`; mismatched counts return
///   `confirmationMismatch`; both refuse before the engine or executor is
///   touched.
/// - A `plan` throw leaves the state browsing and sets `failureNotice` to
///   a plain sentence.
/// - The executor's stream drives executing; its terminal report (C17,
///   exactly one, whatever happened) moves to result. An ExecutionRefusal
///   surfaces as a failure sentence in the summary, never a crash and
///   never a silent drop.
///
/// The hub:
/// - There is no hub estimate interplay. Disk Map has no HubModule case
///   (C36), contributes nothing to HubMachineState.moduleFigures or
///   reclaimableEstimateBytes, and its reclaimed bytes surface only on its
///   own result screen. A test asserts the model exposes no hub figure.
///
/// Full Disk Access:
/// - `startMapping` reads the store's current settings and the monitor's
///   current grant (C32), and mints one scan context through the session
///   provider. Without the grant the map covers what the user domain
///   allows (C15). The cost is stated plainly: DiskMapUpdate (C22)
///   carries no degraded events, so s2d ships no degraded banner in this
///   module; the honest banner arrives if C22 gains a degraded surface.
///
/// Purity and isolation:
/// - The model holds only its five injected protocols and never touches
///   the file system; the disk is reachable only through the engine's map
///   stream and the executor (C13 and C14 never appear here).
/// - No clock reads: every date the model holds arrived in an input.
/// - `failureNotice` is always a plain sentence, set only by a failed map
///   stream or a failed plan build, cleared by the next `startMapping`.
/// - Construction traps unless `engine.module == .diskMap`.
@MainActor @Observable
public final class DiskMapModuleModel {
    public private(set) var state: DiskMapModuleState
    public private(set) var failureNotice: String?

    public init(
        engine: any DiskMapProviding,
        executor: any PlanExecuting,
        settings: any SettingsStoring,
        sessions: any DiskMapSessionProviding,
        access: any FullDiskAccessMonitoring
    )

    public func startMapping(volume: AbsolutePath)
    @discardableResult
    public func drillIn(to path: AbsolutePath) -> DiskMapDrill?
    @discardableResult
    public func drillOut() -> DiskMapDrill?
    public func toggleSelection(_ path: AbsolutePath)
    public func permanentDeletionScope() -> PermanentDeletionScope?
    @discardableResult
    public func executeSelection(
        permanentConfirmation: PermanentDeletionConfirmation?
    ) -> DiskMapCommandRefusal?
    public func cancelMapping()
    public func cancelExecution()
    public func acknowledgeResult()
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
- The helper serves exactly one client identity, and that identity is real
  before release. `ExpectedClientIdentity.macGleamApp` (C31) carries a stand
  in team identifier until the Developer ID exists, and the release pipeline
  fails a signed build whose expected team identifier is not the Developer ID
  team (s7b). Every other guarantee in the helper assumes this check bites,
  so a placeholder left here removes all of them at once and breaks no test.
- Every privileged launch item change is attributable, and a direct toggle
  is attributable to itself. `ChangeAttribution` (C24) has no case meaning
  none and no optional field, the manager's parameter carries no default, and
  C30's request cannot be constructed without one, so an unattributed change
  fails to compile rather than failing a test. A planned change names the plan
  and the operation the executor is running (C17). A switch flipped in the
  interface names a change identifier minted at that moment, which appears in
  no plan and in no ExecutionReport, so nothing is ever reconciled to a plan
  that never existed. The helper echoes whichever it was as the reply's
  `correlationID`, which is how a refusal finds its way back to the thing that
  caused it.
  True end to end as of s3f, 2026-08-12. The attribution is on the wire, the
  reply slot is `correlationID`, and `HelperClient` is the production
  `PrivilegedLaunchItemChanging`, so a system scope change made in the
  interface has a path that carries its own identifier the whole way and back.
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
- Nothing that clears user visible data is ever preselected, and nothing
  that clears it is reachable from a scan nobody opened. The rule is
  stated over `MaintenanceTask.clearsUserVisibleData` (C7) rather than
  over a list of tasks, so a task added later inherits it: the engine
  never preselects such a finding (C5, C23), and no Full Sweep plan ever
  contains one (C29). Preselection is consent inferred from somebody
  having read the row, so a warning that exists to be read cannot sit
  behind a row that is never opened. Four contracts carry a piece of
  this, which is why it is written here as well.
