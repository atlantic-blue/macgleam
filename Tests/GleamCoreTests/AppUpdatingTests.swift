import Foundation
import GleamCore
import Testing

/// What an updater is asked to do, and what a build with none does instead.
///
/// The boundary exists so the rules about updating are this app's rather than
/// a framework's configuration, and so the absence of an updater is a fact
/// that can be stated rather than one that looks like everything being fine.
@Suite("App updating")
struct AppUpdatingTests {

  @Test("a build with no updater never claims the app is up to date")
  func aBuildWithNoUpdaterClaimsNothing() async {
    let updater = UnavailableUpdater()

    await updater.apply(UpdatePolicy(channel: .beta))
    await updater.check()

    #expect(
      await updater.lastCheck == nil,
      """
      no updater and nothing to update are different facts, and only one of \
      them is good news
      """)
  }

  @Test("applying a policy hands the updater that policy's own feed")
  func applyingAPolicyHandsItsFeed() async {
    let updater = RecordingUpdater()

    await updater.apply(UpdatePolicy(channel: .beta))

    #expect(await updater.applied.map(\.feedURL) == [UpdateChannel.beta.appcastURL])
  }

  @Test("a check is a look, and the answer is when it happened")
  func aCheckIsALook() async {
    let updater = RecordingUpdater(lastCheck: Date(timeIntervalSince1970: 1_726_000_000))

    await updater.check()

    #expect(await updater.checks == 1)
    #expect(await updater.lastCheck == Date(timeIntervalSince1970: 1_726_000_000))
  }
}

/// An updater at the boundary, recording what it was asked for.
actor RecordingUpdater: AppUpdating {
  private(set) var applied: [UpdatePolicy] = []
  private(set) var checks = 0
  private let recorded: Date?

  init(lastCheck: Date? = nil) {
    self.recorded = lastCheck
  }

  nonisolated var isAvailable: Bool { true }

  func apply(_ policy: UpdatePolicy) async {
    applied.append(policy)
  }

  func check() async {
    checks += 1
  }

  var lastCheck: Date? {
    get async { recorded }
  }
}
