import Foundation
import GleamCore
import Testing

@Suite("FileMetadataSnapshot")
struct FileMetadataSnapshotTests {

  @Test("a fully populated snapshot round trips losslessly")
  func fullyPopulatedSnapshotRoundTrips() throws {
    try expectLosslessRoundTrip(makeMetadataSnapshot())
  }

  @Test("a snapshot with nothing resolvable round trips losslessly")
  func sparseSnapshotRoundTrips() throws {
    let snapshot = makeMetadataSnapshot(
      posixPermissions: 0,
      ownerAccountName: nil,
      extendedAttributes: [:],
      created: nil,
      modified: nil
    )
    try expectLosslessRoundTrip(snapshot)
  }

  @Test("extended attribute bytes survive coding exactly")
  func extendedAttributeBytesSurviveCoding() throws {
    let snapshot = makeMetadataSnapshot(
      extendedAttributes: [
        "com.apple.quarantine": Fixture.attributeBytes,
        "com.example.empty": Data(),
      ]
    )
    let encoded = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(FileMetadataSnapshot.self, from: encoded)
    #expect(decoded.extendedAttributes["com.apple.quarantine"] == Fixture.attributeBytes)
    #expect(decoded.extendedAttributes["com.example.empty"] == Data())
  }
}

@Suite("SafetyNetItem")
struct SafetyNetItemTests {

  @Test("sources use their contract raw values")
  func sourcesUseContractRawValues() {
    #expect(SafetyNetItem.Source.malwareQuarantine.rawValue == "malwareQuarantine")
    #expect(SafetyNetItem.Source.uninstallArchive.rawValue == "uninstallArchive")
  }

  @Test("a quarantine item without a group round trips losslessly")
  func quarantineItemRoundTrips() throws {
    try expectLosslessRoundTrip(makeSafetyNetItem(source: .malwareQuarantine, groupID: nil))
  }

  @Test("an archived item keeps its uninstall group through coding")
  func archivedItemKeepsGroupThroughCoding() throws {
    let item = makeSafetyNetItem(source: .uninstallArchive, groupID: Fixture.groupID)
    let encoded = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(SafetyNetItem.self, from: encoded)
    #expect(decoded == item)
    #expect(decoded.groupID == Fixture.groupID)
  }

  @Test("a restored item round trips losslessly")
  func restoredItemRoundTrips() throws {
    try expectLosslessRoundTrip(makeSafetyNetItem(isRestored: true))
  }

  @Test("storage and expiry dates survive coding exactly")
  func storageAndExpiryDatesSurviveCoding() throws {
    let item = makeSafetyNetItem()
    let encoded = try JSONEncoder().encode(item)
    let decoded = try JSONDecoder().decode(SafetyNetItem.self, from: encoded)
    #expect(decoded.storedAt == item.storedAt)
    #expect(decoded.expiresAt == item.expiresAt)
    #expect(decoded.expiresAt == decoded.storedAt.addingTimeInterval(Fixture.thirtyDays))
  }
}
