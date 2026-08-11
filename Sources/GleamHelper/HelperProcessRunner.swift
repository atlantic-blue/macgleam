import Foundation

/// Runs one system tool and reports what it said.
///
/// The tools are named by absolute path and their arguments are built from the
/// closed `MaintenanceTask` set, never from anything that crossed the process
/// boundary: nothing here interpolates a request into a command line, and no
/// shell is involved, so there is nothing for a request to inject into.
enum HelperProcessRunner {
  struct Outcome {
    let status: Int32
    let output: String

    var succeeded: Bool { status == 0 }
  }

  enum RunError: Error, LocalizedError {
    case couldNotStart(tool: String, description: String)

    var errorDescription: String? {
      switch self {
      case .couldNotStart(let tool, let description):
        return "\(tool) could not be started: \(description)"
      }
    }
  }

  static func run(_ tool: String, _ arguments: [String]) throws -> Outcome {
    let process = Process()
    process.executableURL = URL(filePath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
    } catch {
      throw RunError.couldNotStart(tool: tool, description: error.localizedDescription)
    }
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return Outcome(
      status: process.terminationStatus,
      output: String(decoding: output, as: UTF8.self)
    )
  }
}
