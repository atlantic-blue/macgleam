import CoreGraphics
import Foundation
import SpaceLensModule
import Testing

/// The map's whole job is that every entry stays visible with an area you can
/// read its size from. These assert exactly that, on geometry, without a view.
let canvas = CGRect(x: 0, y: 0, width: 800, height: 500)

func items(_ weights: [UInt64]) -> [TreemapItem<Int>] {
  weights.enumerated().map { TreemapItem(id: $0.offset, weight: $0.element) }
}

/// The shape that broke the old proportional list: one folder holding almost
/// everything, beside several that hold the rest.
let lopsided: [UInt64] = [31_500_000, 98_300, 8_200, 4_100, 2_000]

@Suite("Treemap layout")
struct TreemapLayoutTests {

  @Test("no items, no tiles")
  func noItemsNoTiles() {
    #expect(TreemapLayout.tiles(for: items([]), in: canvas).isEmpty)
  }

  @Test("a canvas with no area produces no tiles")
  func aCanvasWithNoAreaProducesNoTiles() {
    #expect(TreemapLayout.tiles(for: items([1, 2]), in: .zero).isEmpty)
    #expect(
      TreemapLayout.tiles(
        for: items([1, 2]), in: CGRect(x: 0, y: 0, width: 100, height: 0)
      ).isEmpty)
  }

  @Test("a zero weight gets no tile, because a tile with no area cannot be clicked")
  func aZeroWeightGetsNoTile() {
    let tiles = TreemapLayout.tiles(for: items([10, 0, 5]), in: canvas)
    #expect(tiles.map(\.id).sorted() == [0, 2])
  }

  @Test(
    "every weighted item gets exactly one tile",
    arguments: [[100], lopsided, [1, 1, 1, 1, 1, 1, 1]])
  func everyWeightedItemGetsExactlyOneTile(weights: [UInt64]) {
    let tiles = TreemapLayout.tiles(for: items(weights), in: canvas)
    #expect(tiles.count == weights.count)
    #expect(Set(tiles.map(\.id)).count == weights.count)
  }

  @Test("one item fills the whole canvas")
  func oneItemFillsTheWholeCanvas() {
    let tile = TreemapLayout.tiles(for: items([42]), in: canvas)[0]
    #expect(abs(tile.rect.width - canvas.width) < 0.001)
    #expect(abs(tile.rect.height - canvas.height) < 0.001)
  }

  @Test(
    "a tile's share of the area is its share of the weight",
    arguments: [[100], lopsided, [1, 1, 1, 1, 1], [7, 3, 3, 2, 1, 1, 1, 1]]
  )
  func aTilesShareOfTheAreaIsItsShareOfTheWeight(weights: [UInt64]) {
    let tiles = TreemapLayout.tiles(for: items(weights), in: canvas)
    let totalWeight = weights.reduce(0.0) { $0 + Double($1) }
    let totalArea = Double(canvas.width * canvas.height)
    for tile in tiles {
      let expected = Double(weights[tile.id]) / totalWeight
      let actual = Double(tile.rect.width * tile.rect.height) / totalArea
      #expect(
        abs(actual - expected) < 0.001,
        "item \(tile.id) holds \(actual) of the area and \(expected) of the weight")
    }
  }

  @Test(
    "tiles never overlap", arguments: [lopsided, [1, 1, 1, 1, 1], [9, 8, 7, 6, 5, 4, 3, 2, 1]])
  func tilesNeverOverlap(weights: [UInt64]) {
    let tiles = TreemapLayout.tiles(for: items(weights), in: canvas)
    for outer in tiles.indices {
      for inner in tiles.indices where inner > outer {
        let overlap = tiles[outer].rect.intersection(tiles[inner].rect)
        let area = overlap.isNull ? 0 : Double(overlap.width * overlap.height)
        #expect(area < 0.01, "\(tiles[outer].id) and \(tiles[inner].id) overlap by \(area)")
      }
    }
  }

  @Test("tiles stay inside the canvas", arguments: [lopsided, [5, 4, 3, 2, 1]])
  func tilesStayInsideTheCanvas(weights: [UInt64]) {
    for tile in TreemapLayout.tiles(for: items(weights), in: canvas) {
      #expect(tile.rect.minX >= canvas.minX - 0.001)
      #expect(tile.rect.minY >= canvas.minY - 0.001)
      #expect(tile.rect.maxX <= canvas.maxX + 0.001)
      #expect(tile.rect.maxY <= canvas.maxY + 0.001)
    }
  }

  @Test(
    "the tiles together fill the canvas", arguments: [lopsided, [1, 1, 1], [6, 5, 4, 3, 2, 1]])
  func theTilesTogetherFillTheCanvas(weights: [UInt64]) {
    let tiles = TreemapLayout.tiles(for: items(weights), in: canvas)
    let covered = tiles.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
    #expect(abs(covered - Double(canvas.width * canvas.height)) < 1)
  }

  @Test("the layout honours a canvas that does not start at the origin")
  func theLayoutHonoursACanvasThatDoesNotStartAtTheOrigin() {
    let offset = CGRect(x: 120, y: 64, width: 400, height: 300)
    let tiles = TreemapLayout.tiles(for: items(lopsided), in: offset)
    for tile in tiles {
      #expect(tile.rect.minX >= offset.minX - 0.001)
      #expect(tile.rect.minY >= offset.minY - 0.001)
      #expect(tile.rect.maxX <= offset.maxX + 0.001)
      #expect(tile.rect.maxY <= offset.maxY + 0.001)
    }
  }

  @Test("tiles come back largest first")
  func tilesComeBackLargestFirst() {
    let tiles = TreemapLayout.tiles(for: items([3, 9, 1, 7]), in: canvas)
    #expect(tiles.map(\.id) == [1, 3, 0, 2])
  }

  @Test("equal weights keep the order they arrived in")
  func equalWeightsKeepTheOrderTheyArrivedIn() {
    let tiles = TreemapLayout.tiles(for: items([5, 5, 5, 5]), in: canvas)
    #expect(tiles.map(\.id) == [0, 1, 2, 3])
  }

  @Test("the same input always lays out the same way")
  func theSameInputAlwaysLaysOutTheSameWay() {
    let first = TreemapLayout.tiles(for: items(lopsided), in: canvas)
    for _ in 1...5 {
      #expect(TreemapLayout.tiles(for: items(lopsided), in: canvas) == first)
    }
  }

  /// The point of squarifying. A strip layout would give equal weights an
  /// aspect ratio of the canvas ratio times the item count, which for eight
  /// items on this canvas is over twelve to one.
  @Test("equal weights come out close to square")
  func equalWeightsComeOutCloseToSquare() {
    let tiles = TreemapLayout.tiles(for: items(Array(repeating: 10, count: 8)), in: canvas)
    for tile in tiles {
      let ratio = max(tile.rect.width / tile.rect.height, tile.rect.height / tile.rect.width)
      #expect(ratio < 2.5, "tile \(tile.id) came out at \(ratio) to one")
    }
  }

  /// The complaint this replaced: the small entries have to stay big enough
  /// to see and click, not collapse into hairlines.
  @Test("a small entry beside a dominant one still has both a width and a height")
  func aSmallEntryBesideADominantOneStillHasBothAWidthAndAHeight() {
    let tiles = TreemapLayout.tiles(for: items(lopsided), in: canvas)
    for tile in tiles {
      #expect(tile.rect.width > 0.5, "tile \(tile.id) is \(tile.rect.width) points wide")
      #expect(tile.rect.height > 0.5, "tile \(tile.id) is \(tile.rect.height) points tall")
    }
  }

  @Test("a taller canvas than it is wide lays out just as completely")
  func aTallerCanvasLaysOutJustAsCompletely() {
    let portrait = CGRect(x: 0, y: 0, width: 300, height: 900)
    let tiles = TreemapLayout.tiles(for: items(lopsided), in: portrait)
    #expect(tiles.count == lopsided.count)
    let covered = tiles.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
    #expect(abs(covered - Double(portrait.width * portrait.height)) < 1)
  }
}
