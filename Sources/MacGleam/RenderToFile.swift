import AppKit
import DiskMapModule
import GleamCore
import GleamHub
import SwiftUI

/// Renders the shell to a PNG and exits, without ever showing a window.
///
/// This exists because judging a layout against a specification needs a
/// picture, and a screen capture of a live window needs the Screen Recording
/// permission, which a terminal does not have by default. What comes out here
/// is a render of the composed view, not a photograph of the running app: it
/// carries no window chrome, and any material that samples what is behind the
/// window renders as its flat fallback. The shell paints flat token colours,
/// so for these screens the two agree.
///
///     MacGleam --render out.png --size 1280x1024 --appearance dark
enum RenderToFile {

  struct Request {
    let destination: URL
    let size: CGSize
    let appearance: ColorScheme
    let selection: HubDestination
    /// When present, the render maps this folder for real and waits for the
    /// map before drawing, so the picture is of an actual scan rather than a
    /// fixture.
    let mapFolder: String?
  }

  /// Parses the request out of the process arguments, or nil for a normal
  /// launch.
  static func request(from arguments: [String]) -> Request? {
    guard let renderIndex = arguments.firstIndex(of: "--render"),
      renderIndex + 1 < arguments.count
    else { return nil }
    return Request(
      destination: URL(fileURLWithPath: arguments[renderIndex + 1]),
      size: parseSize(value(of: "--size", in: arguments)) ?? CGSize(width: 1280, height: 1024),
      appearance: value(of: "--appearance", in: arguments) == "light" ? .light : .dark,
      selection: parseSelection(value(of: "--selection", in: arguments)),
      mapFolder: value(of: "--map", in: arguments)
    )
  }

  @MainActor
  static func render(
    _ request: Request, hub: HubModel, cleanup: CleanupDependencies,
    diskMap: DiskMapDependencies, protection: ProtectionDependencies,
    fullSweep: FullSweepDependencies
  ) throws {
    let renderer = ImageRenderer(
      content:
        AppShellView(
          model: hub,
          cleanup: cleanup,
          diskMap: diskMap,
          protection: protection,
          fullSweep: fullSweep,
          initialSelection: request.selection
        )
        .frame(width: request.size.width, height: request.size.height)
        .environment(\.colorScheme, request.appearance)
    )
    renderer.scale = 2
    guard let image = renderer.nsImage,
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
    else {
      throw RenderFailure.couldNotProduceAnImage
    }
    try png.write(to: request.destination)
  }

  enum RenderFailure: Error {
    case couldNotProduceAnImage
  }

  /// Runs a real map of the folder and waits for it to settle, so a render of
  /// the map is a render of an actual scan. Gives up after the deadline and
  /// draws whatever has streamed in by then, which is itself a picture worth
  /// having.
  @MainActor
  static func mapAndSettle(
    _ model: DiskMapModuleModel,
    folder: String,
    deadline: Duration = .seconds(20)
  ) async {
    model.startMapping(volume: AbsolutePath(normalising: folder))
    let started = ContinuousClock.now
    while ContinuousClock.now - started < deadline {
      if case .browsing = model.state { return }
      try? await Task.sleep(for: .milliseconds(100))
    }
  }

  private static func value(of flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
      return nil
    }
    return arguments[index + 1]
  }

  private static func parseSize(_ text: String?) -> CGSize? {
    guard let parts = text?.split(separator: "x"), parts.count == 2,
      let width = Double(parts[0]), let height = Double(parts[1])
    else { return nil }
    return CGSize(width: width, height: height)
  }

  private static func parseSelection(_ text: String?) -> HubDestination {
    guard let text else { return HubDestination.allCases[0] }
    return HubDestination.allCases.first { $0.title.lowercased() == text.lowercased() }
      ?? HubDestination.allCases[0]
  }
}
