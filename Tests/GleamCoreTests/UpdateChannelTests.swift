import Foundation
import GleamCore
import Testing

/// What this app watches for updates, and what it will not do.
///
/// An app that can replace itself is the most dangerous thing on the disk, so
/// the rules are narrow and stated: two feeds, both this app's own, a check
/// that offers rather than installs, and a cadence nobody would call polling.
@Suite("Update channel")
struct UpdateChannelTests {

  @Test("there are two channels and no more")
  func thereAreTwoChannels() {
    #expect(UpdateChannel.allCases == [.stable, .beta])
  }

  @Test("each channel reads its own feed, and the two are different files")
  func eachChannelReadsItsOwnFeed() {
    #expect(UpdateChannel.stable.appcastURL != UpdateChannel.beta.appcastURL)
  }

  @Test("both feeds are this app's own host, over a secure connection")
  func bothFeedsAreThisAppsOwnHost() {
    for channel in UpdateChannel.allCases {
      #expect(channel.appcastURL.scheme == "https")
      #expect(channel.appcastURL.host() == "updates.macgleam.app")
      #expect(
        channel.appcastURL.query() == nil,
        "a query would be a place to put something about this Mac")
    }
  }

  @Test("a beta entry cannot reach a stable installation, because they are separate files")
  func aBetaEntryCannotReachAStableInstallation() {
    #expect(
      !UpdateChannel.stable.appcastURL.path().contains("beta"),
      """
      separate feeds rather than one feed with a flag: a filter somebody got \
      wrong would put a beta build on everybody's Mac
      """)
    #expect(UpdateChannel.beta.appcastURL.path().contains("beta"))
  }

  @Test("each channel says what it costs, so choosing beta is an informed choice")
  func eachChannelSaysWhatItCosts() {
    for channel in UpdateChannel.allCases {
      #expect(!channel.explanation.isEmpty)
      #expect(channel.explanation.hasSuffix("."))
    }
    #expect(UpdateChannel.beta.explanation.contains("less use"))
  }

  // MARK: - The policy

  @Test("the policy's feed is its channel's own")
  func thePolicyFeedIsItsChannels() {
    for channel in UpdateChannel.allCases {
      #expect(UpdatePolicy(channel: channel).feedURL == channel.appcastURL)
    }
  }

  @Test("the default is the stable channel, checked daily")
  func theDefaultIsStableCheckedDaily() {
    let policy = UpdatePolicy()
    #expect(policy.channel == .stable)
    #expect(policy.checksAutomatically)
    #expect(policy.checkInterval == UpdatePolicy.dailyInterval)
  }

  @Test("a cadence under an hour is raised to one, because anything faster is polling")
  func aCadenceUnderAnHourIsRaised() {
    for interval in [0.0, 1.0, 60.0, 3_599.0] {
      #expect(UpdatePolicy(checkInterval: interval).checkInterval == 3_600)
    }
  }

  @Test("a longer cadence is left alone")
  func aLongerCadenceIsLeftAlone() {
    #expect(UpdatePolicy(checkInterval: 7 * 24 * 60 * 60).checkInterval == 7 * 24 * 60 * 60)
  }

  @Test("checking can be switched off, and switching it off changes nothing else")
  func checkingCanBeSwitchedOff() {
    let policy = UpdatePolicy(channel: .beta, checksAutomatically: false)
    #expect(!policy.checksAutomatically)
    #expect(policy.feedURL == UpdateChannel.beta.appcastURL)
  }
}

/// What the bundle tells an updater before it trusts anything.
///
/// The feed and the key live in the bundle rather than in code, because a
/// build's own identity is what an updater reads first, and a feed nobody can
/// see in the bundle is a feed nobody can audit.
@Suite("Update keys in the bundle")
struct UpdateBundleKeyTests {

  private static let bundlerSource: String = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { url.deleteLastPathComponent() }
    return
      (try? String(
        contentsOf: url.appending(path: "Sources/GleamBundler/main.swift"), encoding: .utf8)) ?? ""
  }()

  @Test("the bundle names the stable feed and the appcast key")
  func theBundleNamesTheFeedAndTheKey() {
    #expect(Self.bundlerSource.contains("SUFeedURL"))
    #expect(Self.bundlerSource.contains("SUPublicEDKey"))
    #expect(
      Self.bundlerSource.contains("UpdateChannel.stable.appcastURL"),
      "the feed comes from the channel, so there is one place it is decided")
  }

  @Test("the bundle says updates are offered and never installed unasked")
  func theBundleSaysUpdatesAreOfferedRatherThanInstalled() {
    #expect(Self.bundlerSource.contains("\"SUAutomaticallyUpdate\": false"))
    #expect(Self.bundlerSource.contains("\"SUEnableAutomaticChecks\": true"))
  }

  @Test("the appcast key in the tree is a placeholder that verifies nothing")
  func theAppcastKeyIsAPlaceholderThatVerifiesNothing() {
    #expect(
      Self.bundlerSource.contains("REPLACE_AT_LAUNCH_WITH_THE_APPCAST_PUBLIC_KEY"),
      """
      the private half exists only in the release pipeline, so the public half \
      here is a placeholder until the launch ceremony. A placeholder fails \
      closed: nothing verifies against it, so nothing installs
      """)
    #expect(
      !Self.bundlerSource.contains("BEGIN PRIVATE KEY"),
      "no signing key material lives in the repository")
  }
}
