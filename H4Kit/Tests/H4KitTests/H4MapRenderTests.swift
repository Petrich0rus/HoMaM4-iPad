import CryptoKit
import Foundation
import Testing
@testable import H4Kit

// MARK: - Projection and canvas (rule R6)

@Test func canvasProjection() {
    let region = H4MapTerrainRender.Region(row: 80, column: 64, rows: 32, columns: 32)
    #expect(region.canvasWidth == 2048 && region.canvasHeight == 1024)
    // Top-left cell sits at the left-most column of the first row... x = 32*(c-r) + 32*(nr-1).
    #expect(region.origin(row: 80, column: 64) == (992, 0))
    #expect(region.origin(row: 111, column: 64) == (32 * -31 + 992, 16 * 31))     // +row goes left-down
    #expect(region.origin(row: 80, column: 95) == (32 * 31 + 992, 16 * 31))       // +column goes right-down
    #expect(region.origin(row: 111, column: 95) == (992, 16 * 62))
    let whole = H4MapTerrainRender.Region.whole(size: 304)
    #expect(whole.canvasWidth / 4 == 4864 && whole.canvasHeight / 4 == 2432)
}

// MARK: - Masks

/// Builds mask bytes from per-column payloads (column k has `columnHeight(k)` pixels).
private func maskBytes(bitsPerPixel: Int, pixel: (Int, Int) -> UInt8) -> Data {
    var out = Data()
    for k in 0..<64 {
        let h = H4TerrainTexture.columnHeight(k)
        if bitsPerPixel == 4 {
            var col = [UInt8](repeating: 0, count: (h + 1) / 2)
            for i in 0..<h { col[i / 2] |= pixel(k, i) << (i % 2 == 0 ? 0 : 4) }
            out += col
        } else {
            var col = [UInt8](repeating: 0, count: (h + 7) / 8)
            for i in 0..<h where pixel(k, i) != 0 { col[i / 8] |= 1 << UInt8(i % 8) }
            out += col
        }
    }
    return out
}

@Test func maskDecoding() {
    #expect(H4TransitionLibrary.encodedSize(bitsPerPixel: 1) == 160 && H4TransitionLibrary.encodedSize(bitsPerPixel: 4) == 544)
    // 4 bpp: alpha = (x + y) % 16 inside the diamond; low nibble holds the first (upper) pixel of a column.
    let four = maskBytes(bitsPerPixel: 4) { k, i in UInt8((k + i) % 16) }
    #expect(four.count == 544)
    let grid4 = H4TransitionLibrary.decode(four, bitsPerPixel: 4)
    for k in 0..<64 {
        let h = H4TerrainTexture.columnHeight(k), top = (31 - h) / 2
        for y in 0..<32 {
            let a = grid4[y * 64 + k]
            if y >= top && y < top + h { #expect(a == UInt8((k + y - top) % 16)) } else { #expect(a == H4TransitionLibrary.outside) }
        }
    }
    // Column 2 (height 3, rows 14…16) by hand: bytes 0x21 0x03 → 1, 2, 3.
    var hand = Data()
    for k in 0..<64 { hand += k == 2 ? Data([0x21, 0x03]) : Data(count: (H4TerrainTexture.columnHeight(k) + 1) / 2) }
    let g = H4TransitionLibrary.decode(hand, bitsPerPixel: 4)
    #expect([g[14 * 64 + 2], g[15 * 64 + 2], g[16 * 64 + 2]] == [1, 2, 3])
    // 1 bpp: bits are least-significant first; set pixels read 15.
    let one = maskBytes(bitsPerPixel: 1) { k, i in (k * 3 + i) % 5 == 0 ? 1 : 0 }
    #expect(one.count == 160)
    let grid1 = H4TransitionLibrary.decode(one, bitsPerPixel: 1)
    for k in 0..<64 {
        let h = H4TerrainTexture.columnHeight(k), top = (31 - h) / 2
        for i in 0..<h { #expect(grid1[(top + i) * 64 + k] == ((k * 3 + i) % 5 == 0 ? 15 : 0)) }
    }
    // Column 3 has 3 pixels, so a single byte 0b101 sets its first and third.
    var bits = Data()
    for k in 0..<64 { bits += k == 3 ? Data([0b101]) : Data(count: (H4TerrainTexture.columnHeight(k) + 7) / 8) }
    let g1 = H4TransitionLibrary.decode(bits, bitsPerPixel: 1)
    #expect([g1[14 * 64 + 3], g1[15 * 64 + 3], g1[16 * 64 + 3]] == [15, 0, 15])
}

private func transitionFile(sets: [(String, [(UInt32, Int, Data)])]) -> Data {
    var d = Data([UInt8(sets.count)])
    for (name, masks) in sets {
        d += str16(name) + le32(UInt32(masks.count))
        for (key, kind, bytes) in masks { d += le32(key) + Data([UInt8(kind)]) + bytes }
    }
    return d
}

@Test func transitionLibraryParsing() throws {
    let one = maskBytes(bitsPerPixel: 1) { _, _ in 1 }
    let four = maskBytes(bitsPerPixel: 4) { _, _ in 9 }
    let lib = try H4TransitionLibrary(data: transitionFile(sets: [("a 1", [(33, 1, one)]), ("b 2", [(201, 4, four), (3333, 1, one)])]))
    #expect(lib.sets.map(\.name) == ["a 1", "b 2"] && lib.sets[1].masks.count == 2)
    #expect(lib.mask(set: "b 2", index: 0)?.key == 201 && lib.mask(set: "b 2", index: 0)?.bitsPerPixel == 4)
    #expect(lib.mask(set: "b 2", index: 0)?.alpha(x: 32, y: 16) == 9 && lib.mask(set: "b 2", index: 0)?.alpha(x: 0, y: 0) == nil)
    #expect(lib.mask(set: "a 1", index: 0)?.alpha(x: 32, y: 16) == 15)
    #expect(lib.mask(set: "a 1", index: 1) == nil && lib.mask(set: "zzz", index: 0) == nil)
    #expect(throws: (any Error).self) { try H4TransitionLibrary(data: transitionFile(sets: [("x", [(1, 2, one)])])) }       // bad kind
    #expect(throws: (any Error).self) { try H4TransitionLibrary(data: transitionFile(sets: [("x", [(1, 1, one)])]) + Data([0])) }
    #expect(throws: (any Error).self) { try H4TransitionLibrary(data: transitionFile(sets: [("x", [(1, 4, four)])]).dropLast()) }
}

// MARK: - Chunk function (rule R1)

@Test func chunkFunctionVectors() {
    typealias R = H4MapTerrainRender
    // Values computed with splitmix64/chunk/sub of the reference renderer (render_ref.py).
    #expect(R.splitmix64(0) == 16294208416658607535)
    #expect(R.splitmix64(1) == 10451216379200822465)
    #expect(R.splitmix64(0x48344D41) == 4779221530450107027)               // chunk (0, 0) of level 0
    #expect(R.chunkHash(level: 0, row: 80, column: 64) == 4210076320327607224)      // chunk (20, 16): ox 1, oy 0
    #expect(R.chunkHash(level: 1, row: 152, column: 153) == 10550371276464080799)   // chunk (38, 38) of level 1
    #expect(R.chunkHash(level: 0, row: 303, column: 301) == 3499758777616500294)    // ox 0, oy 2
    // Same chunk for the whole 4×4 block.
    #expect(R.chunkHash(level: 0, row: 83, column: 67) == R.chunkHash(level: 0, row: 80, column: 64))
    #expect(R.chunkHash(level: 0, row: 84, column: 64) != R.chunkHash(level: 0, row: 80, column: 64))
    #expect(R.tileIndex(level: 0, row: 80, column: 64, terrain: 1) == 43 && R.tileIndex(level: 0, row: 80, column: 64, terrain: 12) == 33)
    #expect(R.tileIndex(level: 1, row: 152, column: 153, terrain: 1) == 54 && R.tileIndex(level: 1, row: 152, column: 153, terrain: 14) == 43)
    #expect(R.tileIndex(level: 0, row: 303, column: 301, terrain: 1) == 37 && R.tileIndex(level: 0, row: 303, column: 301, terrain: 13) == 46)
    let h = R.chunkHash(level: 0, row: 80, column: 64)
    #expect([(1, 0), (1, 1), (9, 0), (15, 0)].map { R.subVariant(chunkHash: h, terrain: $0.0, variant: $0.1) } == [1, 1, 1, 0])
    let h2 = R.chunkHash(level: 0, row: 0, column: 0)
    #expect([(1, 0), (1, 1), (9, 0), (15, 0)].map { R.subVariant(chunkHash: h2, terrain: $0.0, variant: $0.1) } == [1, 0, 1, 1])
    // Tile indices stay inside the 6×6 core window of the 10×10 texture.
    for r in 0..<64 { for c in 0..<64 {
        let i = R.tileIndex(level: 0, row: r, column: c, terrain: 1)
        #expect((2...7).contains(i % 10) && (2...7).contains(i / 10))
    } }
}

@Test func textureNames() {
    func name(_ t: Int, _ v: Int, _ h: UInt64 = 0) -> String { H4MapTerrainRender.textureRef(chunkHash: h, terrain: t, variant: v).resourceName }
    let h = H4MapTerrainRender.chunkHash(level: 0, row: 80, column: 64)       // subs: (1,0)→1, (1,1)→1, (9,0)→1, (15,0)→0
    #expect(name(1, 0, h) == "terrain.grass.1.2.h4d" && name(1, 1, h) == "terrain.grass.2.2.h4d")
    #expect(name(9, 0, h) == "terrain.river.water.2.h4d" && name(15, 0, h) == "terrain.magic.death.1.h4d")
    #expect(name(12, 0, h) == "terrain.magic.all.h4d" && name(14, 0, h) == "terrain.magic.order.h4d")
    #expect(H4TerrainTextureRef.road(0).resourceName == "terrain.road.gravel.1.h4d")
    #expect(H4TerrainTextureRef.road(1).resourceName == "terrain.road.dirt.1.h4d")
    #expect(H4TerrainTextureRef.road(2).resourceName == "terrain.road.cobblestone.1.h4d")
    #expect(H4TerrainTextureRef.road(3).resourceName == "terrain.road.dirt.1.h4d")
}

// MARK: - Blend (rule R5)

@Test func blendFormula() {
    typealias R = H4MapTerrainRender
    #expect(R.blend(dst: 100, src: 200, alpha: 5) == 133)       // (100·10 + 200·5 + 7) / 15
    #expect(R.blend(dst: 200, src: 10, alpha: 5) == 137)
    #expect(R.blend(dst: 137, src: 150, alpha: 10) == 146)
    for v in 0...255 {
        #expect(R.blend(dst: UInt8(v), src: 77, alpha: 15) == 77)   // 1-bpp masks: full replacement
        #expect(R.blend(dst: UInt8(v), src: 77, alpha: 0) == UInt8(v))
    }
}

// MARK: - Compositing with synthetic resources

/// A terrain texture whose 100 tiles are filled with palette colour 0 = `rgb`.
private func solidTexture(_ rgb: (UInt8, UInt8, UInt8)) -> Data {
    var d = Data()
    for _ in 0..<100 {
        var body = Data(), offsets: [UInt32] = []
        for k in 0..<64 {
            offsets.append(UInt32(body.count))
            body += Data([0, UInt8(H4TerrainTexture.columnHeight(k))]) + Data(count: H4TerrainTexture.columnHeight(k))
        }
        d += le32(UInt32(body.count)) + body
        for o in offsets { d += le32(o) }
    }
    return d + le32(1) + Data([rgb.2, rgb.1, rgb.0])
}

/// Size-8 map, level 0: grass everywhere; every cell has a water overlay (set slot 0, mask 0), cell (4, 4) a gravel
/// road (kind 0) and cell (4, 5) a cobblestone road (kind 2), both mask 0 of slot 10 ("road 1").
func syntheticMap() throws -> H4ScenarioTerrain {
    let g = H4MapGeometry(size: 8)
    var cells = Data()
    for (r, range) in g.cellRows.enumerated() {
        for c in range {
            cells += Data([1, 0, 0, 0, 0]) + le32(0x80000) + Data([1, 0, 0]) + le16(0) + Data([0])
            if r == 4 && c == 4 { cells += Data([1, 0]) + le16(0) + Data([10]) }
            else if r == 4 && c == 5 { cells += Data([1, 2]) + le16(0) + Data([10]) }
            else { cells += Data([0]) }
        }
    }
    let scenario = try H4Scenario(scenario: scenarioHeader(size: 8, levels: 1) + Data(repeating: 0xFF, count: 37) + cells
                                  + Data(count: g.vertexCount), containerVersion: 22)
    return try H4ScenarioTerrain(scenario: scenario)
}

func syntheticCompositor(maskAlpha: UInt8) throws -> H4TerrainCompositor {
    let four = maskBytes(bitsPerPixel: 4) { _, _ in maskAlpha }
    let sets = H4MapTerrainRender.maskSetNames.map { ($0, [(UInt32(0), 4, four)]) }
    let lib = try H4TransitionLibrary(data: transitionFile(sets: sets))
    return H4TerrainCompositor(transitions: lib) { name in
        switch name {
        case _ where name.hasPrefix("terrain.grass"): return solidTexture((200, 200, 200))
        case _ where name.hasPrefix("terrain.water"): return solidTexture((10, 10, 10))
        case "terrain.road.gravel.1.h4d": return solidTexture((150, 150, 150))
        case "terrain.road.cobblestone.1.h4d": return solidTexture((90, 90, 90))
        default: throw H4Error.notFound(name: name)
        }
    }
}

@Test func syntheticComposite() throws {
    let terrain = try syntheticMap()
    let compositor = try syntheticCompositor(maskAlpha: 5)
    let region = H4MapTerrainRender.Region.whole(size: 8)
    let image = try compositor.render(terrain: terrain, level: 0, region: region)
    #expect(image.width == 512 && image.height == 256 && compositor.missingTextures.isEmpty && compositor.missingMasks.isEmpty)
    func centre(_ r: Int, _ c: Int) -> [UInt8] {
        let o = region.origin(row: r, column: c)
        let p = ((o.y + 16) * image.width + o.x + 32) * 4
        return Array(image.pixels[p..<(p + 4)])
    }
    // base 200 → water overlay at alpha 5 → 137
    #expect(centre(3, 3) == [137, 137, 137, 255])
    // gravel (kind 0): the mask is inverted, so alpha 5 becomes 10 → (137·5 + 150·10 + 7) / 15 = 146
    #expect(centre(4, 4) == [146, 146, 146, 255])
    // cobblestone (kind 2): the mask is used as is → (137·10 + 90·5 + 7) / 15 = 121
    #expect(centre(4, 5) == [121, 121, 121, 255])
    // Outside the diamond of the map nothing is drawn.
    #expect(Array(image.pixels[0..<4]) == [0, 0, 0, 0])
    // Scaled render = box average of the scale-1 canvas, floored.
    for k in [2, 4, 8] {
        let small = try compositor.render(terrain: terrain, level: 0, region: region, scale: k)
        #expect(small.width == 512 / k && small.height == 256 / k)
        for y in 0..<small.height { for x in 0..<small.width { for ch in 0..<4 {
            var sum = 0
            for dy in 0..<k { for dx in 0..<k { sum += Int(image.pixels[((y * k + dy) * image.width + x * k + dx) * 4 + ch]) } }
            #expect(small.pixels[(y * small.width + x) * 4 + ch] == UInt8(sum / (k * k)))
        } } }
    }
    // Cropped region: odd sizes floor, only cells of the region are drawn.
    let crop = try compositor.render(terrain: terrain, level: 0, region: .init(row: 2, column: 2, rows: 3, columns: 3), scale: 4)
    #expect(crop.width == 192 / 4 && crop.height == 96 / 4)
}

@Test func missingResourcesAreReported() throws {
    let terrain = try syntheticMap()
    let four = maskBytes(bitsPerPixel: 4) { _, _ in 5 }
    // Only one transition set exists, and no water texture.
    let lib = try H4TransitionLibrary(data: transitionFile(sets: [("road 1", [(0, 4, four)])]))
    let compositor = H4TerrainCompositor(transitions: lib) { name in
        guard name.hasPrefix("terrain.grass") else { throw H4Error.notFound(name: name) }
        return solidTexture((200, 200, 200))
    }
    _ = try compositor.render(terrain: terrain, level: 0, region: .whole(size: 8))
    #expect(compositor.missingMasks == ["water_to_land 1 #0"])
    // Overlays whose mask is missing are skipped before their texture is looked up; the road masks exist, their textures do not.
    #expect(compositor.missingTextures == ["terrain.road.gravel.1.h4d", "terrain.road.cobblestone.1.h4d"])
    let noGrass = H4TerrainCompositor(transitions: lib) { throw H4Error.notFound(name: $0) }
    _ = try noGrass.render(terrain: terrain, level: 0, region: .whole(size: 8))
    #expect(noGrass.missingTextures.count >= 1 && noGrass.missingTextures.allSatisfy { $0.hasPrefix("terrain.") })
}

@Test func drawListOrderAndRoadInversion() throws {
    let terrain = try syntheticMap()
    let list = H4MapTerrainRender.drawList(terrain: terrain, level: 0, region: .whole(size: 8))
    #expect(list.bases.count == terrain.geometry.cellCount && list.overlays.count == list.bases.count && list.roads.count == 2)
    let keys = list.bases.map { $0.row + $0.column }
    #expect(keys == keys.sorted())
    #expect(zip(list.bases, list.bases.dropFirst()).allSatisfy { ($0.row + $0.column, $0.row) < ($1.row + $1.column, $1.row) })
    #expect(list.roads[0].mask == H4MaskRef(set: 6, index: 0, inverted: true))      // kind 0: inverted, slot 10 → "road 1"
    #expect(list.roads[1].mask == H4MaskRef(set: 6, index: 0, inverted: false))     // kind 2
    #expect(list.roads[0].texture == .road(0) && list.roads[1].texture == .road(2))
    #expect(list.overlays[0].mask == H4MaskRef(set: 0, index: 0, inverted: false))
    #expect(H4MapTerrainRender.extraSets.count == 20)
    #expect(H4MapTerrainRender.extraSets.map { H4MapTerrainRender.maskSetNames[$0] }[18] == "land 3")
}

// MARK: - Real data

private var realDirs: (data: URL, maps: URL)? {
    guard let d = ProcessInfo.processInfo.environment["H4_DATA_DIR"] else { return nil }
    let data = URL(fileURLWithPath: d)
    let maps = ProcessInfo.processInfo.environment["H4_MAPS_DIR"].map { URL(fileURLWithPath: $0) }
        ?? data.deletingLastPathComponent().appendingPathComponent("maps")
    return (data, maps)
}

private func sha256(_ image: H4RGBAImage) -> String {
    SHA256.hash(data: image.pixels).map { String(format: "%02x", $0) }.joined()
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["H4_DATA_DIR"] != nil))
func realTransitionMasks() throws {
    let dirs = try #require(realDirs)
    let store = try H4ResourceStore(dataDirectory: dirs.data)
    let lib = try H4TransitionLibrary(data: store.data(for: "transition.Transitions.h4d"))
    #expect(lib.sets.count == 15 && lib.sets.allSatisfy { $0.masks.count == 93 })
    for name in H4MapTerrainRender.maskSetNames { #expect(lib.set(named: name) != nil, "missing set \(name)") }
    for set in lib.sets {
        let kinds = Set(set.masks.map(\.bitsPerPixel))
        #expect(kinds.count == 1)
        let expected = set.name.contains("_to_") ? 4 : 1
        #expect(kinds == [expected], "\(set.name)")
        for m in set.masks {
            let inside = (0..<32).flatMap { y in (0..<64).compactMap { x in m.alpha(x: x, y: y) } }
            #expect(inside.count == (0..<64).reduce(0) { $0 + H4TerrainTexture.columnHeight($1) } && inside.allSatisfy { $0 <= 15 })
            if expected == 1 { #expect(inside.allSatisfy { $0 == 0 || $0 == 15 }) }
        }
    }
}

/// The three crops of the acceptance test (A2) must reproduce the reference renderer exactly. The expected
/// values are SHA-256 digests of the RGBA bytes of the reference output (no game pixels are stored).
@Test(.enabled(if: ProcessInfo.processInfo.environment["H4_DATA_DIR"] != nil))
func realCropsMatchReference() throws {
    let dirs = try #require(realDirs)
    let compositor = try H4TerrainCompositor(store: H4ResourceStore(dataDirectory: dirs.data))
    func terrain(_ file: String) throws -> H4ScenarioTerrain {
        try H4ScenarioTerrain(scenario: H4Scenario(fileData: Data(contentsOf: dirs.maps.appendingPathComponent(file))))
    }
    let king = try terrain("A Land without a King.h4c"), zanfas = try terrain("Zanfas's Challenge.h4c")
    let a = try compositor.render(terrain: king, level: 0, region: .init(row: 80, column: 64, rows: 32, columns: 32))
    let b = try compositor.render(terrain: zanfas, level: 0, region: .init(row: 200, column: 88, rows: 32, columns: 32))
    let c = try compositor.render(terrain: zanfas, level: 1, region: .init(row: 152, column: 152, rows: 32, columns: 32))
    #expect(sha256(a) == "03e13d722f962bda999258a410fee92500a1f6d67e975fe226b311a02af0a69d")
    #expect(sha256(b) == "f7c9abe2f198c0cff14059c5f29f6e0f0a4745255dff75b3a904e7fc6ba21051")
    #expect(sha256(c) == "f9a6e0d4ca2e154e04c66b097c3d2df06e09fc63fb9135a5b247fcc9308b07b5")
    #expect(compositor.missingTextures.isEmpty && compositor.missingMasks.isEmpty)
    // A scaled render is the box average of the scale-1 render.
    let half = try compositor.render(terrain: king, level: 0, region: .init(row: 80, column: 64, rows: 32, columns: 32), scale: 2)
    #expect(half.width == 1024 && half.height == 512)
    for (x, y) in [(0, 0), (100, 200), (511, 255), (1023, 511), (700, 30)] {
        for ch in 0..<4 {
            let s = [(0, 0), (1, 0), (0, 1), (1, 1)].reduce(0) { $0 + Int(a.pixels[((y * 2 + $1.1) * a.width + x * 2 + $1.0) * 4 + ch]) }
            #expect(half.pixels[(y * half.width + x) * 4 + ch] == UInt8(s / 4))
        }
    }
}
