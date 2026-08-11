# Decisions: MacGleam

Technical and product decisions, one entry per decision. Status is locked,
deferred or revisit. New decisions are appended, never rewritten; a reversal
gets its own entry pointing at the one it supersedes.

- 2026-08-09. Hub with zoom navigation, no sidebar. The signature interaction:
  status scene centre, six module cards, matched geometry zoom with one shared
  navigation grammar across hub and Disk Map. Rejected the CleanMyMac style
  sidebar as safer but undifferentiated. Status: locked.
- 2026-08-09. macOS 14 (Sonoma) floor. The animation stack (phaseAnimator,
  keyframeAnimator, shader view effects, Observation) requires 14; SMAppService
  needs only 13, so the floor costs nothing there. Status: locked.
- 2026-08-09. One time licence, 14 day full trial, 29 to 39 dollars at launch,
  paid major upgrades. Everything runs locally with no per user server cost;
  pay once is the wedge against CleanMyMac's subscription. Status: locked.
- 2026-08-09. Payment processor likely Paddle. Chosen direction, integration
  and final choice sit in the launch milestone. Status: deferred.
- 2026-08-09. Malware v1 built on Apple's published XProtect YARA rules plus a
  curated adware and persistence list, scanned with a vendored YARA library.
  Rejected a commercial feed (cost, licensing friction) and heuristics only
  (too weak). Honest labelling: malware and adware removal, not antivirus.
  Status: locked, revisit the commercial feed if field reports show misses.
- 2026-08-09. Quarantine only for malware findings, never silent delete.
  SafetyNet store with 30 day retention and one click restore. Status: locked.
- 2026-08-09. Deletion defaults to the macOS Trash for junk and leftovers;
  permanent delete is opt in and confirmed with counts. Uninstalls archive to
  SafetyNet before removal. Reversibility is a trust feature. Status: locked.
- 2026-08-09. Sparkle 2 for updates, EdDSA signed appcast, beta and stable
  channels. Rejected a custom updater as undifferentiated risk. Status: locked.
- 2026-08-09. Full Sweep ships three of five jobs (deep clean, storage
  declutter, performance boost). Threat scan and software updates join when
  Protection and Applications exist; no stub jobs ever. Status: locked.
- 2026-08-09. Privileged operations via an SMAppService root daemon with a
  typed XPC contract, closed operation set, denylist enforced in both
  processes, client identity verified by audit token. Rejected SMJobBless
  (deprecated) and AppleScript authorization (fragile). Status: locked.
- 2026-08-09. Engines as pure Swift packages behind protocol boundaries,
  scanning against a FileSystem protocol so every engine tests against an in
  memory file system. Engines never delete; the executor does. Status: locked.
- 2026-08-09. Directory enumeration with getattrlistbulk and 4 to 8 concurrent
  readers per volume, deduplicating by file id to cover the Sequoia repeat
  entry regression, with a regression test. Status: locked.
- 2026-08-09. Rules and denylist ship as a signed versioned bundle: baseline in
  the app, updates from an Ed25519 signed static channel independent of app
  releases. The denylist overrides any rule in both app and helper.
  Status: locked.
- 2026-08-09. Privacy stance as product promise: no analytics by default, no
  paths or file names ever leave the machine, outbound network is exactly
  appcast, rules channel and licence activation. Status: locked.
- 2026-08-09. Menu bar monitor ships minimal in v1 (storage, memory,
  processor, one quick action) as a scene in the main app process, not a
  separate login item. Revisit the separate process if footprint demands it.
  Status: locked.
- 2026-08-09. Pearl chosen as the working name through development; trademark
  search before launch decides the shipping name. Status: superseded by the
  MacGleam entry below.
- 2026-08-09. Renamed to MacGleam, superseding the Pearl entry above. Pearl
  read as meaningless for search; MacGleam is category legible and ties to the
  orb design language (sheen, lustre, gleam). Verified same day via the
  Registration Data Access Protocol: macgleam.com, gleammac.com, macgleam.app
  and gleammac.app all unregistered, and no existing product found under the
  name. The literal Mac Cleaner name is unavailable (Nektony's MacCleaner Pro,
  all literal domains registered) and being generic could not be owned anyway;
  the mac cleaner search query is captured by page titles instead. Bundle
  identifier namespace com.atlanticblue.macgleam. Trademark search still gates
  the shipping name at launch. Status: locked, revisit at launch.
- 2026-08-09. Direct distribution only: Developer ID, hardened runtime,
  notarization, disk image. The App Store cannot carry Full Disk Access
  dependent features or the helper. Status: locked.
- 2026-08-09. Motion is governed by a token set (snappy, gentle, lively
  springs plus two fade durations); no animation outside the tokens without a
  design decision recorded here. Status: locked.
- 2026-08-09. The 14 day trial survives app reinstall. The trial start is
  recorded in Application Support beside the SafetyNet manifest, which already
  survives reinstall, and the record never moves backwards. Reinstall as a
  trial reset is closed off; a genuinely new machine starts a fresh trial.
  Status: locked.
- 2026-08-09. The architect's nine typed resolutions in GRAPH.md's open
  questions section stand as decided (helper deletions carry an explicit
  destination, scan schedules omitted from Settings until scheduling ships,
  malware findings preselected and privacy items never, keep one invariant
  covers similar photos, login item prior state is app persisted, each process
  verifies its own rule catalogue and updates never shrink the denylist,
  external volumes are user domain when mutable without escalation, menu bar
  quick clean starts a scan, byte figures are allocated bytes). Status: locked.
- 2026-08-10. Navigation rail replaces the hub, superseding the 2026-08-09
  "hub with zoom navigation, no sidebar" decision, which is now reversed. The
  window is a rail of every destination down the left and a pane for the
  selected one, the shape CleanMyMac 5 uses. The centre orb and the hexagon of
  six cards are removed: the orb held one line of text the cards already
  carried, and the pane holds what the module is for, the jobs it runs and
  their live figures instead. The orb survives at 40 points in the rail as a
  live health light. Matched geometry zoom between hub and module is removed
  with the hexagon; the zoom grammar itself stays, because Disk Map drills
  into folders with it. Status: locked.
- 2026-08-10. The Lumina Utility specification is the visual source of truth
  for tokens: the palette, the eight text roles, three nested radii and the
  elevation set all come from it. Two departures, both recorded here. SF Pro
  and SF Mono replace Inter and JetBrains Mono, because the specification
  names them only to work around a web page being unable to use SF Pro, and a
  native app can. Control level padding sits on a 4 point half step because
  the specification pads cards at 20; layout spacing stays on the 8 point
  grid. Status: locked.
- 2026-08-11. Light is a specified appearance, not a derivation. The Clinical
  Precision specification (`.desings/lumina_utility/DESIGN-light.md`) supplies
  the light palette hex for hex, replacing values that had been derived by
  hand to hold contrast. Elevation becomes appearance aware with it, because
  the two specifications genuinely disagree: dark separates layers by tone, so
  a resting card casts nothing and only a floating one casts, sharply; light
  has no tone left above white, so every card casts a soft ambient shadow in
  the text navy and an overlay casts a much wider one. Where a specification's
  palette and its prose disagree, the prose wins, because it is the part that
  says what a colour is for. Status: locked.

- 2026-08-11. Removed `ownerAccountName` from the file metadata snapshot,
  which shrinks a stated promise and is why it is recorded here. Restore
  fidelity claimed to reinstate a file's owning account, and nothing could
  keep that claim: the reading contract had no accessor for it, the mutating
  contract had no setter, and no privileged request moves a root owned file
  back out of the store. So the field would have been nil forever inside a
  structure documented as everything a restore needs. A promise nothing can
  keep is worse than a smaller promise kept exactly, because the first is
  discovered by whoever relies on it. Re-adding it later is an optional
  property whose existing entries decode as nil, so this reverses in a line
  rather than a migration. Ownership rides on the same decision as privileged
  restore, recorded as open question 11 in GRAPH.md and opening at s5b.
  Status: locked, revisit with privileged restore.
