import CoreGraphics

/// One item asking for a share of the map.
public struct TreemapItem<ID: Hashable & Sendable>: Sendable, Equatable {
  public let id: ID
  public let weight: UInt64

  public init(id: ID, weight: UInt64) {
    self.id = id
    self.weight = weight
  }
}

/// One item's rectangle on the map.
public struct TreemapTile<ID: Hashable & Sendable>: Sendable, Equatable {
  public let id: ID
  public let rect: CGRect

  public init(id: ID, rect: CGRect) {
    self.id = id
    self.rect = rect
  }
}

/// Squarified treemap layout, after Bruls, Huizing and van Wijk.
///
/// A list whose row heights are proportional to size cannot show a folder
/// holding 99 percent of a volume next to the folders holding the rest: the
/// big one takes the screen and everything else collapses into slivers. A
/// treemap spends two dimensions instead of one, so every entry keeps an area
/// proportional to its size and stays visible and clickable.
///
/// Guarantees:
/// - One tile per item with a positive weight, in weight order, largest
///   first. A zero weight gets no tile, because a tile with no area cannot be
///   seen or clicked.
/// - Tiles never overlap, every tile sits inside the bounds, and together
///   they fill the bounds exactly.
/// - A tile's share of the area equals its share of the total weight.
/// - Pure and deterministic: the same items and bounds always give the same
///   tiles.
/// - Squarified, not striped: tiles are kept as near square as the weights
///   allow, which is what makes a small entry a target rather than a hairline.
public enum TreemapLayout {

  public static func tiles<ID>(
    for items: [TreemapItem<ID>],
    in bounds: CGRect
  ) -> [TreemapTile<ID>] {
    let weighted = items.filter { $0.weight > 0 }
    guard !weighted.isEmpty, bounds.width > 0, bounds.height > 0 else { return [] }

    // A stable sort: equal weights keep the order they arrived in, so the
    // layout does not shuffle when two folders happen to match.
    let ordered = weighted.enumerated()
      .sorted { left, right in
        left.element.weight == right.element.weight
          ? left.offset < right.offset
          : left.element.weight > right.element.weight
      }
      .map(\.element)

    let totalWeight = ordered.reduce(0.0) { $0 + Double($1.weight) }
    let scale = Double(bounds.width) * Double(bounds.height) / totalWeight

    var tiles: [TreemapTile<ID>] = []
    var remaining = ArraySlice(ordered)
    var free = bounds
    var row: [(item: TreemapItem<ID>, area: Double)] = []

    while let next = remaining.first {
      let nextArea = Double(next.weight) * scale
      let side = Double(min(free.width, free.height))
      if row.isEmpty
        || worstAspect(of: row + [(next, nextArea)], alongSide: side)
          <= worstAspect(of: row, alongSide: side)
      {
        row.append((next, nextArea))
        remaining = remaining.dropFirst()
      } else {
        let (placed, rest) = layOut(row, in: free)
        tiles.append(contentsOf: placed)
        free = rest
        row = []
      }
    }
    if !row.isEmpty {
      tiles.append(contentsOf: layOut(row, in: free).placed)
    }
    return tiles
  }

  /// The worst aspect ratio in a row laid along a side of the given length.
  /// Lower is squarer. An empty row is infinitely bad, so the first item
  /// always joins.
  private static func worstAspect<ID>(
    of row: [(item: TreemapItem<ID>, area: Double)],
    alongSide side: Double
  ) -> Double {
    guard !row.isEmpty, side > 0 else { return .infinity }
    let total = row.reduce(0.0) { $0 + $1.area }
    guard total > 0 else { return .infinity }
    let largest = row.max { $0.area < $1.area }?.area ?? 0
    let smallest = row.min { $0.area < $1.area }?.area ?? 0
    guard smallest > 0 else { return .infinity }
    let squared = side * side
    return max(squared * largest / (total * total), (total * total) / (squared * smallest))
  }

  /// Places a row as a band along the free rectangle's shorter side and
  /// returns what is left over.
  private static func layOut<ID>(
    _ row: [(item: TreemapItem<ID>, area: Double)],
    in free: CGRect
  ) -> (placed: [TreemapTile<ID>], rest: CGRect) {
    let total = row.reduce(0.0) { $0 + $1.area }
    guard total > 0 else { return ([], free) }
    let isHorizontalBand = free.width <= free.height

    if isHorizontalBand {
      let bandHeight = CGFloat(total / Double(free.width))
      var x = free.minX
      var placed: [TreemapTile<ID>] = []
      for (index, entry) in row.enumerated() {
        let isLast = index == row.count - 1
        let width = isLast ? free.maxX - x : CGFloat(entry.area / Double(bandHeight))
        placed.append(
          TreemapTile(
            id: entry.item.id,
            rect: CGRect(x: x, y: free.minY, width: width, height: bandHeight)))
        x += width
      }
      let rest = CGRect(
        x: free.minX, y: free.minY + bandHeight,
        width: free.width, height: free.height - bandHeight)
      return (placed, rest)
    }

    let bandWidth = CGFloat(total / Double(free.height))
    var y = free.minY
    var placed: [TreemapTile<ID>] = []
    for (index, entry) in row.enumerated() {
      let isLast = index == row.count - 1
      let height = isLast ? free.maxY - y : CGFloat(entry.area / Double(bandWidth))
      placed.append(
        TreemapTile(
          id: entry.item.id,
          rect: CGRect(x: free.minX, y: y, width: bandWidth, height: height)))
      y += height
    }
    let rest = CGRect(
      x: free.minX + bandWidth, y: free.minY,
      width: free.width - bandWidth, height: free.height)
    return (placed, rest)
  }
}
