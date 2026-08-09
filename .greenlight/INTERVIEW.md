# Interview brief: pearl

## What we are building

A macOS only Mac care app with feature parity with CleanMyMac 5, built in SwiftUI,
with a better interface and better animations than the product it copies. User
interaction is the stated priority. Original branding and assets throughout: we copy
the feature set and the quality bar, never the name, icons, artwork or copy, which
also keeps us clear of MacPaw's trademarks.

## Parity target (researched 2026-08-09 from macpaw.com and coverage of CleanMyMac 5)

CleanMyMac 5 is organised as six primary modules plus standalone tools:

- Smart Care: one scan that runs five jobs (deep clean, threat scan, performance
  boost, software updates, storage declutter) and presents one combined result
- Cleanup: system junk (caches, logs, broken downloads), mail attachments, trash bins
- Protection: malware scan and removal, privacy cleanup (browser data, recent lists)
- Performance: maintenance scripts, login items, background items and launch agents,
  memory and CPU load
- Applications: full uninstall with leftover sweep, updater, leftovers from removed apps
- My Clutter: duplicates, similar photos, large and old files, downloads triage
- Space Lens: visual disk map, drill in by folder size
- Cloud Cleanup: large cloud files and redundant local copies
- Menu bar item: live monitors (storage, memory, CPU, battery, network) and quick actions
- Assistant layer: suggestions after each scan

Their stated requirements: macOS 11+, 320 MB, subscription from about 3 to 4 dollars
a month. Version 5.5.x as of mid 2026.

## Constraints and decisions already made

- macOS only, SwiftUI first
- Direct distribution with Developer ID signing and notarization. Not App Store: the
  feature set needs Full Disk Access, unsandboxed file operations and a privileged
  helper, none of which survive App Store review
- Interaction and animation quality is the differentiator, not feature count
- Original branding; "pearl" is a working codename only
- Atlantic Blue engineering standards apply: TDD, contracts first, vertical slices,
  TypeScript rule does not apply here (Swift is the typed language), no plain scripts

## Open questions for the design session

- Final product name and visual identity
- macOS floor: 14 proposed for modern SwiftUI animation and Observation framework
- Malware scan approach: signature database (source, update channel) versus
  heuristics only for v1
- Monetisation: one time licence versus subscription, trial shape
- Update mechanism: Sparkle versus custom
- How far Smart Care goes in v1 (which of the five jobs ship first)
