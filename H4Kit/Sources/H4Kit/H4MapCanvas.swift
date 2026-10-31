import Foundation

/// Geometry of the whole-map canvas of one level (slice 6b): the canvas size, the rectangle of the canvas that holds
/// cells (so the app never shows the empty margins of the diamond layout), the inverse of the R6/O1 projection
/// (canvas point → lattice cell) and the object and terrain lookups used by the info popup.
///
/// The canvas is the R6 canvas of `Region.whole(size:)`: cell (r, c) has its tile's top-left at
/// x = 32(c − r) + 32(n − 1), y = 16(r + c); the tile is a 64×32 diamond whose centre is the cell centre.
public struct H4MapCanvas: Sendable {
    /// What the hit-test needs to know about an object's model.
    public struct Footprint: Sendable, Equatable {
        public var width: Int, height: Int
        /// Drawn before everything else (ground objects: imageKind 1 or draw-layer byte 2, rule O4).
        public var isGround: Bool
        /// Has at least one drawn body layer.
        public var isVisible: Bool
        public init(width: Int, height: Int, isGround: Bool = false, isVisible: Bool = true) {
            self.width = width; self.height = height; self.isGround = isGround; self.isVisible = isVisible
        }
    }

    public let size: Int
    public let level: Int
    public let region: H4MapTerrainRender.Region
    /// Canvas size at scale 1.
    public var width: Int { region.canvasWidth }
    public var height: Int { region.canvasHeight }
    /// Bounding box of the tiles of all present cells of the level, widened to multiples of 8 so it is a whole number
    /// of pixels at every scale 1, 2, 4, 8.
    public let contentRect: H4TerrainCompositor.PixelRect

    private let geometry: H4MapGeometry
    private let terrainIDs: [UInt8]
    private let rowStart: [Int]
    private let objectAt: [Int32: Int32]
    private let objects: [H4ScenarioObject]

    /// Canvas size of `region` at `scale` (the size of the image `H4TerrainCompositor.render(…scale:)` returns).
    public static func canvasSize(region: H4MapTerrainRender.Region, scale: Int) -> (width: Int, height: Int) {
        (region.canvasWidth / scale, region.canvasHeight / scale)
    }

    public init(terrain: H4ScenarioTerrain, level: Int, objects all: [H4ScenarioObject],
                footprint: (H4ScenarioObject) throws -> Footprint?) rethrows {
        let g = terrain.geometry
        size = g.size; self.level = level
        region = .whole(size: g.size)
        geometry = g
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        var ids: [UInt8] = []
        var starts: [Int] = []
        ids.reserveCapacity(g.cellCount)
        for (r, range) in g.cellRows.enumerated() {
            starts.append(ids.count)
            guard !range.isEmpty else { continue }
            let o0 = region.origin(row: r, column: range.lowerBound), o1 = region.origin(row: r, column: range.upperBound - 1)
            minX = min(minX, o0.x); maxX = max(maxX, o1.x)
            minY = min(minY, o0.y); maxY = max(maxY, o1.y)
            // x and y grow with c, so the extreme tiles of a row are its end cells.
            for c in range { ids.append(terrain.cell(level: level, row: r, column: c)?.terrain ?? 0) }
        }
        terrainIDs = ids
        rowStart = starts
        let x0 = (minX / 8) * 8, y0 = (minY / 8) * 8
        let x1 = (maxX + 64 + 7) / 8 * 8, y1 = (maxY + 32 + 7) / 8 * 8
        contentRect = .init(x: x0, y: y0, width: x1 - x0, height: y1 - y0)

        // Topmost object per cell: ground objects first, then by (x + y, x), later list entries over earlier ones.
        func rank(_ o: H4ScenarioObject, _ f: Footprint) -> (Int, Int, Int) {
            (f.isVisible ? (f.isGround ? -1 : 0) : -2, Int(o.x) + Int(o.y), Int(o.x))
        }
        var best: [Int32: (rank: (Int, Int, Int), index: Int32)] = [:]
        var kept: [H4ScenarioObject] = []
        for o in all where Int(o.level) == level && o.classID != H4ScenarioObject.armyClassID {
            guard let f = try footprint(o), f.width > 0, f.height > 0 else { continue }
            let index = Int32(kept.count)
            kept.append(o)
            let rk = rank(o, f)
            for a in 0..<f.width {
                for b in 0..<f.height {
                    let (r, c) = (Int(o.x) + a, Int(o.y) + b)
                    guard (0..<g.size).contains(r), g.cellRows[r].contains(c) else { continue }
                    let key = Int32(r * 1024 + c)
                    if let old = best[key], old.rank > rk { continue }
                    best[key] = (rk, index)
                }
            }
        }
        objects = kept
        objectAt = best.mapValues(\.index)
    }

    /// With models from a library; objects whose model is unknown have no footprint and are skipped (as in the draw list).
    public init(terrain: H4ScenarioTerrain, level: Int, objects: [H4ScenarioObject], models: H4ObjectModelLibrary) throws {
        try self.init(terrain: terrain, level: level, objects: objects) { o in
            guard let m = try models.model(named: o.modelName) else { return nil }
            return Footprint(width: m.width, height: m.height, isGround: m.imageKind == 1 || m.drawLayer == 2,
                             isVisible: !m.bodyLayers.isEmpty)
        }
    }

    // MARK: tiles

    /// What to render for one tile of a tiled view that shows the content rect: one layer point is `canvasPerPoint`
    /// scale-1 canvas pixels (the screen scale, so that zoom 1 is one device pixel per canvas pixel); the view draws with
    /// `deviceScale` device pixels per layer point (the CTM scale of the tile). The tile covers (x, y, width, height) layer
    /// points, origin at the content rect's top-left.
    public struct TileRequest: Sendable, Equatable {
        /// Render scale k ∈ {1, 2, 4, 8}: the largest power of two not above canvasPerPoint / deviceScale (1 when magnified).
        public var scale: Int
        /// Pixels of the scale-k image of the whole-map canvas, covering the tile.
        public var pixelRect: H4TerrainCompositor.PixelRect
        /// Where the rendered pixels go, in layer points (covers the tile; slightly larger when it does not fall on pixels).
        public var destination: (x: Double, y: Double, width: Double, height: Double)

        public static func == (l: TileRequest, r: TileRequest) -> Bool {
            l.scale == r.scale && l.pixelRect == r.pixelRect && l.destination == r.destination
        }
    }

    public func tileRequest(x: Double, y: Double, width: Double, height: Double,
                            canvasPerPoint: Double, deviceScale: Double) -> TileRequest {
        let ideal = canvasPerPoint / max(deviceScale, 1e-6)
        var k = 1
        while k < 8, Double(k * 2) <= ideal * 1.0001 { k *= 2 }
        let kd = Double(k)
        let x0 = Int(((Double(contentRect.x) + x * canvasPerPoint) / kd).rounded(.down))
        let y0 = Int(((Double(contentRect.y) + y * canvasPerPoint) / kd).rounded(.down))
        let x1 = Int(((Double(contentRect.x) + (x + width) * canvasPerPoint) / kd).rounded(.up))
        let y1 = Int(((Double(contentRect.y) + (y + height) * canvasPerPoint) / kd).rounded(.up))
        let rect = H4TerrainCompositor.PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        return TileRequest(scale: k, pixelRect: rect, destination: (
            (Double(x0) * kd - Double(contentRect.x)) / canvasPerPoint, (Double(y0) * kd - Double(contentRect.y)) / canvasPerPoint,
            Double(rect.width) * kd / canvasPerPoint, Double(rect.height) * kd / canvasPerPoint))
    }

    // MARK: projection

    /// Top-left of the tile of cell (row, column) on the scale-1 canvas.
    public func origin(row: Int, column: Int) -> (x: Int, y: Int) { region.origin(row: row, column: column) }

    /// Inverse of the projection: the lattice cell whose diamond holds the canvas point (x, y) (scale-1 pixels), or nil
    /// where the level has no cell. The tile of cell (r, c) is the diamond with centre (x₀ + 32, y₀ + 16), so with
    /// s = (x − 32n)/32 and t = (y − 16)/16 the cell is r = round((t − s)/2), c = round((t + s)/2).
    public func cell(atX x: Double, y: Double) -> (row: Int, column: Int)? {
        let s = (x - Double(32 * size)) / 32, t = (y - 16) / 16
        let r = Int(((t - s) / 2 + 0.5).rounded(.down)), c = Int(((t + s) / 2 + 0.5).rounded(.down))
        guard (0..<size).contains(r), geometry.cellRows[r].contains(c) else { return nil }
        return (r, c)
    }

    // MARK: lookups

    /// Terrain id of a present cell.
    public func terrainID(row: Int, column: Int) -> Int? {
        guard (0..<size).contains(row), geometry.cellRows[row].contains(column) else { return nil }
        return Int(terrainIDs[rowStart[row] + column - geometry.cellRows[row].lowerBound])
    }

    public func terrainName(row: Int, column: Int) -> String? {
        guard let id = terrainID(row: row, column: column) else { return nil }
        return H4MapTerrainRender.terrainNames.indices.contains(id) ? H4MapTerrainRender.terrainNames[id] : "terrain \(id)"
    }

    /// The object whose footprint contains the cell, topmost in draw order (anonymous armies never count).
    public func object(row: Int, column: Int) -> H4ScenarioObject? {
        objectAt[Int32(row * 1024 + column)].map { objects[Int($0)] }
    }
}
