/// The one byte figure style every cleanup surface uses, matching the hub's
/// status line: decimal units, one decimal place at most, plain "bytes"
/// under a kilobyte.
enum ByteFigure {
  static func string(_ bytes: UInt64) -> String {
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
