import Darwin
import Foundation

/// What this machine calls the process holding an identifier, right now.
///
/// One reader, used by both the listing side and the signalling side, because
/// the safety property is a comparison between the two: a row shown under one
/// spelling and a check made under another would refuse every quit and teach
/// nobody anything. The names agree because they come from here.
enum LiveProcessName {
  /// What the machine says, or nothing at all if no process holds the
  /// identifier.
  ///
  /// Two answers and they are kept apart. `nil` means nothing holds the
  /// identifier; a throw means the machine would not say, which is never read
  /// as no objection.
  static func of(_ processIdentifier: Int32) throws -> String? {
    guard processIdentifier > 0 else { return nil }
    guard let record = try processRecord(processIdentifier) else { return nil }
    if let name = bundleAwareName(processIdentifier) { return name }
    return shortName(from: record)
  }

  /// The kernel's record of the process. Readable for any process without
  /// privilege, which is what makes a name check possible for rows the app
  /// cannot otherwise inspect.
  private static func processRecord(_ processIdentifier: Int32) throws -> kinfo_proc? {
    var request: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processIdentifier]
    var record = kinfo_proc()
    var length = MemoryLayout<kinfo_proc>.stride
    let outcome = sysctl(&request, UInt32(request.count), &record, &length, nil, 0)
    if outcome != 0 {
      if errno == ESRCH { return nil }
      throw ProcessMachineFailure.nameUnreadable(processIdentifier)
    }
    guard length > 0, record.kp_proc.p_pid == processIdentifier else { return nil }
    return record
  }

  /// The name of the enclosing application bundle, for a process that has one.
  /// This is the name a person reads on the row, so it is the name the
  /// confirmation is checked against.
  private static func bundleAwareName(_ processIdentifier: Int32) -> String? {
    guard let executable = executablePath(processIdentifier) else { return nil }
    guard let bundle = applicationBundlePath(of: executable) else {
      return (executable as NSString).lastPathComponent
    }
    return ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
  }

  /// The executable's path, when the machine will give it up. It is used to
  /// find a name and a bundle identifier, and it never reaches a sample, a
  /// finding or a plan.
  static func executablePath(_ processIdentifier: Int32) -> String? {
    var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let written = buffer.withUnsafeMutableBytes { bytes in
      proc_pidpath(
        processIdentifier,
        bytes.baseAddress,
        UInt32(bytes.count)
      )
    }
    guard written > 0 else { return nil }
    return String(decoding: buffer.prefix(Int(written)), as: UTF8.self)
  }

  /// The `.app` directory an executable sits inside, if it sits inside one.
  private static func applicationBundlePath(of executable: String) -> String? {
    var directory = (executable as NSString).deletingLastPathComponent
    while !directory.isEmpty, directory != "/" {
      if (directory as NSString).pathExtension == "app" { return directory }
      directory = (directory as NSString).deletingLastPathComponent
    }
    return nil
  }

  /// The kernel's short name, which every process has and which is capped at
  /// sixteen characters. The fallback when there is no readable path.
  private static func shortName(from record: kinfo_proc) -> String {
    var command = record.kp_proc.p_comm
    return withUnsafeBytes(of: &command) { bytes in
      let characters = bytes.prefix { $0 != 0 }
      return String(decoding: characters, as: UTF8.self)
    }
  }
}

/// What this machine refuses. It stays inside the boundary implementations:
/// `ProcessMonitor` turns a refusal into `ProcessQuitError` in the app's own
/// words, so no errno reaches a person.
enum ProcessMachineFailure: Error, Sendable, Equatable {
  case processTableUnreadable
  case nameUnreadable(Int32)
  case signalRefused(Int32)
}
