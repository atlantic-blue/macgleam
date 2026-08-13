import Foundation
import GleamCore
import Testing

/// How a path reads in a line that changes several times a second while a
/// scan runs.
@Suite("Path display")
struct PathDisplayTests {
  private let home = Fixture.path("/Users/ada")

  @Test("a path inside the home directory reads as a tilde")
  func aPathInsideHomeReadsAsATilde() {
    let line = PathDisplay.short(Fixture.path("/Users/ada/Downloads/report.pdf"), home: home)

    #expect(line == "~/Downloads/report.pdf")
  }

  @Test("the home directory itself is a tilde")
  func theHomeDirectoryIsATilde() {
    #expect(PathDisplay.short(home, home: home) == "~")
  }

  @Test("a path outside the home directory is written in full")
  func aPathOutsideHomeIsWrittenInFull() {
    let line = PathDisplay.short(Fixture.path("/Library/Caches/logs.txt"), home: home)

    #expect(line == "/Library/Caches/logs.txt")
  }

  @Test("another account's home is not written as this one's tilde")
  func anotherAccountsHomeIsNotATilde() {
    let line = PathDisplay.short(Fixture.path("/Users/adam/Downloads/report.pdf"), home: home)

    #expect(line == "/Users/adam/Downloads/report.pdf")
  }

  @Test("a long path keeps the name of the file it is reading")
  func aLongPathKeepsTheFileName() {
    let deep = Fixture.path(
      "/Users/ada/Library/Application Support/com.example.something/Caches/v4/objects/payload.bin")

    let line = PathDisplay.short(deep, home: home)

    #expect(line.hasSuffix("payload.bin"), "the file name is the informative half")
    #expect(line.count <= PathDisplay.defaultLimit)
    #expect(line.contains("…"), "and the reader can see something was left out")
  }

  @Test("a path that fits is left exactly as it is")
  func aPathThatFitsIsLeftAlone() {
    let line = PathDisplay.short(Fixture.path("/Users/ada/notes.txt"), home: home)

    #expect(line == "~/notes.txt")
  }

  @Test("a file name longer than the whole line still arrives whole")
  func aVeryLongFileNameStillArrivesWhole() {
    let name = String(repeating: "n", count: 90)
    let line = PathDisplay.short(
      Fixture.path("/Users/ada/Downloads/\(name)"), home: home)

    #expect(
      line.hasSuffix(name),
      "cutting the name would leave a line that names no file at all")
  }
}
