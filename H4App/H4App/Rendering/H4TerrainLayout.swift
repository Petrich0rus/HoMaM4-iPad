import Foundation
import H4Kit

/// Identifies one terrain texture (100 tiles). Roads use `terrain = 100 + kind`.
struct H4TextureKey: Hashable, Sendable {
    var terrain: UInt8, variant: UInt8, sub: UInt8
    static func road(kind: Int) -> H4TextureKey { H4TextureKey(terrain: UInt8(100 + kind), variant: 0, sub: 0) }
    var isRoad: Bool { terrain >= 100 }
}

/// One textured diamond tile drawn at `position` (top-left of its 64×32 box, map pixels).
/// Field layout is shared with Terrain.metal.
struct TerrainQuad {
    var position: SIMD2<Float>
    /// Pixel origin of the 64×32 tile inside its 640×320 texture slice.
    var tile: SIMD2<UInt16>
    /// Pixel origin of the mask in the mask atlas; x = 0xFFFF means opaque.
    var mask: SIMD2<UInt16>
    var slice: UInt16
    /// Bit 0: invert the mask.
    var flags: UInt16
}

/// Quads of one 16×16-cell block with their bounding box in map pixels (for culling).
struct TerrainBlock {
    var quads: [TerrainQuad] = []
    var minX = Float.infinity, minY = Float.infinity, maxX = -Float.infinity, maxY = -Float.infinity
    mutating func add(_ q: TerrainQuad) {
        quads.append(q)
        minX = min(minX, q.position.x); minY = min(minY, q.position.y)
        maxX = max(maxX, q.position.x + 64); maxY = max(maxY, q.position.y + 32)
    }
}

/// Which tiles, textures and masks make up the terrain of a scenario (see SPEC_render.md).
/// Pure logic on H4Kit data; no Metal, so it can move into H4Kit.
enum H4TerrainLayout {
    static let atlasSize = SIMD2<Int>(640, 320)
    static let maskCount = 93
    static let opaqueMask = SIMD2<UInt16>(0xFFFF, 0)

    static let terrainNames = H4TerrainCell.terrainNames + [
        "river.water", "river.lava", "river.ice", "magic.all", "magic.life", "magic.order",
        "magic.death", "magic.chaos", "magic.nature", "special.personal_combat"]
    static let roadTextures = ["gravel", "dirt", "cobblestone", "cobblestone"]
    /// Transition set per overlay/road `extra` slot (name table at 0xa86e88).
    static let extraSets = ["water_to_land 1", "water_to_land 1", "water_to_land 2", "water_to_land 2", "water_to_land 3",
                            "land_to_water 1", "land_to_water 1", "land_to_water 2", "land_to_water 2", "land_to_water 3",
                            "road 1", "road 1", "road 2", "road 2", "road 2",
                            "land 1", "land 2", "land 2", "land 3", "land 3"]

    static func subCount(terrain t: Int) -> Int { (12...14).contains(t) ? 1 : 2 }

    static func resourceName(_ k: H4TextureKey) -> String {
        if k.isRoad { return "terrain.road.\(roadTextures[Int(k.terrain) - 100]).1.h4d" }
        let t = Int(k.terrain), name = terrainNames[t]
        if t < 9 { return "terrain.\(name).\(k.variant + 1).\(k.sub + 1).h4d" }
        return (12...14).contains(t) ? "terrain.\(name).h4d" : "terrain.\(name).\(k.sub + 1).h4d"
    }

    // MARK: Per-chunk randomness (the game uses an MSVC LCG per 4×4 chunk; any hash gives the same look)

    private static func mix(_ x: UInt32) -> UInt32 {
        var z = x &+ 0x9E37_79B9
        z = (z ^ (z >> 16)) &* 0x85EB_CA6B
        z = (z ^ (z >> 13)) &* 0xC2B2_AE35
        return z ^ (z >> 16)
    }
    /// Keep identical to `chunk_hash` in the comparison script.
    static func chunkHash(_ px: Int, _ py: Int, salt: UInt32) -> UInt32 {
        mix(mix(UInt32(truncatingIfNeeded: px << 16 | py)) &+ salt)
    }

    /// Every texture the terrain can ask for: all sub-variants of each (terrain, variant) used, and used road kinds.
    static func usedTextures(in terrain: H4ScenarioTerrain) -> Set<H4TextureKey> {
        var pairs = Set<[UInt8]>(), roads = Set<Int>()
        for level in terrain.cells {
            for row in level {
                for cell in row {
                    pairs.insert([cell.terrain, cell.variant])
                    for o in cell.overlays { pairs.insert([o.terrain, o.variant]) }
                    for r in cell.roads { roads.insert(Int(r.kind)) }
                }
            }
        }
        var keys = Set<H4TextureKey>()
        for p in pairs where Int(p[0]) < terrainNames.count {
            for s in 0..<subCount(terrain: Int(p[0])) { keys.insert(H4TextureKey(terrain: p[0], variant: p[1], sub: UInt8(s))) }
        }
        for k in roads { keys.insert(.road(kind: k)) }
        return keys
    }

    // MARK: Quads

    /// Quads of one level grouped in 16×16-cell blocks, base tile first, then overlays, then roads for each cell.
    /// `slice` gives the texture slice of a key, `mask` the mask-atlas origin of (set name, mask index).
    static func blocks(of terrain: H4ScenarioTerrain, level: Int,
                       slice: (H4TextureKey) -> UInt16?, mask: (String, Int) -> SIMD2<UInt16>?) -> [TerrainBlock] {
        var blocks: [Int: TerrainBlock] = [:]
        for (r, range) in terrain.geometry.cellRows.enumerated() {
            for c in range {
                guard let cell = terrain.cell(level: level, row: r, column: c), Int(cell.terrain) < terrainNames.count else { continue }
                let px = r >> 2, py = c >> 2
                let h0 = chunkHash(px, py, salt: 0)
                let t = Int(cell.terrain)
                let (ox, oy) = (12...14).contains(t) ? (1, 1) : (Int(h0 % 3), Int((h0 >> 16) % 3))
                let idx = (r - 4 * px + 4 - ox) + 10 * (c - 4 * py + 4 - oy)
                let tile = SIMD2<UInt16>(UInt16(idx % 10 * 64), UInt16(idx / 10 * 32))
                let position = SIMD2<Float>(Float(32 * (c - r) - 32), Float(16 * (r + c) - 16))
                let blockKey = (r >> 4) << 8 | (c >> 4)

                func key(_ terrain: UInt8, _ variant: UInt8) -> H4TextureKey {
                    let n = subCount(terrain: Int(terrain))
                    let s = Int(chunkHash(px, py, salt: 1 + UInt32(terrain) * 2 + UInt32(variant)) % UInt32(n))
                    return H4TextureKey(terrain: terrain, variant: variant, sub: UInt8(s))
                }
                func add(_ k: H4TextureKey, mask m: SIMD2<UInt16>, flags: UInt16 = 0) {
                    guard let s = slice(k) else { return }
                    blocks[blockKey, default: TerrainBlock()].add(
                        TerrainQuad(position: position, tile: tile, mask: m, slice: s, flags: flags))
                }

                add(key(cell.terrain, cell.variant), mask: opaqueMask)
                for o in cell.overlays where Int(o.terrain) < terrainNames.count && Int(o.extra) < extraSets.count {
                    if let m = mask(extraSets[Int(o.extra)], Int(o.value)) { add(key(o.terrain, o.variant), mask: m) }
                }
                for road in cell.roads {
                    let set = Int(road.extra) < extraSets.count ? extraSets[Int(road.extra)] : "road 1"
                    // Kind 0 is the road body (mask inverted); the other kinds are its shoulders. [empirical]
                    if let m = mask(set, Int(road.value)) { add(.road(kind: Int(road.kind)), mask: m, flags: road.kind == 0 ? 1 : 0) }
                }
            }
        }
        return blocks.keys.sorted().map { blocks[$0]! }
    }
}
