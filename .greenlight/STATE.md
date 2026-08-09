```state
stage:    implement
updated:  2026-08-09
goal:     MacGleam at CleanMyMac 5 feature parity, interaction first, M0 to M7
next:     slice s0c, the hub zoom with matched geometry and keyboard walking
blocked:  none
prs:      atlantic-blue/macgleam#1
steps:
  - [x] s0a tokens and workspace (atlantic-blue/macgleam#1)
  - [ ] s0b hub shell (this branch)
  - [ ] s0c hub zoom
  - [ ] M1 s1a to s1g, the first clean
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

## Notes for resume

- The hexagonal card geometry is approximated as two columns of three in
  s0b; true hexagonal polish, card hover breathing, the Metal shader orb and
  the zoom all belong to s0c.
- C36 (hub shell model) was added to CONTRACTS.md during s0b because the
  view model needed a typed surface for isolated test writing; GRAPH.md s0b
  entry updated accordingly.
