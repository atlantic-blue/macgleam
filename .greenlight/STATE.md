```state
stage:    implement
updated:  2026-08-12
goal:     MacGleam at CleanMyMac 5 feature parity, interaction first, M0 to M7
next:     M5 protection: s5a malware scan, then s5b, s5c, s5d
blocked:  none. The live window cannot be captured (the terminal has no
          Screen Recording permission), so visual checks run off offscreen
          renders and the human checks stay queued below.
prs:      atlantic-blue/macgleam#1 to #34, merged in order
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
  - [x] s2i the rail's keys (atlantic-blue/macgleam#22) and module state
  - [x] s3a helper message set and admission policy (atlantic-blue/macgleam#21)
  - [x] s3b the helper daemon (atlantic-blue/macgleam#23)
  - [x] s3c maintenance (atlantic-blue/macgleam#24)
  - [x] s3d login items (atlantic-blue/macgleam#25)
  - [x] s3e process monitor (atlantic-blue/macgleam#26)
  - [x] s3f the helper contract at version two (atlantic-blue/macgleam#32)
  - [x] s4a safety net store (atlantic-blue/macgleam#27)
  - [x] s4b app inventory (atlantic-blue/macgleam#28)
  - [x] s4c uninstall (atlantic-blue/macgleam#29)
  - [x] s4e the store sizes what it stored (atlantic-blue/macgleam#30)
  - [x] s4f the helper archives into the store (atlantic-blue/macgleam#33)
  - [x] s4g the trash destination is the connecting user's own (atlantic-blue/macgleam#34)
  - [x] s4d leftover sweep (atlantic-blue/macgleam#35)
  - [x] s5a malware and adware detection (atlantic-blue/macgleam#36)
  - [ ] s5b quarantine flow
  - [ ] s5c privacy cleanup
  - [x] s5d rules channel (atlantic-blue/macgleam#38)
  - [ ] s5e the signature matcher, a decision for Julian first
  - [ ] M6 full sweep: s6a orchestrator, s6b smart care, s6c menu bar
  - [ ] M7 launch: s7a sparkle, s7b release pipeline, s7c licensing
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

## Two things waiting on Julian

The rules channel is built and has nothing to fetch. `rules.macgleam.app` does
not exist and the rules signing key has not been minted, so a refresh finds
nothing and the app runs on its embedded baseline. The publisher takes the key
from the pipeline's secrets and from nowhere else, and refuses to run without
it, so standing the channel up is: mint the key, set `RULES_SIGNING_KEY`, host
the signed manifest.

## A decision waiting on Julian

The Protection module detects adware from the curated list today and does not
check malware signatures, because nothing ships a YARA matcher. The engine
takes one and says plainly when it has none, so the shape is right and the
library is the only thing missing.

Vendoring libyara is a third party C dependency with its own build, licence
and update path. The alternatives are to vendor it (s5e), or to ship the
Protection module as adware and unwanted software removal alone and say so in
the product. A security feature is the last place to put an approximation
while that is decided, which is why this build has none rather than something
that half works.

## Pending human verification

Verify tier slices are merged on tests and self checks but stay open until
Julian judges them on a running app. Open items:

- s4d the leftover sweep: sweep a real machine and read the findings before
  acting on any of them. Self check done: 16 new tests, 1471 green; mutations
  on the shape rule, on the wider claimed identifiers and on the deletion mode
  branch watched failing then passing. What a test cannot judge: whether the
  findings on a real disk read as obviously safe to remove, which is the whole
  question for a category that acts on files nobody claims.

- s4f the privileged archive: uninstall an application from /Applications on a
  scratch account, confirm the archive is listed with a real size, restore it
  and launch it; then quarantine something only root can move, confirm it
  cannot be run from the store, and restore it. Self check done: 1454 tests
  green, 131 of them new or newly reachable; mutations on the destination
  stage, on the store's routing, on the executor's routing and on both file
  systems' delete watched failing then passing. Not proved by a test: the real
  daemon's archive verbs, because the helper target is an executable nothing
  links; what is proved is the policy that admits them, the client that sends
  them and the store that records them.

- s2i module state and the rail's keys: drive the whole app with the keyboard
  alone, start a scan and dismiss a result without touching the pointer, fold
  two categories in the Cleanup review, go to the Disk Map and come back, and
  confirm the folds are where you left them. Self check done: 1345 tests
  green, 22 of them new; mutation on the slot store and on the decode watched
  failing then passing. Not proved by a test: that the fold animation on
  return reads as the pane arriving rather than as a jump cut, because the
  view choreography does not draw offscreen.

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

## Both contracted promises are wired

Found while reconciling the documents on 2026-08-11, both in C37, both closed
as s2i.

- Return and escape were dead keys, a live defect, closed 2026-08-11.
  `HubKeyResolver` takes what the open pane can do and returns a moved state,
  an intent the pane runs, or ignored, so a press is claimed only when
  something happens. Return runs a pane's primary action; escape dismisses
  where there is something to dismiss and never cancels work. One audible
  consequence: the ends of the rail now beep instead of going silent.
- Module state survives navigation as of 2026-08-12.
  `ModuleStateExchange.navigate` is the one function every rail move goes
  through, from the pointer and from the arrow keys alike: it asks the
  departing module for a slot and hands the arriving module back what it
  left. Cleanup is the first module with one, carrying which review
  categories are folded away; that state moved out of the review view, which
  the rail rebuilds on every return. Disk Map keeps no slot because C39 gives
  it none; its state survives because the model outlives the pane, and the
  tests prove the exchange never touches it.

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
