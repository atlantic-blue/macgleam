import Foundation
import GleamHelperCore

// The gate a release passes before anything is signed.
//
// The helper admits exactly one client identity, and every other guarantee it
// makes rests on that check biting. A build carrying the stand in team
// identifier would ship a helper that admits nobody, and a check that is a
// formality is worse than no check at all, because everything around it is
// written as though it works.
//
// So this refuses the release. It is a separate tool rather than a test
// because it compares what is compiled into the build against what the
// pipeline was given, and only the pipeline knows the second half.

let placeholderTeamIdentifier = "DEVELOPERIDPENDING"

func team(in arguments: [String]) -> String? {
  guard let index = arguments.firstIndex(of: "--team"), index + 1 < arguments.count else {
    return nil
  }
  let value = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
  return value.isEmpty ? nil : value
}

let compiled = ExpectedClientIdentity.macGleamApp.teamIdentifier

guard compiled != placeholderTeamIdentifier else {
  FileHandle.standardError.write(
    Data(
      """
      This build still carries the placeholder team identifier \
      \(placeholderTeamIdentifier). The privileged helper admits exactly one \
      client, and every guarantee it makes assumes that check bites, so a \
      release with a placeholder there ships a helper that admits nobody and a \
      check that is a formality. Set the Developer ID team in \
      ExpectedClientIdentity.macGleamApp and try again.\n
      """.utf8))
  exit(1)
}

guard let expected = team(in: Array(CommandLine.arguments.dropFirst())) else {
  FileHandle.standardError.write(
    Data(
      """
      No Developer ID team was passed, so this cannot check what the build \
      carries against what it should carry. Set DEVELOPER_ID_TEAM in the \
      repository's secrets.\n
      """.utf8))
  exit(1)
}

guard compiled == expected else {
  FileHandle.standardError.write(
    Data(
      """
      This build expects clients from team \(compiled) and is being signed by \
      team \(expected). The helper would refuse the app it shipped with.\n
      """.utf8))
  exit(1)
}

print("The helper admits team \(compiled), which is the team signing this release.")
