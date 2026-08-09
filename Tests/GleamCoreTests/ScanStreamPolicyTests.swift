import GleamCore
import Testing

/// C15's two streaming numbers, pinned to the literals the contract names.
///
/// Every other test that cares about the cap or the checkpoint window states
/// the number as a literal of its own, so this is the only place either value
/// is read off `ScanStreamPolicy`. That is deliberate. A cap assertion written
/// relative to the constant holds for every value of the constant, so the
/// memory bound C15 exists to provide would have no test that can fail.
///
/// Both numbers are contract values, with the memory and review arithmetic for
/// each written out in C15. Changing one is a contract decision that belongs in
/// C15 and then here, not an implementation tweak.
@Suite("Scan stream policy values")
struct ScanStreamPolicyValueTests {

  @Test("the entry cap is exactly 2,000 entries")
  func theEntryCapIsExactlyTwoThousandEntries() {
    #expect(ScanStreamPolicy.maximumFindingEntries == 2_000)
  }

  @Test("the first finding checkpoint window is exactly 1,000 files")
  func theCheckpointWindowIsExactlyOneThousandFiles() {
    #expect(ScanStreamPolicy.firstFindingCheckpointFiles == 1_000)
  }
}
