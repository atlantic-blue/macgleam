# MacGleam

A macOS care app: clean, protect and speed up a Mac, in an interface built
around interaction and motion quality. SwiftUI, macOS 14 and later, direct
distribution.

The design, contracts and slice graph live in `.greenlight/`. Start with
`.greenlight/DESIGN.md`.

## Running it

```
swift build --product MacGleam
swift run GleamBundler
open dist/MacGleam.app
```

The bundle step is not optional. macOS identifies an app for permissions by
its bundle identifier and code signature, so a bare executable from the build
directory can never appear in the Full Disk Access list, and any access it
attempts is attributed to the terminal that launched it instead.

Full Disk Access has no prompt. Open System Settings, go to Privacy and
Security, then Full Disk Access, add `dist/MacGleam.app` with the plus button
and switch it on. Copy the app to `/Applications` first if you want the grant
to survive moving it.

The signature is ad hoc, which is enough for the system to list the app. The
bundle identifier stays the same across builds but the code directory hash
does not, so a rebuild can mean granting access again. Developer ID signing
and notarization are launch milestone work.
