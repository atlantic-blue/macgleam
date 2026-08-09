# Dependency Graph: MacGleam

Companion to CONTRACTS.md. Slices are thin vertical paths of user value,
mapped onto milestones M0 to M7 from ROADMAP.md. Each slice is sized so one
agent completes it within half a fresh context window. Contract numbers (C1 to
C38) refer to CONTRACTS.md.

Reading a slice entry:

- Depends on lists only real dependencies: the slice's tests cannot pass
  without them. Transitive dependencies are not repeated.
- Verification names the behaviour a test proves when the slice is done.
- Tier is auto (tests passing fully captures correctness) or verify (a human
  checks the named behaviour on a real machine before the slice closes).
  Every interface slice is verify because interaction quality is the product.

## Dependency diagram

Validated with the mermaid command line renderer on 2026-08-09.

```mermaid
flowchart TB
    subgraph m0["M0 foundation and hub shell"]
        s0a["s0a tokens and workspace"]
        s0b["s0b hub shell"]
        s0c["s0c hub zoom"]
    end
    subgraph m1["M1 the first clean"]
        s1a["s1a domain model"]
        s1b["s1b file system"]
        s1c["s1c rules baseline"]
        s1d["s1d cleanup scan"]
        s1e["s1e executor"]
        s1f["s1f disk access onboarding"]
        s1g["s1g cleanup module"]
    end
    subgraph m2["M2 clutter and space lens"]
        s2a["s2a large and old files"]
        s2b["s2b duplicates"]
        s2c["s2c similar photos"]
        s2d["s2d space lens"]
        s2e["s2e performance gates"]
    end
    subgraph m3["M3 performance and helper"]
        s3a["s3a helper contract"]
        s3b["s3b helper daemon"]
        s3c["s3c maintenance"]
        s3d["s3d login items"]
        s3e["s3e process monitor"]
    end
    subgraph m4["M4 applications"]
        s4a["s4a safety net store"]
        s4b["s4b app inventory"]
        s4c["s4c uninstall"]
        s4d["s4d leftover sweep"]
    end
    subgraph m5["M5 protection"]
        s5a["s5a malware scan"]
        s5b["s5b quarantine flow"]
        s5c["s5c privacy cleanup"]
        s5d["s5d rules channel"]
    end
    subgraph m6["M6 smart care and menu bar"]
        s6a["s6a orchestrator"]
        s6b["s6b smart care surface"]
        s6c["s6c menu bar"]
    end
    subgraph m7["M7 launch"]
        s7a["s7a sparkle updates"]
        s7b["s7b release pipeline"]
        s7c["s7c licensing"]
    end

    s0a --> s0b --> s0c
    s0a --> s1a
    s1a --> s1b
    s1a --> s1c
    s1b --> s1d
    s1c --> s1d
    s1b --> s1e
    s1c --> s1e
    s0c --> s1f
    s1d --> s1g
    s1e --> s1g
    s1f --> s1g
    s1g --> s2a --> s2b --> s2c
    s1g --> s2d
    s2a --> s2e
    s2d --> s2e
    s1a --> s3a
    s1c --> s3a
    s3a --> s3b
    s1e --> s3b
    s3b --> s3c
    s1g --> s3c
    s3c --> s3d
    s3c --> s3e
    s1b --> s4a
    s1b --> s4b
    s1c --> s4b
    s4a --> s4c
    s4b --> s4c
    s1g --> s4c
    s4c --> s4d
    s1b --> s5a
    s1c --> s5a
    s5a --> s5b
    s4a --> s5b
    s1g --> s5b
    s1g --> s5c
    s1c --> s5d
    s3b --> s5d
    s1d --> s6a
    s2a --> s6a
    s3c --> s6a
    s6a --> s6b --> s6c
    s0a --> s7a --> s7b
    s0c --> s7c
    s1a --> s7c
```

The first wave (no dependencies beyond s0a) is wide on purpose: s0b, s1a and
s7a can start in parallel the moment the workspace exists.

---

## M0. Foundation and the hub shell

### s0a. tokens and workspace
- Contracts: C1, C2.
- Depends on: nothing.
- Includes the repo cut, the Swift package workspace and continuous
  integration with test and lint gates, folded in because infrastructure
  alone is not a slice.
- Verification: token values match the contract exactly (spring responses,
  damping, fade durations, grid unit); semantic colours pass the Web Content
  Accessibility Guidelines AA contrast threshold in both appearances; the
  Reduce Motion mapping returns a crossfade, never a spring; continuous
  integration runs the suite on a macOS runner and fails on an empty test run.
- Tier: auto.

### s0b. hub shell
- Contracts: C36 (hub shell model), consuming C1, C2.
- Depends on: s0a.
- Verification: the hub renders the orb with its two idle states (healthy,
  attention needed) and six placeholder cards in the hexagonal layout; mood,
  status line and card derivation are pure functions of HubMachineState,
  driven in tests without any view; the appearance resolver is total over
  every mood and Reduce Motion pair and never returns a spring under Reduce
  Motion; the card order is the fixed HubModule order.
- Tier: verify. Human check: the orb breathes at roughly a 6 second period,
  the sheen reads as calm not busy, both appearances look intentional.

### s0c. hub zoom
- Contracts: C37 (hub navigation model), consuming C1, C2, C36.
- Depends on: s0b.
- Verification: entering and leaving a card round trips with matched
  geometry; module state survives the round trip; arrow keys walk the cards,
  Return enters, Escape leaves; full operation without a pointer; Reduce
  Motion replaces the zoom with a crossfade.
- Tier: verify. Human check: the zoom is one continuous motion with no
  crossfade seams and no dropped frames on a 60 hertz display.

## M1. The first clean

### s1a. domain model
- Contracts: C3, C4, C5, C6, C7, C8, C9, C10, C11, C12 (types and their
  invariants; no protocols implemented yet).
- Depends on: s0a.
- Verification: path normalisation and descendant checks; counter
  monotonicity; plan and confirmation matching rules; denylist pattern
  matching including descendant blocking; all types round trip through
  Codable losslessly.
- Tier: auto.

### s1b. file system
- Contracts: C13, C14, plus the in memory implementation every engine test
  uses and the real enumerator.
- Depends on: s1a.
- Verification: the in memory and real implementations pass one shared
  conformance suite; enumeration never yields a duplicate (volumeID, fileID)
  pair even when the platform repeats entries (the Sequoia regression test,
  driven by a repeating fake); inaccessible directories are reported, not
  thrown; cancellation stops promptly and mutates nothing; moves are atomic
  per item.
- Tier: auto.

### s1c. rules baseline
- Contracts: C19 (baseline load and signature verification), completing C10.
- Depends on: s1a.
- Verification: the embedded baseline loads and verifies; a tampered
  catalogue is rejected and current rules are untouched; a lower or equal
  version is rejected; the effective denylist is the union of baseline and
  catalogue and can never lose a baseline entry.
- Tier: auto.

### s1d. cleanup scan
- Contracts: C15, C20.
- Depends on: s1b, s1c.
- Verification: against fixture trees the engine finds each junk category
  with itemised paths; nothing risky is preselected even when a hostile
  catalogue says preselectable; degraded mode reports what was skipped;
  phases advance in order and counters only count up; scanning holds only
  the reading side of the file system.
- Tier: auto.

### s1e. executor
- Contracts: C16, C17 (user domain execution; helper routing lands in s3b).
- Depends on: s1b, s1c.
- Verification: operations run in order, atomically per item; a denylisted
  target is skipped and reported as such; a permanent plan without a
  matching confirmation is refused whole before anything runs; cancellation
  between items leaves completed items completed and reports exactly which
  is which; the report always arrives, whatever happened.
- Tier: auto.

### s1f. disk access onboarding
- Contracts: C32.
- Depends on: s0c.
- Verification: the flow advances by itself when the grant lands (driven by
  a fake monitor in tests); declining lands in degraded mode with the honest
  banner naming what is unavailable; the app never prompts on a schedule.
- Tier: verify. Human check: grant Full Disk Access in System Settings and
  watch the flow advance without touching the app.

### s1g. cleanup module
- Contracts: C38 (cleanup module model), wiring C15, C17, C20, C32, C35
  into the interface. Also implements C35 (settings store) since deletion
  mode is first exercised here.
- Depends on: s1d, s1e, s1f.
- Verification: the full first clean end to end against a fixture home:
  scan, review down to file paths, deselect, execute, result screen naming
  every outcome, files present in the Trash afterwards; empty state is the
  designed clean sweep, not a blank panel; permanent mode demands the counts
  confirmation. Carried through to what the user sees next: after execution
  the hub estimate reflects the reclaimed bytes.
- Tier: verify. Human check: run a real clean on a scratch account, restore
  a file from the Trash, confirm the choreography (staggered rows, fly to
  summary, ticking counter) uses only token motion.

## M2. Clutter and Space Lens

### s2a. large and old files
- Contracts: C21 (large, old, downloads triage portions).
- Depends on: s1g.
- Verification: threshold edges are exact (threshold minus one byte or day
  is not a finding); thresholds honour Settings; downloads triage groups by
  the review rules; end to end removal through the shared executor lands in
  Trash.
- Tier: verify. Human check: the My Clutter module surface reads as the same
  design language as Cleanup.

### s2b. duplicates
- Contracts: C21 (duplicate sets).
- Depends on: s2a.
- Verification: sets group by full content hash, never by size alone; the
  kept copy is a member of every set, shown in review, and no generated plan
  targets it under any selection, attacked with hostile selections; at least
  one copy always survives.
- Tier: verify. Human check: resolve a duplicate set and confirm the kept
  copy is visibly named before anything moves.

### s2c. similar photos
- Contracts: C21 (similar photo sets).
- Depends on: s2b.
- Verification: sets contain only image files and never overlap; kept path
  mechanics identical to duplicates; non photo libraries produce no sets.
- Tier: verify. Human check: grouping quality on a real photo folder is
  useful rather than noisy.

### s2d. space lens
- Contracts: C22.
- Depends on: s1g.
- Verification: the map streams and node totals only ever grow, converging
  to true allocated totals; denylisted nodes render but cannot be selected;
  deleting from the map follows the Trash default through the shared
  executor; drill in uses the shared zoom grammar.
- Tier: verify. Human check: the map builds outward from the root while
  scanning and drilling in feels identical to the hub zoom.

### s2e. performance gates
- Contracts: enforces the performance clauses of C20 and C22.
- Depends on: s2a, s2d.
- Verification: on a generated fixture of typical shape, the full Cleanup
  scan finishes under 60 seconds and the Space Lens map under 30 on Apple
  silicon; peak resident memory during the largest scan stays under 500
  megabytes; the gates run in continuous integration and fail on regression.
- Tier: auto.

## M3. Performance and the privileged helper

### s3a. helper contract
- Contracts: C30, C31 (types, policy, contract tests against a test double
  transport).
- Depends on: s1a, s1c.
- Verification: every message round trips the wire encoding losslessly; the
  policy refuses in the contract's evaluation order (identity, handshake,
  domain, denylist) with the right refusal each time; a user domain target
  is refused notSystemDomain; a denylisted target is refused whatever the
  request claims; version mismatch refuses everything after handshake.
- Tier: auto.

### s3b. helper daemon
- Contracts: implements C30, C31 in the real daemon; extends C17 with helper
  routing.
- Depends on: s3a, s1e.
- Verification: contract tests pass against the real daemon on a real
  machine; the executor routes systemDomain operations to the helper and
  validates replies; a malformed reply fails the one operation, not the run;
  the helper is registered lazily on first privileged need, never at first
  launch.
- Tier: verify. Human check: first privileged operation triggers the System
  Settings approval exactly once, and the app degrades honestly if approval
  is refused.

### s3c. maintenance
- Contracts: C23 (maintenance portion), first real helper consumer.
- Depends on: s3b, s1g.
- Verification: each maintenance task runs through the helper and is
  idempotent; tasks that clear user visible data say so before running; no
  PerformanceEngine plan ever contains a file removal operation.
- Tier: verify. Human check: run the Domain Name System cache flush and
  confirm the warning sentence appears first.

### s3d. login items
- Contracts: C24, C23 (login item portion).
- Depends on: s3c.
- Verification: inventory attributes items to owning apps; disable then re
  enable round trips through the recorded prior state and survives relaunch;
  user scope changes stay in process, system scope routes through the
  helper; disable never deletes.
- Tier: verify. Human check: disable a known login item, log out and in,
  confirm it did not launch, re enable with one click.

### s3e. process monitor
- Contracts: C25.
- Depends on: s3c.
- Verification: samples stream sorted heaviest first without blocking the
  main actor; quit demands the confirmation path and force is a second
  separate confirmation; a recycled process identifier is caught by the name
  check and nothing is killed.
- Tier: verify. Human check: the live view updates smoothly and quitting a
  test process names it in the confirmation.

## M4. Applications

### s4a. safety net store
- Contracts: C18 in full.
- Depends on: s1b.
- Verification: store strips execute permission and preserves extended
  attributes; restore reinstates path, permissions, attributes and dates
  exactly (fidelity asserted attribute by attribute); an occupied origin
  refuses and changes nothing; group restore is all or nothing; expiry marks
  eligibility only and purge demands matching counts; the manifest survives
  simulated app removal and reinstall.
- Tier: auto.

### s4b. app inventory
- Contracts: C9, C26 (inventory portion).
- Depends on: s1b, s1c.
- Verification: discovery against fixture bundles finds the app and each
  leftover kind; the association rule survives the adversarial fixtures
  (shared containers, colliding bundle identifier prefixes) without a single
  false association; MacGleam itself is never offered.
- Tier: auto.

### s4c. uninstall
- Contracts: C26 (uninstall), consuming C18.
- Depends on: s4a, s4b, s1g.
- Verification: an uninstall plan contains only archive operations under one
  group; after execution every file sits in SafetyNet and the app is gone;
  group restore reinstates every file at its original path; no uninstall
  plan can contain a trash or permanent operation.
- Tier: verify. Human check: uninstall a scratch app, watch the gather
  choreography present it as one reversible unit, restore it, launch it.

### s4d. leftover sweep
- Contracts: C26 (orphan sweep).
- Depends on: s4c.
- Verification: orphans from deleted fixture apps are found, never
  preselected, and removal follows the Trash default; files belonging to
  installed apps are never flagged as orphans.
- Tier: verify. Human check: sweep a real machine and read the findings for
  false positives before acting.

## M5. Protection

### s5a. malware scan
- Contracts: C27 (detection portion), C28.
- Depends on: s1b, s1c.
- Verification: seeded fixture binaries matching test YARA rules are found
  with their signature identifiers; adware launch items, extensions and
  unwanted paths from the curated list are found; one failing rule disables
  itself without sinking the scan; a detection plan contains only quarantine
  operations, proven over the generated plan space.
- Tier: auto.

### s5b. quarantine flow
- Contracts: C27 wired to C18 and the interface.
- Depends on: s5a, s4a, s1g.
- Verification: a detection quarantines into SafetyNet with execute
  permission stripped; one click restore within 30 days reinstates it;
  purge demands confirmation; nothing is ever silently deleted, asserted
  end to end.
- Tier: verify. Human check: quarantine a European Institute for Computer
  Antivirus Research test file, confirm it cannot execute from the store,
  restore it, confirm fidelity.

### s5c. privacy cleanup
- Contracts: C27 (privacy portion).
- Depends on: s1g.
- Verification: findings per browser and per data kind, none preselected;
  each removal clears exactly the selected item against fixture browser
  profiles; explanations name what is cleared.
- Tier: verify. Human check: clear one browser's cookies on a scratch
  profile and confirm history survived.

### s5d. rules channel
- Contracts: C19 (live channel), the channel publish workflow, helper
  catalogue adoption per C31.
- Depends on: s1c, s3b.
- Verification: a published update is fetched, verified and adopted; a
  tampered or replayed (older version) manifest is rejected leaving current
  rules intact; the helper only honours a catalogue it verified itself; the
  publish workflow signs with the rules key held only in that pipeline.
- Tier: auto.

## M6. Smart Care and the menu bar

### s6a. orchestrator
- Contracts: C29.
- Depends on: s1d, s2a, s3c.
- Verification: three jobs run concurrently with interleaved tagged events;
  one job failing leaves the other two fully usable and named in the
  summary; exactly one summary, after all jobs; the combined plan preserves
  every underlying engine invariant; no stub job can appear (the enum is the
  proof).
- Tier: auto.

### s6b. smart care surface
- Contracts: wires C29 to the hub; the orb's scanning, result and clean
  sweep states go live.
- Depends on: s6a.
- Verification: one combined result with per job detail and deselection;
  the orb reflects scanning (shimmer, live byte counter, non scanned cards
  dimmed), result (single lively pulse, particles here and nowhere else)
  and clean sweep; Reduce Motion swaps the shimmer for a determinate ring.
- Tier: verify. Human check: run Smart Care on a scratch account and judge
  the scene against the DESIGN.md choreography, including the empty result
  as a reward moment.

### s6c. menu bar
- Contracts: C33, the menu bar scene.
- Depends on: s6b.
- Verification: storage, memory and processor figures stream and agree with
  the hub's figures; the quick clean action opens the app onto Smart Care;
  the scene honours the menu bar preferences in Settings.
- Tier: verify. Human check: glanceability and footprint; the popover sizes
  correctly (the known AppKit interop seam).

## M7. Launch

### s7a. sparkle updates
- Contracts: Sparkle 2 integration, beta and stable appcast channels, the
  EdDSA appcast keys in the pipeline. No new package contracts; the
  no exfiltration invariant (CONTRACTS.md cross contract section) now covers
  the third permitted endpoint.
- Depends on: s0a.
- Verification: an update from the beta channel installs and relaunches; a
  tampered appcast entry is rejected; the appcast is one of exactly three
  outbound endpoints.
- Tier: verify. Human check: update a versioned build from the beta channel
  on a real machine.

### s7b. release pipeline
- Contracts: none new; the deployment section of DESIGN.md becomes a
  workflow.
- Depends on: s7a.
- Verification: on tag, continuous integration archives, signs app and
  helper, notarizes, staples, builds the disk image and publishes the
  signed appcast entry; the built artefact passes Gatekeeper assessment on
  a clean machine; no signing key ever exists on a laptop.
- Tier: auto.

### s7c. licensing
- Contracts: C34, completing C11.
- Depends on: s0c, s1a.
- Verification: trial boundaries against a controlled clock (day 14 versus
  day 15); verify is offline and network independent; activation exchanges
  a key for a signed licence and server failure leaves state untouched; no
  feature gate exists during trial, asserted by walking every module entry
  point in the trial state.
- Tier: verify. Human check: the trial and purchase surfaces read honestly,
  no dark patterns.

Launch also carries non engineering work with no contracts: the trademark
search resolving the MacGleam name, the branding pass, the website and
purchase flow. Tracked in ROADMAP.md, outside this graph.

---

## Open questions found while typing the design

Ambiguities and contradictions in DESIGN.md surfaced by writing the
contracts. Each names the resolution typed into CONTRACTS.md so reversing it
is one edit, not an archaeology dig.

1. Trash destination for system domain paths. Cleanup defaults to the Trash,
   but junk outside the user domain is removed by the root helper, and which
   Trash receives a root owned file (and with what ownership) is undefined
   in the design. Typed: the helper takes an explicit destination
   (C30, HelperRemovalDestination) including userTrash with ownership
   transfer. Whether root owned items should honour the Trash default at all
   needs a decision.
2. Settings lists scan schedules while scheduled background scanning is
   deferred to post launch. Typed: schedules omitted from C12. If the field
   was meant as forward provision, say so in DECISIONS.md.
3. Preselection for Protection findings. The design forbids preselecting
   risky items in Cleanup but is silent for malware. Typed: malware and
   adware findings are preselected because quarantine is reversible; privacy
   items never are. This is my resolution, not a stated decision.
4. Keep one invariant for similar photos. Stated only for duplicates. Typed:
   the same kept path mechanics apply to similar photo sets (C21).
5. Where the prior state of a login item change is recorded. The design says
   recorded per change but not where. Typed: LaunchItemChange records
   persisted by the app (C24). If they should live in SafetyNet for the
   shared retention story, C18 needs a third source case.
6. Helper denylist updates. The design wants the denylist enforced
   independently in both processes so a bad rules update cannot cross it,
   but does not say whether the helper adopts catalogue updates. Typed: each
   process unions the embedded baseline with only catalogues it verified
   itself, and updates can extend but never shrink the denylist (C10, C31).
7. Path ownership of external volumes and other users' files. Typed:
   userDomain means mutable without privilege escalation (C16), which puts
   user writable external volumes in the user domain. Edge cases (another
   user's home on the same machine, network volumes) follow the same rule
   but deserve a look.
8. The menu bar quick clean action "opens the app on the Smart Care result".
   Ambiguous between starting a scan and showing the last result. Typed:
   the action starts a Smart Care scan and opens the window onto its
   progress, landing on the result (s6c).
9. Byte size semantics. Reclaimable estimates need allocated (on disk)
   bytes; the design never says logical or physical. Typed: allocated bytes
   everywhere (C5, C13), so sparse and cloned files do not inflate the
   promise.
10. Trial persistence across reinstall. A 14 day trial whose record dies
    with the app folder resets on reinstall. Typed: the trial record
    survives where possible and never moves backwards (C34). Resolved
    2026-08-09: surviving reinstall is a goal. The trial start lives in
    Application Support beside the SafetyNet manifest, which already
    carries the reinstall survival requirement.
