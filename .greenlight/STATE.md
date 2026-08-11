```state
stage:    implement
updated:  2026-08-11
goal:     MacGleam at CleanMyMac 5 feature parity, interaction first, M0 to M7
next:     open the pull request for s2f and s2g, carry it to green, merge
blocked:  the live window cannot be captured; the terminal has no Screen
          Recording permission, so checks run off offscreen renders
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
  - [x] s2d disk map (atlantic-blue/macgleam#14)
  - [x] s2e performance gates (atlantic-blue/macgleam#16)
  - [x] s2f Lumina tokens and the navigation rail (this branch)
  - [x] s2g the disk map as a treemap (this branch)

  - [ ] M2 to M7 per .greenlight/GRAPH.md
```

## The interface changed shape on 2026-08-10

Julian supplied the Lumina Utility design specification (`.desings/`), then a
picture of CleanMyMac 5's window, and said the orb in the middle earned
nothing and the centre needed something useful. Both decisions are recorded in
DECISIONS.md. In short: the hexagon of six cards and the centre orb are gone,
a navigation rail carries every destination, and the pane beside it shows what
the selected module is for, the jobs it runs and their live figures. The orb
lives on at 40 points in the rail as a health light.

Only Cleanup is a built module, so its pane is its real screen and the other
five say plainly that they are not built. That is deliberate: an action that
does nothing is worse than an empty pane that explains itself.

# State

Autonomous run under the macgleam grant of 2026-08-09: commit, push, pull
request and merge on green continuous integration are pre approved for this
repo only, with the s0a evidence bar (isolated tests, blind implementation,
own test run, mutation check watched both ways, lint, runner executed count
confirmed). Julian is away; product decisions get batched and flagged here.

## Pending human verification

Verify tier slices are merged on tests and self checks but stay open until
Julian judges them on a running app. Open items:

- s2f the rail and the panes: every module opens on the same shape, the rail
  reads as one column rather than a list of unrelated things, and the five
  unbuilt modules saying so is the right call rather than a discouraging one.
  Self check done: 676 tests green, mutation on the rail clamp and on the pane
  figure rule watched failing then passing, offscreen renders of every
  destination in both appearances. Two things a render cannot judge: the
  selection animation between panes, and the text field and any material,
  which do not draw offscreen.
- s2g the disk map: a folder holding almost everything no longer hides the
  rest, tiles are big enough to aim at, and drilling in from a tile feels the
  same as from the list. Self check done: 16 geometry tests including the
  lopsided case, mutation on the squarify step watched failing then passing,
  and a render of a real map of /opt/homebrew. Not seen: the list under the
  map scrolling, because ScrollView does not draw offscreen; its rows were
  proved by swapping in a plain stack, confirming they draw, then restoring
  the scroller.
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
  watched both ways, app launches with the onboarding card over the shell.
  Two things only a live run can judge: the probe paths (~/Library/Mail,
  ~/Library/Safari) behaving on real hardware, and the unofficial System
  Settings pane URL opening the right pane. Note: macOS commonly kills a
  process when it is granted Full Disk Access, so the self advancing flow
  may in practice be a relaunch that lands granted.

Retired without a verdict: s0b hub shell and s0c hub zoom. The hexagon of six
cards and the matched geometry zoom they asked about no longer exist, so there
is nothing left to judge. The orb survives as the rail's health light and its
breathing is part of the s2f check above.

## Notes for resume

- C36 (hub shell model) was added to CONTRACTS.md during s0b because the
  view model needed a typed surface for isolated test writing; GRAPH.md s0b
  entry updated accordingly.
- The render harness is in the app: `MacGleam --render out.png --size WxH
  [--appearance light] [--selection "Disk Map"] [--map /some/folder]`
  draws the composed shell to a PNG and exits. It exists because a screen
  capture of a live window needs Screen Recording, which a terminal does not
  have. It draws the view, not the window: no chrome, and ScrollView, TextField
  and materials do not appear.

- Recorded debt from s2b: duplicate member allocated sizes travel from scan
  to plan through a process wide ScannedAllocationCache, because Finding
  carries no per path byte sizes and plan is synchronous without a file
  system. The clean fix is per path sizes on Finding (a C5 contract change),
  which would also make denylist byte apportioning exact. RETIRED in s2d:
  Finding now carries per path entries and the cache is deleted.
