import Foundation
import GleamCore
import Testing

@Suite("LicenceState")
struct LicenceStateTests {

  static let allStates: [LicenceState] = [
    .trial(
      startedAt: Fixture.referenceDate,
      endsAt: Fixture.referenceDate.addingTimeInterval(14 * 24 * 60 * 60)
    ),
    .trialExpired(endedAt: Fixture.laterDate),
    .licensed(makeSignedLicence()),
    .invalid(reason: "The licence file does not verify against the embedded key."),
  ]

  @Test("every licence state round trips losslessly", arguments: allStates)
  func everyStateRoundTrips(state: LicenceState) throws {
    try expectLosslessRoundTrip(state)
  }

  @Test("an invalid state carries its reason through coding")
  func invalidStateCarriesReasonThroughCoding() throws {
    let reason = "The licence file does not verify against the embedded key."
    let encoded = try JSONEncoder().encode(LicenceState.invalid(reason: reason))
    let decoded = try JSONDecoder().decode(LicenceState.self, from: encoded)
    #expect(decoded == .invalid(reason: reason))
  }
}

@Suite("SignedLicence")
struct SignedLicenceTests {

  @Test("a licence round trips losslessly")
  func licenceRoundTripsLosslessly() throws {
    try expectLosslessRoundTrip(makeSignedLicence())
  }

  @Test("a licence with the highest version ceiling round trips losslessly")
  func highestCeilingRoundTripsLosslessly() throws {
    try expectLosslessRoundTrip(makeSignedLicence(majorVersionCeiling: UInt16.max))
  }

  @Test("a far future issue date survives coding exactly")
  func farFutureIssueDateSurvivesCoding() throws {
    let licence = SignedLicence(
      licenceKey: "GLEAM-TEST-0002",
      issuedAt: Fixture.farFutureDate,
      majorVersionCeiling: 3,
      signature: Fixture.signatureBytes
    )
    let encoded = try JSONEncoder().encode(licence)
    let decoded = try JSONDecoder().decode(SignedLicence.self, from: encoded)
    #expect(decoded.issuedAt == Fixture.farFutureDate)
  }
}
