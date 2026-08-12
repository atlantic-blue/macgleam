/// The one byte figure style every surface uses: decimal units, one decimal
/// place at most, plain "bytes" under a kilobyte.
///
/// It lives here rather than in each surface because two of them disagreeing
/// about how to write 1,500,000 bytes is two products. Decimal rather than
/// binary units, to agree with what the Finder shows for the same file.
public enum ByteFigure {
  public static func string(_ bytes: UInt64) -> String {
    let units = ["KB", "MB", "GB", "TB", "PB"]
    if bytes < 1000 {
      return bytes == 1 ? "1 byte" : "\(bytes) bytes"
    }
    var value = Double(bytes)
    var unitIndex = -1
    while value >= 1000, unitIndex < units.count - 1 {
      value /= 1000
      unitIndex += 1
    }
    let tenths = (value * 10).rounded() / 10
    if tenths == tenths.rounded() {
      return "\(Int(tenths)) \(units[unitIndex])"
    }
    return "\(tenths) \(units[unitIndex])"
  }
}
