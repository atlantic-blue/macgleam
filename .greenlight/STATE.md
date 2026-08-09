```state
stage:    implement
updated:  2026-08-09
goal:     MacGleam at CleanMyMac 5 feature parity, interaction first, M0 to M7
next:     M2 slice s2e, performance gates
blocked:  none
prs:      atlantic-blue/macgleam#1
          atlantic-blue/macgleam#2
steps:
  - [x] s0a tokens and workspace (atlantic-blue/macgleam#1)
  - [x] s0b hub shell (atlantic-blue/macgleam#2)
  - [x] s0c hub zoom (atlantic-blue/macgleam#3)
  - [x] s1a domain model (atlantic-blue/macgleam#4)
  - [x] s1b file system (atlantic-blue/macgleam#5)
  - [x] s1c rules baseline (atlantic-blue/macgleam#6)
  - [x] s1d cleanup scan (atlantic-blue/macgleam#7)
  - [x] s1e executor (atlantic-blue/macgleam#8)
  - [x] s1f disk access onboarding (atlantic-blue/macgleam#9)
  - [x] s1g cleanup module (atlantic-blue/macgleam#10)
  - [x] s2a large and old files (atlantic-blue/macgleam#11)
  - [x] s2b duplicates (atlantic-blue/macgleam#12)
  - [x] s2c similar photos (atlantic-blue/macgleam#13)
  - [ ] s2d space lens (this branch)

  - [ ] M2 to M7 per .greenlight/GRAPH.md
```

# State

Autonomous run under the macgleam grant of 2026-08-09: commit, push, pull
request and merge on green continuous integration are pre approved for this
repo only, with the s0a evidence bar (isolated tests, blind implementation,
own test run, mutation check watched both ways, lint, runner executed count
confirmed). Julian is away; product decisions get batched and flagged here.

## Pending human verification

Verify tier slices are merged on tests and self checks but stay open until
Julian judges them on a running app. Open items:

- s0b hub shell: the orb breathes at roughly a 6 second period, the sheen
  reads calm not busy, both appearances look intentional. Self check done:
  63 tests green, app launches and creates its 980 by 700 window (verified
  through the window list), offscreen render saved at
  ~/claude/orgs/atlantic-blue/ideas/macgleam/verify-queue/s0b-hub-rendered.png
  (rendered through ImageRenderer from the composed view, not a screen
  capture; reproduce with swift run MacGleam). Screen capture of the live
  window was not possible: the terminal lacks the Screen Recording
  permission, which only Julian can grant.
- s1g cleanup module: run a real clean on a scratch account, restore a file
  from the Trash, and confirm the choreography (staggered rows, fly to
  summary, ticking counter, clean sweep reward state) uses only token
  motion, in both appearances and under Reduce Motion. Self check done: 442
  tests green with the model driven end to end through fakes, mutation on
  the preselection defence watched both ways, app launches with the real
  cleanup screen behind the cleanup card. The whole view choreography is
  untested by the suite by design; it is this check.
- s1f disk access onboarding: grant Full Disk Access in System Settings and
  watch the flow advance without touching the app; also flip it off and watch
  the degraded banner return. Self check done: 386 tests green including the
  flow model driven by a fake monitor, mutation on the grant advancement
  watched both ways, app launches with the onboarding card over the hub.
  Two things only a live run can judge: the probe paths (~/Library/Mail,
  ~/Library/Safari) behaving on real hardware, and the unofficial System
  Settings pane URL opening the right pane. Note: macOS commonly kills a
  process when it is granted Full Disk Access, so the self advancing flow
  may in practice be a relaunch that lands granted.
- s0c hub zoom: the zoom is one continuous motion with no crossfade seams
  and no dropped frames on a 60 hertz display; the hexagon reads as a
  hexagon; hover breathing feels alive not busy. Self check done: 101 tests
  green including several hundred parameterised navigation cases, mutation
  check on the zoom spring watched both ways, app launches and creates its
  window, render with the focus ring and hexagonal offsets at
  ~/claude/orgs/atlantic-blue/ideas/macgleam/verify-queue/s0c-hub-rendered.png
  (rendered offscreen, same caveat as s0b). The keyboard flow (arrows,
  Return, Escape) and the zoom motion itself cannot be judged from a still;
  run swift run MacGleam on main once this merges.

## Notes for resume

- The hexagonal card geometry is approximated as two columns of three in
  s0b; true hexagonal polish, card hover breathing, the Metal shader orb and
  the zoom all belong to s0c.
- C36 (hub shell model) was added to CONTRACTS.md during s0b because the
  view model needed a typed surface for isolated test writing; GRAPH.md s0b
  entry updated accordingly.

- Recorded debt from s2b: duplicate member allocated sizes travel from scan
  to plan through a process wide ScannedAllocationCache, because Finding
  carries no per path byte sizes and plan is synchronous without a file
  system. The clean fix is per path sizes on Finding (a C5 contract change),
  which would also make denylist byte apportioning exact. RETIRED in s2d:
  Finding now carries per path entries and the cache is deleted.
