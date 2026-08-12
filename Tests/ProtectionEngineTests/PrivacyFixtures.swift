import Foundation
import GleamCore
import Testing

/// A disk holding the traces four browsers and macOS itself keep, plus the
/// files sitting beside them that a privacy scan must not touch.
///
/// The neighbours are the point. Bookmarks live next to history, saved
/// passwords live next to cookies, and a scan that took the folder rather than
/// the file would take all four.
enum PrivacyFixture {

  static let home = ProtectionFixture.home
  static let library = "\(home)/Library"

  // MARK: Safari

  static let safariHistory = "\(library)/Safari/History.db"
  static let safariLocalStorage = "\(library)/Safari/LocalStorage"
  static let safariCookies = "\(library)/Cookies"
  static let bookmarks = "\(library)/Safari/Bookmarks.plist"

  // MARK: Chrome, and its second profile

  static let chromeProfile = "\(library)/Application Support/Google/Chrome/Default"
  static let chromeHistory = "\(chromeProfile)/History"
  static let chromeCookies = "\(chromeProfile)/Cookies"
  static let chromeLocalStorage = "\(chromeProfile)/Local Storage"
  static let passwords = "\(chromeProfile)/Login Data"
  static let secondProfileHistory =
    "\(library)/Application Support/Google/Chrome/Profile 2/History"

  // MARK: Firefox

  static let firefoxProfile = "\(library)/Application Support/Firefox/Profiles/abc.default"
  static let firefoxHistory = "\(firefoxProfile)/places.sqlite"
  static let firefoxCookies = "\(firefoxProfile)/cookies.sqlite"

  // MARK: What macOS keeps

  static let recentItems = "\(library)/Application Support/com.apple.sharedfilelist"
  static let wifiNetworks = "/Library/Preferences/com.apple.wifi.known-networks.plist"

  // MARK: A file that is none of the above

  static let document = "\(home)/Documents/thesis.pdf"

  static func isPrivacy(_ category: FindingCategory) -> Bool {
    switch category {
    case .browserHistory, .browserCookies, .browserSiteData, .recentItemsList,
      .wifiNetworkHistory:
      return true
    default:
      return false
    }
  }
}

/// The privacy disk. Sizes are distinct so a row carrying the wrong bytes
/// fails rather than coincidentally passing.
func makePrivacyDisk() async -> InMemoryFileSystem {
  let fileSystem = InMemoryFileSystem()
  for directory in [
    "\(PrivacyFixture.library)/Safari",
    PrivacyFixture.safariCookies,
    PrivacyFixture.safariLocalStorage,
    PrivacyFixture.chromeProfile,
    PrivacyFixture.chromeLocalStorage,
    "\(PrivacyFixture.library)/Application Support/Google/Chrome/Profile 2",
    PrivacyFixture.firefoxProfile,
    PrivacyFixture.recentItems,
    "/Library/Preferences",
    "\(PrivacyFixture.home)/Documents",
  ] {
    await fileSystem.seedDirectory(at: ProtectionFixture.path(directory))
  }
  let files: [(String, Int)] = [
    (PrivacyFixture.safariHistory, 900),
    ("\(PrivacyFixture.safariCookies)/Cookies.binarycookies", 400),
    ("\(PrivacyFixture.safariLocalStorage)/site.localstorage", 700),
    (PrivacyFixture.bookmarks, 300),
    (PrivacyFixture.chromeHistory, 1_100),
    (PrivacyFixture.chromeCookies, 500),
    ("\(PrivacyFixture.chromeLocalStorage)/leveldb.000001", 1_000),
    ("\(PrivacyFixture.chromeLocalStorage)/leveldb.000002", 2_000),
    (PrivacyFixture.passwords, 250),
    (PrivacyFixture.secondProfileHistory, 1_200),
    (PrivacyFixture.firefoxHistory, 1_300),
    (PrivacyFixture.firefoxCookies, 600),
    ("\(PrivacyFixture.recentItems)/com.apple.LSSharedFileList.RecentDocuments.sfl3", 200),
    (PrivacyFixture.wifiNetworks, 150),
    (PrivacyFixture.document, 5_000),
  ]
  for (path, length) in files {
    await fileSystem.seedFile(
      at: ProtectionFixture.path(path), contents: ProtectionFixture.contents(9, length: length))
  }
  return fileSystem
}
