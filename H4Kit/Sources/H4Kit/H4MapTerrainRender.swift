import Foundation

/// Reference of one terrain texture resource (`terrain.<name>[.<variant>].<sub>.h4d`).
public enum H4TerrainTextureRef: Hashable, Sendable {
    /// `variant` is 0 or 1 and only matters for terrains 0…8; `sub` is the per-chunk sub-variant (0-based).
    case terrain(UInt8, variant: UInt8, sub: UInt8)
    /// `terrain.road.<gravel|dirt|cobblestone>.1.h4d`; the payload is the road kind 0…3.
    case road(UInt8)

    public var resourceName: String {
        switch self {
        case let .terrain(t, v, s):
            let name = H4MapTerrainRender.terrainNames[Int(t)]
            if t < 9 { return "terrain.\(name).\(v + 1).\(s + 1).h4d" }
            if (12...14).contains(t) { return "terrain.\(name).h4d" }
            return "terrain.\(name).\(s + 1).h4d"
        case let .road(kind):
            return "terrain.road.\(H4MapTerrainRender.roadTextureNames[Int(kind)]).1.h4d"
        }
    }
}

/// Which mask to read: a transition set (index into `H4MapTerrainRender.maskSetNames`, nil when the
/// file refers to a set slot the game does not have) and a mask index; roads of kind 0 use the inverted mask.
public struct H4MaskRef: Hashable, Sendable {
    public var set: Int?
    public var index: Int
    public var inverted: Bool
}

/// One tile to draw: its 64×32 texture tile, optionally through a mask.
public struct H4TerrainDrawItem: Sendable, Equatable {
    public enum Layer: UInt8, Sendable { case base, overlay, road }
    public var layer: Layer
    public var row: Int, column: Int
    /// Top-left pixel of the tile on the canvas of the region (rule R6).
    public var x: Int, y: Int
    public var texture: H4TerrainTextureRef
    public var tileIndex: Int
    /// nil for base tiles.
    public var mask: H4MaskRef?
}

/// Draw items of one region in the order the three passes execute them (rule R4).
public struct H4TerrainDrawList: Sendable {
    public var bases: [H4TerrainDrawItem] = []
    public var overlays: [H4TerrainDrawItem] = []
    public var roads: [H4TerrainDrawItem] = []
}

/// Terrain rendering rules of the adventure map (slice 6a-T; spec `SPEC_render.md` §1–5).
///
/// Rules (normative, identical to the reference renderer):
/// - R1 chunk: a chunk is 4×4 cells (cr = row>>2, cc = col>>2); h = splitmix64(0x48344D41 ^ level<<40 ^ cr<<20 ^ cc);
///   ox = h % 3, oy = (h>>8) % 3 (terrains 12, 13, 14 use 1, 1); sub-variant of (terrain t, variant v) =
///   splitmix64(h &+ (1 + 2t + v)) % subCount(t). tile index = ((row−4cr)+4−ox) + 10·((col−4cc)+4−oy).
///   The game's own chunk init (MSVC LCG plus a neighbour pass, 0x795040) is not reproduced [?]; the look is equivalent [V].
/// - R2 textures: terrain t < 9 `terrain.<name>.<v+1>.<s+1>`; 12, 13, 14 `terrain.<name>`; others `terrain.<name>.<s+1>`.
///   Overlays use their own (t, v) with the sub-variant of that (t, v) in the cell's chunk and the cell's tile index.
/// - R3 roads: kind 0 gravel (mask inverted: a = 15 − m inside the diamond), 1 dirt, 2 cobblestone, 3 dirt [I];
///   road texture sub-variant 1 [I]; tile index computed with the cell's base terrain; mask set = overlay-set table of
///   `extra` when extra < 20, else "road 1".
/// - R4 order: pass 1 bases of all cells, pass 2 overlays (file order inside a cell), pass 3 roads; cells sorted by (row+col, row).
/// - R5 pixels: a base writes its opaque pixels. An overlay/road pixel applies where the mask alpha a > 0 and the texture
///   pixel exists: written as is onto an empty destination, else per channel (dst·(15−a) + src·a + 7) / 15 (integer).
/// - R6 canvas for cells r0…, c0…, nr × nc: W = 32(nr+nc), H = 16(nr+nc); top-left of cell (r, c):
///   x = 32((c−c0)−(r−r0)) + 32(nr−1), y = 16((r−r0)+(c−c0)). Only cells present in the level are drawn.
/// - R7 output RGBA: alpha 255 where a pixel was written, else (0, 0, 0, 0).
public enum H4MapTerrainRender {
    /// Texture name stems of terrain ids 0…18.
    public static let terrainNames = [
        "water", "grass", "rough", "swamp", "lava", "snow", "sand", "dirt", "subterranean",
        "river.water", "river.lava", "river.ice", "magic.all", "magic.life", "magic.order",
        "magic.death", "magic.chaos", "magic.nature", "special.personal_combat",
    ]
    /// Sub-variants per terrain id.
    public static let subCounts: [UInt64] = [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2]
    public static let roadTextureNames = ["gravel", "dirt", "cobblestone", "dirt"]
    /// Transition sets used by overlays and roads.
    public static let maskSetNames = [
        "water_to_land 1", "water_to_land 2", "water_to_land 3", "land_to_water 1", "land_to_water 2",
        "land_to_water 3", "road 1", "road 2", "land 1", "land 2", "land 3",
    ]
    /// Set slot (`extra`, 0…19) → index in `maskSetNames` (name table at 0xa86e88; slots 0/1, 2/3, … share a set).
    public static let extraSets = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 6, 6, 7, 7, 7, 8, 9, 9, 10, 10]

    // MARK: R1

    public static func splitmix64(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Hash of the 4×4-cell chunk containing (row, column) on `level`.
    public static func chunkHash(level: Int, row: Int, column: Int) -> UInt64 {
        splitmix64(0x4834_4D41 ^ (UInt64(level) << 40) ^ (UInt64(row >> 2) << 20) ^ UInt64(column >> 2))
    }

    public static func subVariant(chunkHash h: UInt64, terrain t: Int, variant v: Int) -> Int {
        Int(splitmix64(h &+ UInt64(1 + 2 * t + v)) % subCounts[t])
    }

    public static func tileIndex(chunkHash h: UInt64, row: Int, column: Int, terrain t: Int) -> Int {
        let (ox, oy) = (12...14).contains(t) ? (1, 1) : (Int(h % 3), Int((h >> 8) % 3))
        return ((row - 4 * (row >> 2)) + 4 - ox) + 10 * ((column - 4 * (column >> 2)) + 4 - oy)
    }

    public static func tileIndex(level: Int, row: Int, column: Int, terrain t: Int) -> Int {
        tileIndex(chunkHash: chunkHash(level: level, row: row, column: column), row: row, column: column, terrain: t)
    }

    // MARK: R2

    public static func textureRef(chunkHash h: UInt64, terrain t: Int, variant v: Int) -> H4TerrainTextureRef {
        let s = UInt8(subVariant(chunkHash: h, terrain: t, variant: v))
        // The cache key only keeps what the resource name depends on.
        return .terrain(UInt8(t), variant: t < 9 ? UInt8(v) : 0, sub: (12...14).contains(t) ? 0 : s)
    }

    // MARK: R4 / R6

    public struct Region: Sendable, Equatable {
        public var row: Int, column: Int, rows: Int, columns: Int
        public init(row: Int, column: Int, rows: Int, columns: Int) {
            self.row = row; self.column = column; self.rows = rows; self.columns = columns
        }
        public static func whole(size: Int) -> Region { Region(row: 0, column: 0, rows: size, columns: size) }
        public var canvasWidth: Int { 32 * (rows + columns) }
        public var canvasHeight: Int { 16 * (rows + columns) }
        /// Top-left of the tile of cell (r, c) on the canvas.
        public func origin(row r: Int, column c: Int) -> (x: Int, y: Int) {
            (32 * ((c - column) - (r - row)) + 32 * (rows - 1), 16 * ((r - row) + (c - column)))
        }
    }

    public static func drawList(terrain: H4ScenarioTerrain, level: Int, region: Region) -> H4TerrainDrawList {
        var list = H4TerrainDrawList()
        let geometry = terrain.geometry
        let rEnd = region.row + region.rows, cEnd = region.column + region.columns
        // Cells sorted by (row + column, row).
        for s in (region.row + region.column)...(rEnd + cEnd - 2) {
            let lo = max(region.row, s - (cEnd - 1), 0), hi = min(rEnd - 1, s - region.column, geometry.size - 1)
            guard lo <= hi else { continue }
            for r in lo...hi {
                let c = s - r
                guard let cell = terrain.cell(level: level, row: r, column: c) else { continue }
                let t = Int(cell.terrain)
                let h = chunkHash(level: level, row: r, column: c)
                let idx = tileIndex(chunkHash: h, row: r, column: c, terrain: t)
                let (x, y) = region.origin(row: r, column: c)
                list.bases.append(H4TerrainDrawItem(
                    layer: .base, row: r, column: c, x: x, y: y,
                    texture: textureRef(chunkHash: h, terrain: t, variant: Int(cell.variant)), tileIndex: idx, mask: nil))
                for o in cell.overlays {
                    list.overlays.append(H4TerrainDrawItem(
                        layer: .overlay, row: r, column: c, x: x, y: y,
                        texture: textureRef(chunkHash: h, terrain: Int(o.terrain), variant: Int(o.variant)), tileIndex: idx,
                        mask: H4MaskRef(set: o.extra < 20 ? extraSets[Int(o.extra)] : nil, index: Int(o.value), inverted: false)))
                }
                for road in cell.roads {
                    list.roads.append(H4TerrainDrawItem(
                        layer: .road, row: r, column: c, x: x, y: y,
                        texture: .road(road.kind), tileIndex: idx,
                        mask: H4MaskRef(set: road.extra < 20 ? extraSets[Int(road.extra)] : 6, index: Int(road.value),
                                        inverted: road.kind == 0)))
                }
            }
        }
        return list
    }

    // MARK: R5

    /// Blend of one channel with mask alpha `a` (0…15).
    @inline(__always)
    public static func blend(dst: UInt8, src: UInt8, alpha a: UInt8) -> UInt8 {
        UInt8((UInt32(dst) * UInt32(15 - a) + UInt32(src) * UInt32(a) + 7) / 15)
    }
}
