import GleamDesign
import GleamHub
import SwiftUI

/// The map's drill motion. Every control that drills resolves through
/// HubZoomResolver here, so the breadcrumb's chevron and the escape key move
/// the same way and the app keeps one navigation language: full motion is
/// the snappy matched geometry spring, Reduce Motion is a crossfade.
enum DiskMapZoom {

  static func animation(for direction: HubZoomDirection, reduceMotion: Bool) -> Animation {
    switch HubZoomResolver.appearance(for: direction, reduceMotion: reduceMotion) {
    case .matchedGeometry(let spring):
      return spring.animation(reduceMotion: false)
    case .crossfade(let fade):
      return .easeInOut(duration: seconds(of: fade.duration))
    }
  }

  private static func seconds(of duration: Duration) -> Double {
    Double(duration.components.seconds)
      + Double(duration.components.attoseconds) / 1e18
  }
}
