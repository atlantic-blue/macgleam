# System Design: MacGleam

A macOS care app with feature parity with CleanMyMac 5, differentiated on
interaction and motion quality. MacGleam is the working name through development; a
trademark search happens before launch. Everything here was agreed with Julian in
the design session of 2026-08-09.

## Requirements

### Functional

**Hub (the signature surface)**
- One window. A living status scene (the orb) in the centre, six module cards
  arranged around it: Full Sweep, Cleanup, Protection, Performance, Applications,
  Leftovers. Disk Map and Settings reachable from the hub chrome.
- Selecting a card zooms into the module with a matched geometry transition. Escape
  or the back control zooms out. The hub is never more than one gesture away.
- The status scene reflects real machine state: last scan time, reclaimable space
  estimate, threat state, and it changes visibly with each app state (see the
  Interaction and Motion section).

**Full Sweep (v1 ships three of five jobs)**
- One scan runs deep clean (Cleanup), storage deleftovers (Leftovers large and old
  files) and performance boost (Performance maintenance) concurrently and presents
  one combined result with per job detail.
- Threat scan and software updates join Full Sweep in later milestones once the
  Protection and Applications modules exist. Full Sweep never shows a stub job.
- The combined result screen lets the user review and deselect before running, and
  shows one summary number (space to reclaim, issues found).

**Cleanup**
- Scans system junk: user and app caches, logs, broken downloads, Xcode derived
  data and simulator caches, browser caches, temporary files.
- Scans mail attachments (local copies only) and all trash bins (user trash,
  external volume trashes).
- Every category is itemised and inspectable down to the file path before removal.
  Nothing risky is preselected.
- Removal moves files to Trash by default so the user can restore from a place they
  already know. A setting enables permanent delete for users who opt in, gated by
  an explicit confirmation naming the byte count and file count.

**Protection**
- Malware and adware scan built on Apple's published XProtect YARA rules plus a
  curated adware and persistence path list that we maintain. Honest labelling:
  malware and adware removal, not antivirus.
- Detection targets: known malware binaries by YARA signature, adware launch
  agents and daemons, suspicious browser extensions, known unwanted app paths.
- Findings are quarantined, never silently deleted. Quarantine means: moved to the
  MacGleam SafetyNet store, permissions stripped, original path and metadata recorded,
  restorable for 30 days with one click, then eligible for purge with confirmation.
- Privacy cleanup: browser history, cookies and site data per browser, recent item
  lists, Wi-Fi network history. Each item explicitly selected by the user.
- Rule updates ship through a signed rules channel independent of app releases.

**Performance**
- Maintenance tasks: flush DNS cache, rebuild Launch Services and Spotlight
  reindex triggers, purge memory pressure, run periodic maintenance equivalents.
- Login items and background items: list SMAppService and legacy launch agents and
  daemons per app, allow disable and enable, and reveal the owning app.
- Live memory and processor load view with the heaviest processes; quitting a
  process requires explicit confirmation naming the process.

**Applications**
- Full uninstall: the app bundle plus its leftovers (preferences, caches,
  containers, application support, launch agents), itemised before removal.
- Uninstall archives everything to the SafetyNet store before deletion so an
  uninstall is reversible for 30 days.
- Leftover sweep finds orphaned files from apps already deleted.
- Updater ships in a later milestone (it feeds Full Sweep's fifth job).

**Leftovers**
- Duplicate finder by content hash, similar photo detection, large and old files
  (size and last opened thresholds, user tunable), downloads triage.
- Duplicate resolution always keeps at least one copy; the kept copy is shown
  before anything moves.

**Disk Map**
- Visual disk map, drill in by folder size, scan of any volume the app can read.
  Delete from the map obeys the same Trash default as Cleanup.

**Menu bar monitor (v1 minimal)**
- Storage, memory and processor load at a glance, one quick clean action that
  opens the app on the Full Sweep result. Battery and network stats deferred.

**Onboarding**
- First run explains and requests Full Disk Access with a guided flow: an in app
  explanation of why, a button that deep links to System Settings Privacy and
  Security, live detection of the grant so the flow advances by itself, and a
  degraded but functional mode when the user declines (user domain scanning only,
  with an honest banner of what is unavailable).
- The privileged helper is only requested when the user first runs an operation
  that needs it (Performance maintenance, protected path removal), never at first
  launch.

**Licensing**
- 14 day full trial, no feature gates during trial. One time licence at launch
  (29 to 39 dollar range), paid major upgrades. Offline licence validation with
  a signed licence file; the payment processor (likely Paddle) is a launch
  milestone decision.

### Non Functional

- Scan performance: a full Cleanup scan of a typical 512 GB system disk completes
  in under 60 seconds; Disk Map maps a full volume in under 30 seconds on Apple
  silicon. Directory enumeration uses getattrlistbulk with 4 to 8 concurrent
  readers per volume (APFS serialises directory reads past that).
- Animation: no dropped frames during the hub zoom and scan progress on a 60 Hz
  display, and ProMotion aware on 120 Hz. Motion honours Reduce Motion.
- Memory: under 500 MB resident during the largest scan; results stream and
  aggregate rather than accumulate full file lists in memory.
- App size: under 80 MB installed. Launch to interactive hub in under one second
  on Apple silicon.
- Reliability: a crashed or cancelled scan never leaves partial deletions; all
  destructive work happens after scanning, from an explicit plan, atomically per
  item.
- Privacy: no analytics by default, no file names or paths ever leave the machine.
  Network traffic is limited to the Sparkle appcast, the signed rules channel and
  licence activation. This is a stated product promise.
- Accessibility: WCAG AA contrast, full keyboard navigation of the hub and
  modules, VoiceOver labels on every finding row, Reduce Motion and Reduce
  Transparency respected.

### Constraints

- macOS 14 (Sonoma) floor. Required by the animation stack (phaseAnimator,
  keyframeAnimator, Metal shader view modifiers, Observation framework).
- Swift 6 with strict concurrency, SwiftUI first, AppKit interop only where
  SwiftUI falls short (menu bar popover sizing, window chrome, drag sessions).
- Direct distribution: Developer ID signing, hardened runtime, notarization,
  disk image plus Sparkle updates. Not App Store; Full Disk Access dependent
  features and the privileged helper do not survive App Store review.
- Original branding and assets throughout. Feature parity is the target;
  MacPaw's name, artwork and copy are never reproduced.
- Solo developer with agent support, Greenlight process: contracts first, test
  driven development, vertical slices.
- Continuous integration on GitHub Actions macOS runners; signing and
  notarization in the pipeline, never from a laptop.

### Out of Scope (v1)

- Cloud Cleanup module (cloud storage analysis).
- Application updater and the Full Sweep software updates job.
- Assistant and suggestions layer beyond the per scan summary.
- Battery and network stats in the menu bar.
- iOS device backups cleanup, Time Machine snapshot thinning.
- Localisation beyond English.
- Teams, multi seat licensing, mobile device management deployment.

## Technical Decisions

Each decision as: what was decided, what was rejected, and why.

- **macOS 14 floor.** Rejected: macOS 12 or 13 for wider reach. The interaction
  layer is the product and phaseAnimator, keyframeAnimator, shader view effects
  and Observation all require 14. SMAppService needs 13, so 14 costs nothing
  there.
- **Malware detection from Apple's public XProtect YARA rules plus a curated
  adware list.** Rejected: commercial signature feed (recurring cost, licensing
  friction for v1) and heuristics only (too weak to be honest about). YARA
  scanning via a vendored YARA library; our rules channel ships updates signed
  with our key. Quarantine only, never silent delete.
- **One time licence, 14 day full trial.** Rejected: subscription. Everything
  runs locally with no per user server cost, and pay once is the clearest wedge
  against CleanMyMac's subscription. Paid major upgrades fund development.
- **Sparkle 2 for updates.** Rejected: custom updater (undifferentiated effort,
  high risk surface). EdDSA signed appcast over HTTPS, delta updates, standard
  for Developer ID direct distribution.
- **Full Sweep ships three of five jobs.** Rejected: shipping all five with
  stubbed threat scan and updater. Jobs appear only when their backing module is
  real.
- **Hub with zoom navigation, no sidebar.** Rejected: CleanMyMac style sidebar
  (safer, less distinctive). The hub is the signature interaction and the
  differentiator made visible.
- **SMAppService daemon for privileged operations, XPC between app and helper.**
  Rejected: SMJobBless (deprecated), shelling out with AppleScript authorization
  (fragile, poor UX). XPC is Apple's inter process communication mechanism; the
  helper is a root daemon registered via SMAppService.daemon and approved once in
  System Settings.
- **Engines as pure Swift packages behind protocol boundaries.** Rejected:
  engines living inside the app target. Isolation makes test driven development
  real: every engine is testable against an in memory file system without
  touching a real disk.
- **Deletion defaults to Trash; malware and uninstalls go to the SafetyNet
  quarantine store.** Rejected: immediate permanent deletion (CleanMyMac
  behaviour for junk). Reversibility is a trust feature and trust is the market's
  sore point with cleaner apps.
- **getattrlistbulk enumeration with bounded concurrency.** Rejected: naive
  FileManager enumeration (one stat call per file, several times slower on large
  trees). Note the Sequoia regression where getattrlistbulk can repeat entries;
  the enumerator must deduplicate by file id and carry a regression test.
- **Menu bar monitor as a separate lightweight scene in the main app process.**
  Rejected: separate login item process for v1 (adds an installation surface
  before it earns it). Revisit if memory footprint demands it.
- **MacGleam stays the working name.** Trademark search before launch. Naming does
  not block architecture; the bundle identifier namespace is
  com.atlanticblue.macgleam until then.

## Architecture

Three processes, one app bundle:

- **MacGleam.app** (SwiftUI, runs as the user). Owns all UI, all scanning that user
  permissions allow (which, with Full Disk Access, is nearly everything), plan
  construction and the SafetyNet store. Hosts the menu bar scene.
- **GleamHelper** (root daemon, SMAppService.daemon, embedded in the bundle).
  Executes only the operations that genuinely need root: removing files outside
  the user domain, running maintenance tasks, managing other users' launch
  items. Installed lazily on first need.
- **Sparkle's XPC services** (bundled by the framework) handle update install.

Communication: XPC with codable message types defined in a shared package. The
helper verifies the connecting client's code signing identity (team id and bundle
id via the audit token) before accepting any message. The app treats the helper
as untrusted too: replies are validated.

Internal structure is a Swift Package workspace:

- **GleamDesign**: design tokens, motion tokens, shared components, the status
  scene. No business logic.
- **GleamCore**: shared domain model (findings, plans, operations, sessions),
  the FileSystem protocol, the enumeration engine, the SafetyNet store.
- **Engines**, one package target each, all depending only on GleamCore:
  CleanupEngine, ProtectionEngine (wraps YARA), PerformanceEngine,
  ApplicationsEngine, LeftoversEngine, DiskMapEngine, and FullSweepOrchestrator
  which composes the others.
- **GleamHelperCore**: the XPC contract types and the helper's operation policy,
  shared by app and helper so the contract cannot drift.
- **GleamApp**: the app target, thin composition of the above.

Every engine follows the same shape: scan(context) streams findings, plan(
selection) produces an operation plan, and execution happens in GleamCore's
executor which routes each operation to the user process or the helper based on
path ownership. Engines never delete anything themselves.

### Rules and knowledge base

Safe to clean paths, adware signatures and system critical denylists live in a
versioned, signed rules bundle: a baseline ships in the app, updates come from
our rules channel (static hosting, Ed25519 signed manifest). The denylist (paths
that must never be touched, whatever a rule says) is enforced independently in
both the app executor and the helper, so a bad rules update cannot cross it.

## Data Model

Conceptual entities; the architect turns these into typed contracts.

- **ScanSession**: id, module, started and finished timestamps, state, streamed
  counters (files seen, bytes reclaimable).
- **Finding**: id, session id, category, paths, byte size, risk level (safe,
  review, dangerous), explanation text, preselected flag. Findings are the unit
  of user review.
- **OperationPlan**: id, ordered operations derived from selected findings, total
  bytes, destinations (trash, safety net, permanent).
- **Operation**: one atomic action (move to trash, quarantine, disable launch
  item, run maintenance task), with target, required privilege level, and result.
- **SafetyNetItem**: id, origin path, stored path, source (malware quarantine,
  uninstall archive), metadata snapshot, expiry date, restored flag.
- **AppInventoryEntry**: bundle id, name, version, install location, discovered
  leftover paths.
- **RuleCatalog**: version, signature, cleanup rules, adware rules, denylist.
- **LicenceState**: trial start, licence key, validation state.
- **Settings**: deletion mode, menu bar preferences, motion preferences,
  scan schedules.

Persistence: SwiftData or plain codable stores per concern (the architect
decides per contract); the SafetyNet manifest must survive app reinstall, so it
lives in Application Support with the quarantined payloads.

## Interaction and Motion Design

This is the product. The architect and every slice treat this section as
binding, not decorative.

### Design tokens (GleamDesign package)

- Colour: a deep neutral base (near black blues), one iridescent accent drawn
  from the orb motif, semantic colours for safe, review and dangerous. Dark
  and light appearances from day one. WCAG AA minimum contrast.
- Type: SF Pro with a modular scale (one display size for the hub number, three
  text sizes, one mono size for paths). No custom typeface in v1.
- Spacing on an 8 point grid, two corner radii (cards, controls), three
  elevation levels expressed as material plus shadow tokens.
- Motion tokens, the canonical spring set used everywhere:
  - snappy: response 0.30, damping 0.85. Navigation, selection, toggles.
  - gentle: response 0.55, damping 0.90. Layout settles, list reflow.
  - lively: response 0.40, damping 0.70. Celebration moments only.
  - Durations for non spring fades: 150 ms micro, 250 ms standard.
- No animation outside the token set. A new curve is a design decision, not a
  local choice.

### The status scene (the orb)

A Metal shaded orb (colorEffect and layerEffect shaders on a SwiftUI canvas)
that is the emotional centre of the app. Its states:

- **Idle, healthy**: slow breathing scale (about 6 second period), soft
  iridescent sheen drifting across the surface. Below it, one line: last scan
  and current reclaimable estimate.
- **Idle, attention needed**: the sheen warms toward the review colour, the
  breathing quickens slightly, a single line names the top issue. Never red,
  never alarmist.
- **Scanning**: the orb becomes the progress surface: a shimmer band orbits it,
  a live counter of bytes found ticks with a numeric text content transition,
  and the module cards dim except the ones being scanned.
- **Result**: the orb pulses once with the lively spring and presents the
  summary number; particles are allowed here and nowhere else.
- **Clean sweep** (nothing found): a calm lustre bloom. An empty result is a
  reward moment, designed, not a blank panel.

Reduce Motion replaces the orb's animation with a static gradient and
crossfades; the shimmer becomes a determinate ring.

### Hub choreography

- The six cards orbit the orb in a fixed hexagonal layout, each carrying its
  own live figure (Cleanup: reclaimable estimate; Protection: last scan;
  Performance: memory pressure; and so on). Cards breathe subtly on hover
  (scale 1.02, snappy).
- Entering a module: matched geometry zoom. The card expands to fill the window
  (snappy spring), the hub scales down to 0.94 and blurs behind it, the card's
  title travels to the module header. Target: one continuous motion, no
  crossfade seams.
- Leaving: exact reverse, triggered by Escape, the back control, or a trackpad
  swipe. State inside a module survives the round trip.
- Keyboard: arrow keys walk the cards, Return enters, Escape leaves. Full
  operation without a pointer.

### Per module choreography

- **Scan progress (all modules)**: three phases with a phaseAnimator:
  indeterminate sweep (first 500 ms), determinate progress with live counters
  once the enumerator has an estimate, then a settle phase where counters
  resolve to finals with the gentle spring. Counters only ever count up;
  jitter is smoothed.
- **Findings lists**: results stream in grouped by category; rows insert with a
  staggered gentle spring (30 ms stagger, capped at 8 staggered rows so large
  results do not turn into a light show). Selection checkmarks use the snappy
  spring. Deselecting a category collapses it with layout animation, never a
  jump cut.
- **Execution**: selected rows lift slightly, then fly toward the summary
  figure as they complete (keyframeAnimator, capped particle count), the
  reclaimed number ticks up in real time. Failures stay in place with the
  review colour and a plain sentence saying why.
- **Disk Map**: the disk map builds outward from the root as data streams,
  blocks growing with the gentle spring; drilling in is the same zoom grammar
  as the hub so the whole app has one navigation language.
- **Uninstall**: the app icon and its leftover rows gather into a single stack
  before moving to the SafetyNet, making visible that the removal is one
  reversible unit.

### Empty, error and permission states

- Every module has a designed empty state that says what was checked and when,
  not a grey placeholder.
- Permission gaps render as an inline card naming exactly what is unavailable
  and one button to fix it, never a modal wall.
- Errors are sentences, not codes: what failed, what was and was not done, and
  the one action available.

## Safety and Reversibility

Every destructive operation is reversible or explicitly confirmed. The
mechanisms, by operation:

- **Junk, leftovers and Disk Map deletions**: default destination is the macOS
  Trash, restorable by the user with tools they already know. The permanent
  delete setting is off by default and every permanent run confirms with file
  count and byte total.
- **Malware and adware findings**: always quarantined to the SafetyNet store
  (moved, permissions stripped, execution impossible), restorable for 30 days,
  purged only with explicit confirmation.
- **App uninstalls**: the bundle and all leftovers are archived to the
  SafetyNet before removal; restore reinstates every file at its original path.
- **Login and background item changes**: disable, never delete; re enabling is
  one click. The prior state is recorded per change.
- **Maintenance tasks**: non destructive by design; anything that clears user
  visible data (such as DNS cache) says so before running.
- **Process quit**: explicit confirmation naming the process; force quit is a
  second, separate confirmation.
- **The denylist**: system critical paths are unremovable regardless of rules,
  selections or helper requests, enforced in both processes.
- **Atomicity**: plans execute item by item; a cancelled or crashed run leaves
  completed items completed and untouched items untouched, with the result
  screen saying exactly which is which. No partial file operations.

## Security Model

- **Least privilege**: the helper implements a closed set of typed operations,
  not a general file service. Each request carries the operation, the target
  and the plan id; the helper re validates the target against the denylist and
  the path ownership policy before acting. No arbitrary command execution, no
  shell.
- **Mutual verification**: the helper accepts connections only from the exact
  app identity (team id plus bundle id, checked via audit token code signing
  requirement). The app validates helper replies against the contract.
- **No exfiltration by design**: no file names, paths, or scan contents ever
  leave the machine. Outbound network is exactly three endpoints: Sparkle
  appcast, rules channel, licence activation. Each is HTTPS with certificate
  system trust, and update and rules payloads are additionally Ed25519 signed.
- **Transparency Consent and Control**: Full Disk Access is requested with
  explanation, functional degradation is honest, and the app never nags on a
  schedule.
- **Supply chain**: YARA is vendored and built from a pinned tag; Sparkle is
  pinned by version and checksum. Releases are built in continuous integration,
  signed with Developer ID, notarized and stapled there.
- **Quarantine hygiene**: SafetyNet payloads are stored with execute permission
  removed and extended attributes preserved for restore fidelity.

## Deployment

- GitHub Actions on macOS runners: build, test (unit, engine fixtures, XPC
  contract tests, UI tests), then on tag: archive, sign app and helper,
  notarize, staple, build the disk image, generate the Sparkle appcast entry
  with the EdDSA signature, publish to the release bucket.
- Environments: dev builds unsigned locally; a beta appcast channel precedes the
  stable channel from the first external tester onward.
- The rules channel is a separate static bucket with its own signing key and its
  own publish workflow, so rules can move without an app release.
- Website, purchase flow and licence issuing are launch milestone work.

## Deferred

- Cloud Cleanup module: needs provider integrations, none of the scan engine
  work is wasted; revisit after launch.
- Application updater and Full Sweep jobs four and five: needs a version
  metadata source; design when Applications module is live.
- Assistant and suggestions layer: needs usage patterns to suggest from.
- Commercial malware signature feed: revisit if the XProtect plus curated list
  approach misses real world adware users report.
- Scheduled background scanning: needs the menu bar presence to mature first.
- Battery and network menu bar stats, localisation, a custom display typeface,
  App Store companion utility: all post launch considerations.

## User Decisions

Locked with Julian, 2026-08-09:

- Hub with zoom navigation is the signature interaction; sidebar rejected.
- One time licence, 14 day full trial, 29 to 39 dollars at launch, paid major
  upgrades, processor likely Paddle (deferred to launch milestone).
- macOS 14 floor.
- Malware v1 is XProtect YARA rules plus a curated adware list, quarantine only.
- Sparkle 2 for updates.
- Full Sweep ships three of five jobs; the remaining two arrive with their
  modules.
- MacGleam remains the name through development; trademark search before launch.
- Menu bar monitor ships minimal in v1: storage, memory, processor, one action.
