```state
stage:    implement
updated:  2026-08-11
goal:     MacGleam at CleanMyMac 5 feature parity, interaction first, M0 to M7
next:     s3b, the helper daemon, and s2i, which wires the rail's return and
          escape keys; they do nothing today
blocked:  the live window cannot be captured; the terminal has no Screen
          Recording permission, so checks run off offscreen renders
prs:      atlantic-blue/macgleam#1
          atlantic-blue/macgleam#2
          atlantic-blue/macgleam#3
          atlantic-blue/macgleam#4
          atlantic-blue/macgleam#5
          atlantic-blue/macgleam#6
          atlantic-blue/macgleam#7
          atlantic-blue/macgleam#8
          atlantic-blue/macgleam#9
          atlantic-blue/macgleam#10
          atlantic-blue/macgleam#11
          atlantic-blue/macgleam#12
          atlantic-blue/macgleam#13
          atlantic-blue/macgleam#14
          atlantic-blue/macgleam#15
          atlantic-blue/macgleam#16
          atlantic-blue/macgleam#17
          atlantic-blue/macgleam#18
          atlantic-blue/macgleam#19
          atlantic-blue/macgleam#20
          atlantic-blue/macgleam#21
steps:
  - [x] s0a tokens and workspace (atlantic-blue/macgleam#1)
  - [x] s0b the shell model (atlantic-blue/macgleam#2)
  - [x] s0c the navigation model (atlantic-blue/macgleam#3)
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
  - [x] s2f Lumina tokens and the navigation rail (atlantic-blue/macgleam#19)
  - [x] s2g the disk map as a treemap (atlantic-blue/macgleam#19)
  - [x] s2h the specified light appearance (atlantic-blue/macgleam#20)
  - [x] s3a helper message set and admission policy (atlantic-blue/macgleam#21)
  - [ ] s2i the rail's intents and preserved module state
  - [ ] s3b the helper daemon
  - [ ] the rest of M3 to M7 per .greenlight/GRAPH.md
```

## The interface changed shape on 2026-08-10

The Lumina Utility specification became the visual source of truth for tokens,
and the centre of the window had to earn its space. Both decisions are recorded
in DECISIONS.md. In short: the hexagon of six cards and the centre orb are
gone, a navigation rail carries every destination, and the pane beside it shows
what the selected module is for, the jobs it runs and their live figures. The
orb lives on at 40 points in the rail as a health light.

The documents were reconciled with the code on 2026-08-11. C1 had been
describing a derived light appearance and an elevation shape that no longer
exists; DESIGN.md's interface sections still described the hub; GRAPH.md filed
s2f to s2h under M3 and still asked for human checks against a deleted screen.
Those are corrected. The appearance authority is `.desings/`, one document per
appearance; DESIGN.md keeps behaviour, safety, privacy and the non functional
targets.

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
- s2h the specified light appearance: it reads as deliberate rather than as
  the dark one with the lights turned up. Self check done: contrast holds at
  4.5 to 1 across the text and semantic colours over every running text
  surface in both appearances, the named shadows and the separator edge are
  asserted, and offscreen renders were taken in light. Not proved by a test
  yet when s2h merged, and named in GRAPH.md under s2h: the light palette was
  not asserted hex for hex the way dark is, and nothing asserted that a token
  differs between the two appearances. Both were closed on 2026-08-11.
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

Retired without a verdict: s0b and s0c, which shipped as the hub shell and the
hub zoom. The hexagon of six cards and the matched geometry zoom they asked
about no longer exist, so there is nothing left to judge. GRAPH.md's entries
for both now say so. The orb survives as the rail's health light and its
breathing is part of the s2f check above; the zoom grammar survives in the
Disk Map and is judged in the s2d and s2g checks.

## One contracted promise is not wired

Found while reconciling the documents on 2026-08-11, both in C37, both now
named in CONTRACTS.md and carried by a new slice s2i in GRAPH.md. Both
statements are against what has merged.

- Return and escape were dead keys, a live defect, and that half is now
  closed. `HubKeyResolver` takes what the open pane can do and returns a
  moved state, an intent the pane runs, or ignored, so a press is claimed only
  when something happens. Return runs a pane's primary action; escape
  dismisses where there is something to dismiss and never cancels work. One
  audible consequence: the ends of the rail now beep instead of going silent.
- Module state does not survive navigation. `storingSlot` has no caller
  outside the tests, so no module encodes anything on leaving and the slots
  the shell carries forward are always empty. The type, the store and the pass
  through property are all real and tested; nothing uses them.

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
