import Foundation
import GleamCore
import GleamHelperCore
import os

/// GleamHelper, the privileged daemon.
///
/// It is launched on demand by launchd when MacGleam.app connects to its Mach
/// service, and it does exactly one thing: serve the C30 message set to the
/// one client C31 admits. It opens no window, reads no configuration file,
/// makes no network call ever, and its denylist is its own embedded baseline
/// rather than anything the app sent it, so a compromised app process cannot
/// widen what the root process will do.

let log = Logger(subsystem: GleamHelperService.label, category: "lifecycle")

/// A catalogue that fails to verify leaves the helper with no denylist to
/// enforce, and a root process with no denylist must not run. Exiting is the
/// safe direction: the app then reports the helper as unreachable and touches
/// nothing itself.
let denylist: Denylist
do {
  denylist = try RuleCatalogBaseline.load().denylist
} catch {
  log.critical("The embedded denylist would not load, so the helper is not serving anything.")
  exit(1)
}

if ExpectedClientIdentity.macGleamApp.teamIdentifier == "DEVELOPERIDPENDING" {
  log.error(
    """
    The expected client team identifier is still the placeholder, so no client can satisfy the \
    code signing requirement and every privileged request will be refused. This is the safe \
    direction until the Developer ID certificate exists.
    """
  )
}

let delegate = HelperListener(
  expectedClient: .macGleamApp,
  denylist: denylist
)
let listener = NSXPCListener(machServiceName: GleamHelperService.machServiceName)
listener.delegate = delegate
listener.resume()
log.info("GleamHelper is serving \(GleamHelperService.machServiceName, privacy: .public).")
dispatchMain()
