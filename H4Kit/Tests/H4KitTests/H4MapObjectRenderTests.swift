import CryptoKit
import Foundation
import Testing
@testable import H4Kit

// MARK: - Fixtures

/// A layer that is solid colour (BGR 10,20,30 → RGB 16,32,48 as palette entry 1) with one alpha nibble everywhere.
private func solid(_ name: String, _ l: Int32, _ t: Int32, _ r: Int32, _ b: Int32, alpha: UInt8 = 15) -> LayerFixture {
    let w = Int(r - l), h = Int(b - t)
    var f = LayerFixture()
    f.name = name; f.rect = (l, t, r, b)
    f.spans = (0..<h).map { (0, UInt16(w), UInt32($0 * w)) }
    f.indices = [UInt8](repeating: 1, count: w * h)
    f.alphaNibbles = [UInt8](repeating: alpha, count: w * h)
    return f
}

/// `adv_object` bytes (version 4…6, edge flag 1) with the given header fields, layers, depths.
private func modelBytes(version: UInt16 = 6, w: Int = 1, h: Int = 1, imageKind: UInt8 = 0, drawLayer: UInt8 = 1,
                        flag: (Int, Int)? = nil, header: [UInt16] = [2, 0xFFFF, 0xFFFF], layers: [LayerFixture],
                        origin: (Int, Int) = (0, 0), depths: [Int16] = []) -> Data {
    func bits(_ n: Int) -> Data { Data(repeating: 0, count: (n + 7) / 8) }
    var d = le16(version) + Data([10])
    if version >= 3 { d += le16(1) }
    d += le16(UInt16(w)) + le16(UInt16(h)) + bits(w * h)
    if version >= 3 { d += bits((h + 1) * w) + bits((w + 1) * h) } else { d += bits(w * h) }
    if version > 5 { d += bits(2 * (h + 1) * w) + bits(2 * (w + 1) * h) + Data(repeating: 0, count: (w + 1) * (h + 1)) }
    d += le16(0) + le16(80) + str16("t") + le16(0) + str16("") + le16(0) + str16("")
    if version >= 4 { d += Data([drawLayer]) }
    if version >= 5 { d += flag.map { Data([1]) + i32le($0.0) + i32le($0.1) } ?? Data([0]) }
    d += Data([imageKind]) + le16(2) + le16(1) + le16(3) + header.reduce(Data()) { $0 + le16($1) }
    d += group(layers) + i32le(origin.0) + i32le(origin.1)
    if imageKind == 0 { d += le32(UInt32(depths.count)) + depths.reduce(Data()) { $0 + le16(UInt16(bitPattern: $1)) } }
    return d
}

private func scenarioObject(_ x: Int, _ y: Int, level: Int = 0, _ model: String) -> H4ScenarioObject {
    H4ScenarioObject(offset: 0, x: Int32(x), y: Int32(y), level: Int32(level), modelName: model, triple: nil,
                     classID: 0, payload: .versionOnly)
}

private func library(_ models: [String: Data]) -> H4ObjectModelLibrary {
    H4ObjectModelLibrary { name in
        for (k, v) in models where "adv_object.\(k).h4d" == name { return v }
        throw H4Error.notFound(name: name)
    }
}

// MARK: - Header fields (C4)

@Test func adventureObjectHeaderFields() throws {
    let layers = [solid("frame 001", 0, 0, 2, 2)]
    let a = try H4AdventureObject(data: modelBytes(drawLayer: 2, flag: (-7, 12), header: [2, 5, 0xFFFF], layers: layers))
    #expect(a.drawLayer == 2)
    #expect(a.flagAttachPoint?.dx == -7 && a.flagAttachPoint?.dy == 12)
    #expect(a.sprite.mode == 2 && a.sprite.baseFrameIndex == 5 && a.sprite.baseShadowIndex == nil)
    let b = try H4AdventureObject(data: modelBytes(drawLayer: 0, header: [1, 0xFFFF, 3], layers: layers))
    #expect(b.drawLayer == 0 && b.flagAttachPoint == nil)
    #expect(b.sprite.mode == 1 && b.sprite.baseFrameIndex == nil && b.sprite.baseShadowIndex == 3)
    // Version 5 has the flag but a smaller header; version 4 has only the draw-layer byte; below 4 neither (layer defaults to 1).
    let v5 = try H4AdventureObject(data: modelBytes(version: 5, drawLayer: 0, flag: (1, 2), layers: layers))
    #expect(v5.drawLayer == 0 && v5.flagAttachPoint?.dx == 1 && v5.flagAttachPoint?.dy == 2)
    let v4 = try H4AdventureObject(data: modelBytes(version: 4, drawLayer: 2, layers: layers))
    #expect(v4.drawLayer == 2 && v4.flagAttachPoint == nil)
    let v3 = try H4AdventureObject(data: modelBytes(version: 3, layers: layers))
    #expect(v3.drawLayer == 1 && v3.flagAttachPoint == nil)
    // A sprite of inner version 2 has no u16 x 3 header.
    let plain = try H4AdventureObject(data: advObjectBytes(version: 6, imageKind: 0, sprite: 2))
    #expect(plain.sprite.mode == nil && plain.sprite.baseFrameIndex == nil)
}

// MARK: - Anchor and inclusion (O1, O2)

@Test func anchorAndInclusion() {
    let r = H4MapTerrainRender.Region(row: 80, column: 64, rows: 32, columns: 32)
    #expect(H4MapObjectRender.anchor(x: 80, y: 64, region: r) == (1024, 0))
    #expect(H4MapObjectRender.anchor(x: 81, y: 64, region: r) == (992, 16))      // +row: left-down
    #expect(H4MapObjectRender.anchor(x: 80, y: 65, region: r) == (1056, 16))     // +column: right-down
    // The anchor is the top vertex of the tile, i.e. the tile's top-left plus 32.
    for (x, y) in [(80, 64), (95, 70), (111, 95), (60, 100)] {
        #expect(H4MapObjectRender.anchor(x: x, y: y, region: r).x == r.origin(row: x, column: y).x + 32)
        #expect(H4MapObjectRender.anchor(x: x, y: y, region: r).y == r.origin(row: x, column: y).y)
    }
    // O2 margins: 2 cells beyond the region plus the footprint.
    #expect(H4MapObjectRender.isIncluded(x: 78, y: 70, width: 1, height: 1, region: r))         // x+W = 79 >= 78
    #expect(!H4MapObjectRender.isIncluded(x: 76, y: 70, width: 1, height: 1, region: r))        // 77 < 78
    #expect(H4MapObjectRender.isIncluded(x: 76, y: 70, width: 2, height: 1, region: r))
    #expect(H4MapObjectRender.isIncluded(x: 114, y: 70, width: 1, height: 1, region: r))        // x = r0+nr+2
    #expect(!H4MapObjectRender.isIncluded(x: 115, y: 70, width: 1, height: 1, region: r))
    #expect(H4MapObjectRender.isIncluded(x: 90, y: 98, width: 1, height: 1, region: r))
    #expect(!H4MapObjectRender.isIncluded(x: 90, y: 99, width: 1, height: 1, region: r))
    #expect(H4MapObjectRender.isIncluded(x: 90, y: 60, width: 1, height: 3, region: r))         // 60+3 = 63 >= 62
    #expect(!H4MapObjectRender.isIncluded(x: 90, y: 60, width: 1, height: 1, region: r))        // 61 < 62
}

@Test func floorAndCeilDivision() {
    #expect([-65, -64, -33, -32, -1, 0, 1, 31, 32, 33].map { H4MapObjectRender.floorDiv($0, 32) } == [-3, -2, -2, -1, -1, 0, 0, 0, 1, 1])
    #expect([-65, -64, -33, -32, -1, 0, 1, 31, 32, 33].map { H4MapObjectRender.ceilDiv($0, 32) } == [-2, -2, -1, -1, 0, 0, 1, 1, 1, 2])
}

// MARK: - Layer selection (O3)

@Test func frameOneLayerSelection() throws {
    let layers = [
        solid("frame 001 002", 0, 0, 2, 2),       // 0 frame 1
        solid("base_frame", 0, 0, 2, 2),          // 1 base
        solid("frame 002", 0, 0, 2, 2),           // 2 not frame 1
        solid("frame 003 001", 0, 0, 2, 2),       // 3 frame 1
        solid("frame 011", 0, 0, 2, 2),           // 4 "011" is 11, not 1
        solid("shadow 002", 0, 0, 2, 2),          // 5
        solid("base_shadow", 0, 0, 2, 2),         // 6
        solid("shadow 001", 0, 0, 2, 2),          // 7
    ]
    var empty = LayerFixture()
    empty.name = "frame 001"; empty.rect = (3, 3, 3, 3); empty.spans = []; empty.indices = []; empty.alphaNibbles = []
    let all = layers + [empty]                    // 8 empty: never drawn
    let m = H4ObjectModel(name: "m", object: try H4AdventureObject(data: modelBytes(layers: all)))
    #expect(m.bodyLayers == [1, 0, 3])            // base layers before frame-1 layers, each in file order
    #expect(m.shadowLayers == [6, 7])
    #expect(H4ObjectModel.numbers(in: "frame 001 012 3") == [1, 12, 3])
}

// MARK: - Strips, columns, order (O4)

@Test func stripKeysColumnsAndOrder() throws {
    // Lighthouse-like: base_frame spans cols -3…0 (x -70…10), the frame-1 layer cols -1…1 (x -20…40), and another
    // frame's layer (not drawn) reaches x = -130. Depth columns align on the union of all frame layers:
    // first = floor(-130/32) = -5, so col -5 ↔ depths[0] (frame 1 alone would start at col -3).
    let layers = [
        solid("base_frame", -70, 0, 10, 4),
        solid("frame 001", -20, 0, 40, 4),
        solid("frame 002", -130, 0, 60, 4),       // another frame, wider on the left: widens the union
    ]
    let data = modelBytes(layers: layers, depths: [-1, -2, -3, -4, -5, -6, -7])
    let lib = library(["L": data])
    let region = H4MapTerrainRender.Region(row: 0, column: 0, rows: 8, columns: 8)
    let list = try H4MapObjectRender.drawList(objects: [scenarioObject(3, 4, "L")], level: 0, region: region, models: lib)
    let strips = list.items.filter { $0.kind == .body }
    // base_frame: cols floor(-70/32) = -3 … ceil(10/32)-1 = 0; frame 001: cols -1 … 1.
    let got = strips.map { "\($0.layerIndex):\($0.column!)" }
    // key = x+y-d-1 with x+y = 7: depths col-first → d; sort ascending by (7-d-1, 7, 3, col).
    func d(_ col: Int) -> Int { [-1, -2, -3, -4, -5, -6, -7][col + 5] }
    var expected: [(key: Int, col: Int, layer: Int)] = []
    for (k, cols) in [(0, -3...0), (1, -1...1)] { for c in cols { expected.append((7 - d(c) - 1, c, k)) } }
    expected.sort { ($0.key, $0.col) < ($1.key, $1.col) }
    #expect(got == expected.map { "\($0.layer):\($0.col)" })
    #expect(strips.first.map { $0.layerIndex } == 0 && strips.first?.column == -3)
    // The base layer (file index 0 here) is listed before the frame layer inside one object when keys tie.
    #expect(list.objectCount == 1 && list.items.count == 4 + 3)
    // Strip clip = the 32 pixel screen column of the anchor.
    let a = H4MapObjectRender.anchor(x: 3, y: 4, region: region)
    #expect(strips[0].clip == (a.x + 32 * strips[0].column!)..<(a.x + 32 * strips[0].column! + 32))
    // Depth outside the table counts as −1.
    let model = try #require(try lib.model(named: "L"))
    #expect(H4MapObjectRender.depth(of: model, column: -5) == -1 && H4MapObjectRender.depth(of: model, column: -4) == -2)
    #expect(H4MapObjectRender.depth(of: model, column: 1) == -7)
    #expect(H4MapObjectRender.depth(of: model, column: 2) == -1 && H4MapObjectRender.depth(of: model, column: -6) == -1)
}

@Test func baseLayerIsDrawnBeforeFrameLayer() throws {
    // Same columns, same keys: base_frame (file index 1) must come before 'frame 001' (index 0).
    let layers = [solid("frame 001", 0, 0, 30, 4), solid("base_frame", 0, 0, 30, 4)]
    let lib = library(["B": modelBytes(layers: layers, depths: [-1])])
    let list = try H4MapObjectRender.drawList(objects: [scenarioObject(1, 1, "B")], level: 0,
                                              region: .init(row: 0, column: 0, rows: 4, columns: 4), models: lib)
    #expect(list.items.map(\.layerIndex) == [1, 0])
}

@Test func groundObjectsAndShadowPassOrder() throws {
    let layers = [solid("frame 001", 0, 0, 40, 4), solid("shadow 001", 0, 0, 40, 4)]
    let lib = library([
        "tall": modelBytes(layers: layers, depths: [-1, -1]),
        "flat": modelBytes(imageKind: 1, layers: layers),
        "bridge": modelBytes(drawLayer: 2, layers: layers, depths: [-1, -1]),
    ])
    let objs = [scenarioObject(5, 5, "tall"), scenarioObject(4, 4, "flat"), scenarioObject(6, 2, "bridge"), scenarioObject(1, 1, "missing")]
    let list = try H4MapObjectRender.drawList(objects: objs, level: 0, region: .init(row: 0, column: 0, rows: 8, columns: 8), models: lib)
    // Shadow pass first, in object-list order; then ground objects (whole layer, column nil) by (x+y, x); then the strips.
    #expect(list.items.map { "\($0.kind.rawValue):\($0.model)" }.prefix(3) == ["shadow:tall", "shadow:flat", "shadow:bridge"])
    let bodies = list.items.filter { $0.kind == .body }
    #expect(bodies.map(\.model).prefix(2) == ["flat", "bridge"])           // keys (−1, 8, 4) < (−1, 8, 6)
    #expect(bodies[0].column == nil && bodies[1].column == nil)
    #expect(bodies.dropFirst(2).allSatisfy { $0.model == "tall" && $0.column != nil })
    #expect(lib.missingModels == ["missing"])
}

// MARK: - Blends (O5)

@Test func shadowAndBodyBlendValues() throws {
    // One 2x1 shadow layer (alpha 15 → 255) and one body layer with alpha nibble 8 (→ 136); colour RGB (16, 32, 48).
    let layers = [solid("shadow 001", 0, 0, 2, 1, alpha: 15), solid("frame 001", 0, 0, 2, 1, alpha: 8),
                  solid("base_frame", 0, 0, 1, 1, alpha: 15)]
    let lib = library(["S": modelBytes(layers: layers, depths: [-1])])
    let region = H4MapTerrainRender.Region(row: 0, column: 0, rows: 4, columns: 4)
    let list = try H4MapObjectRender.drawList(objects: [scenarioObject(0, 0, "S")], level: 0, region: region, models: lib)
    let (W, H) = (region.canvasWidth, region.canvasHeight)
    var canvas = [UInt8](repeating: 0, count: W * H * 4)
    let a = H4MapObjectRender.anchor(x: 0, y: 0, region: region)          // anchor (128, 0)
    func set(_ x: Int, _ rgb: (UInt8, UInt8, UInt8), alpha: UInt8 = 255) {
        let p = (a.y * W + a.x + x) * 4
        (canvas[p], canvas[p + 1], canvas[p + 2], canvas[p + 3]) = (rgb.0, rgb.1, rgb.2, alpha)
    }
    set(0, (200, 100, 50))
    // pixel 1 stays empty (alpha 0)
    canvas.withUnsafeMutableBufferPointer { buf in
        for item in list.items { H4MapObjectRender.draw(item, canvas: buf.baseAddress!, width: W, y0: 0, rows: H) }
    }
    func px(_ x: Int) -> [UInt8] { let p = (a.y * W + a.x + x) * 4; return Array(canvas[p..<(p + 4)]) }
    // Shadow a = 255: (d·255 + 255) / 510 → 200→100, 100→50, 50→25 (floor of the half-way values 100.5, 50.5, 25.5);
    // then body pixel 0 is the opaque base_frame layer (written as is) → (16, 32, 48).
    #expect(px(0) == [16, 32, 48, 255])
    // Pixel 1: empty destination counts as black: shadow → 0; body a = 136: (0·119 + src·136 + 127) / 255.
    #expect(px(1) == [9, 17, 26, 255])
    // Direct check of the blend on a known destination: re-run only the frame layer over (100, 100, 100).
    let frame = list.items.first { $0.kind == .body && $0.layerIndex == 1 }!
    var c2 = [UInt8](repeating: 100, count: W * H * 4)
    c2.withUnsafeMutableBufferPointer { H4MapObjectRender.draw(frame, canvas: $0.baseAddress!, width: W, y0: 0, rows: H) }
    let q = (a.y * W + a.x) * 4
    #expect(Array(c2[q..<(q + 4)]) == [55, 64, 72, 255])                  // (100·119 + c·136 + 127) / 255
    let shadow = list.items.first { $0.kind == .shadow }!
    var c3 = [UInt8](repeating: 200, count: W * H * 4)
    c3.withUnsafeMutableBufferPointer { H4MapObjectRender.draw(shadow, canvas: $0.baseAddress!, width: W, y0: 0, rows: H) }
    #expect(Array(c3[q..<(q + 4)]) == [100, 100, 100, 255])               // (200·255 + 255) / 510 = 100
}

@Test func bandedDrawingMatchesWholeCanvas() throws {
    // Drawing into a band of the canvas gives the same pixels as the whole canvas.
    let layers = [solid("frame 001", -40, 3, 60, 40), solid("shadow 001", -40, 3, 60, 40, alpha: 7)]
    let lib = library(["Q": modelBytes(layers: layers, depths: [-1, -1, -1, -1])])
    let region = H4MapTerrainRender.Region(row: 0, column: 0, rows: 4, columns: 4)
    let list = try H4MapObjectRender.drawList(objects: [scenarioObject(1, 2, "Q")], level: 0, region: region, models: lib)
    let (W, H) = (region.canvasWidth, region.canvasHeight)
    var whole = [UInt8](repeating: 9, count: W * H * 4)
    whole.withUnsafeMutableBufferPointer { b in for i in list.items { H4MapObjectRender.draw(i, canvas: b.baseAddress!, width: W, y0: 0, rows: H) } }
    var band = [UInt8](repeating: 9, count: W * 20 * 4)
    band.withUnsafeMutableBufferPointer { b in for i in list.items { H4MapObjectRender.draw(i, canvas: b.baseAddress!, width: W, y0: 60, rows: 20) } }
    #expect(Array(whole[(60 * W * 4)..<(80 * W * 4)]) == band)
    #expect(band.contains(255))
}

// MARK: - Terrain compositor: tile index outside the texture (P3 of 6a-T)

@Test func tileOutsideTextureCountsAsMissing() throws {
    let compositor = H4TerrainCompositor(transitions: try H4TransitionLibrary(data: Data([0])),
                                         loader: { _ in terrainBytes() })
    let item = H4TerrainDrawItem(layer: .base, row: 0, column: 0, x: 0, y: 0,
                                 texture: .terrain(1, variant: 0, sub: 0), tileIndex: 100, mask: nil)
    #expect(try compositor.tile(item) == nil)
    #expect(compositor.missingTextures == ["terrain.grass.1.1.h4d tile 100"])
    let ok = H4TerrainDrawItem(layer: .base, row: 0, column: 0, x: 0, y: 0,
                               texture: .terrain(1, variant: 0, sub: 0), tileIndex: 3, mask: nil)
    #expect(try compositor.tile(ok) != nil)
    #expect(compositor.missingTextures.count == 1)
}

// MARK: - Real data

private var realDirs: (data: URL, maps: URL)? {
    guard let d = ProcessInfo.processInfo.environment["H4_DATA_DIR"] else { return nil }
    let data = URL(fileURLWithPath: d)
    let maps = ProcessInfo.processInfo.environment["H4_MAPS_DIR"].map { URL(fileURLWithPath: $0) }
        ?? data.deletingLastPathComponent().appendingPathComponent("maps")
    return (data, maps)
}

private func sha256(_ bytes: [UInt8]) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }

/// The three crops of the acceptance test (C1) with objects reproduce the reference renderer (`render_objects_ref.py`)
/// exactly. The expected values are SHA-256 digests of the RGBA bytes (and item counts of the draw list) of the
/// reference output; no game pixels are stored.
@Test(.enabled(if: ProcessInfo.processInfo.environment["H4_DATA_DIR"] != nil))
func realCropsWithObjectsMatchReference() throws {
    let dirs = try #require(realDirs)
    let store = try H4ResourceStore(dataDirectory: dirs.data)
    let compositor = try H4TerrainCompositor(store: store)
    let models = H4ObjectModelLibrary(store: store)
    let resolver = H4ObjectClassResolver(resources: store)
    func crop(_ file: String, level: Int, _ r0: Int, _ c0: Int) throws -> (H4RGBAImage, H4ObjectDrawList) {
        let scenario = try H4Scenario(fileData: Data(contentsOf: dirs.maps.appendingPathComponent(file)))
        let body = try H4ScenarioBody(scenario: scenario, resolver: resolver)
        guard case .complete = body.stop else { throw H4Error.malformed("object list incomplete") }
        let region = H4MapTerrainRender.Region(row: r0, column: c0, rows: 32, columns: 32)
        let list = try H4MapObjectRender.drawList(objects: body.objects, level: level, region: region, models: models)
        let terrain = try H4ScenarioTerrain(scenario: scenario)
        return (try compositor.render(terrain: terrain, level: level, region: region, objects: list), list)
    }
    let (a, la) = try crop("A Land without a King.h4c", level: 0, 80, 64)
    let (b, lb) = try crop("Zanfas's Challenge.h4c", level: 0, 200, 88)
    let (c, lc) = try crop("Zanfas's Challenge.h4c", level: 1, 152, 152)
    #expect(sha256(a.pixels) == "d267d4da70299168ffde05d0048f9acce08d3581c7c57048e7586b2c4bc1e03a")
    #expect(sha256(b.pixels) == "2e58c1671c50a2ec82050f28e2459daf2d4403280778eee3535423bc94ab839a")
    #expect(sha256(c.pixels) == "eb8d202c7ce15d1f9b270767d1695f1476147a5360f0b4fe118ee6cd14015e4a")
    let objectCounts: [Int] = [la.objectCount, lb.objectCount, lc.objectCount]
    let itemCounts: [Int] = [la.items.count, lb.items.count, lc.items.count]
    #expect(objectCounts == [408, 305, 243])
    #expect(itemCounts == [1588, 1322, 1091])
    #expect(models.missingModels.isEmpty && compositor.missingTextures.isEmpty && compositor.missingMasks.isEmpty)
    // The draw list's JSON equals the reference JSON as parsed (hash of the canonical text, written by the Swift side).
    #expect(sha256(Array(try la.json())) == "428fb5c1382d51cc08feff6256b5d5bd2e1b9ffef350bc1261901a8e11d8cad0")
    #expect(sha256(Array(try lb.json())) == "bd963f8bffba71f4fe89cdca7329bcc41ea7a4c32e478f59b8908443119e850f")
    #expect(sha256(Array(try lc.json())) == "00f4633ec288acdfefd75e7b8242e5d686dec1e6027838cdfd7678078a16a87c")
}
