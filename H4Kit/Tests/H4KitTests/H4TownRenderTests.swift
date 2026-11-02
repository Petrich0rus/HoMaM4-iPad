import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import H4Kit

// Slice 8b: town screen rendering (reference `town_ref.py`, rules R1-R7).
// Synthetic layers and footprints exercise the rules without the game; data-gated tests replay the frozen oracle.
//   H4_DATA_DIR, H4_MAPS_DIR     game folders
//   H4_TOWN_ORACLE_DIR           the oracle root (SCRATCH): step3/town8b

private let env = ProcessInfo.processInfo.environment
private let hasOracle = env["H4_DATA_DIR"] != nil && env["H4_TOWN_ORACLE_DIR"] != nil
private let hasMaps = hasOracle && env["H4_MAPS_DIR"] != nil

// MARK: - Fixtures

/// A fully opaque rectangle layer `w x h` at (left, top) with palette entry 1 = (r, g, b); `holes` are pixels with alpha 0 (row, column).
private func rect(_ name: String, left: Int, top: Int, w: Int, h: Int, rgb: (UInt8, UInt8, UInt8), holes: Set<[Int]> = []) throws -> H4Layer {
    var f = LayerFixture()
    f.name = name
    f.rect = (Int32(left), Int32(top), Int32(left + w), Int32(top + h))
    f.palette = [(0, 0, 0), (rgb.2, rgb.1, rgb.0)]
    f.spans = (0..<h).map { (0, UInt16(w), UInt32($0 * w)) }
    f.indices = [UInt8](repeating: 1, count: w * h)
    f.alphaNibbles = (0..<(w * h)).map { holes.contains([$0 / w, $0 % w]) ? 0 : 15 }
    f.coverage = false
    return try #require(try H4LayerGroup(data: group([f])).layers.first)
}

private func item(_ id: Int, _ layer: H4Layer) -> H4TownSceneItem {
    H4TownSceneItem(id: id, keyword: "b\(id)", layout: layer, shadow: nil, parts: [(layer, layer.left, layer.top)])
}

private func px(_ img: H4RGBAImage, _ x: Int, _ y: Int) -> [UInt8] { pixel(img, x, y) }

// MARK: - Tables

@Test func backgroundTableMatchesTheExe() {
    // R1b [D 0x8ab0d0]
    let expected = ["sand", "grass", "rough", "swamp", "volcanic", "snow", "sand", "dirt", "subterranean",
                    "sand", "volcanic", "snow", "grass", "grass", "grass", "grass", "grass", "grass", "grass"]
    #expect((0..<19).map { H4TownRender.backgroundName(terrain: $0) } == expected)
    #expect(H4TownRender.backgroundName(terrain: 19) == nil && H4TownRender.backgroundName(terrain: -1) == nil)
    #expect(!expected.contains("volcano"))
}

@Test func buildingKeywordsAre172AndShadowAliasesExist() {
    #expect((0..<6).reduce(0) { $0 + H4TownRules.keywords[$1].count } == 172)
    #expect(H4TownRender.keyword(faction: 5, building: 41) == "magic dampener" && H4TownRender.keyword(faction: 5, building: 20) == nil)
    #expect(H4TownRender.shadowAlias["magic dampener"] == "magic dampner shadow" && H4TownRender.shadowAlias["cemetery"] == "cemetary shadow")
}

@Test func displayedKeepsTheHighestTierAndIgnoresForeignIds() {
    // R2b: halls 0-2, keeps 3-5, mage guilds 20-24: highest only; others as built; ids of other factions ignored
    #expect(H4TownRender.displayed(faction: 0, built: [0, 1, 3, 4, 5, 8, 20, 22, 21, 9]) == [1, 5, 8, 9, 22])
    #expect(H4TownRender.displayed(faction: 0, built: [0, 2, 1]) == [2])
    #expect(H4TownRender.displayed(faction: 5, built: [0, 20, 21, 12, 35, 27]) == [0, 12, 35])   // might: no mage guild, no seminary
    #expect(H4TownRender.displayed(faction: 1, built: [14, 15, 16, 17]) == [14, 15, 16, 17])      // exclusive dwellings are not filtered here
    #expect(H4TownRender.maskIDs(0b1_0000_0001_0101) == [0, 2, 4, 12])
}

// MARK: - Z-order and hit-test

@Test func zOrderSortsByBottomThenId() throws {
    let a = try rect("a", left: 0, top: 0, w: 4, h: 10, rgb: (1, 1, 1))      // bottom 10
    let b = try rect("b", left: 0, top: 5, w: 4, h: 5, rgb: (1, 1, 1))       // bottom 10
    let c = try rect("c", left: 0, top: 0, w: 4, h: 3, rgb: (1, 1, 1))       // bottom 3
    let sorted = H4TownRender.zOrder([item(9, a), item(4, b), item(7, c)])
    #expect(sorted.map(\.id) == [7, 4, 9])                                    // c first (bottom 3); a and b tie on 10: id 4 before 9
}

@Test func hitTestCraftedTwoLayerStack() throws {
    // low (id 9, bottom 16) is under top (id 4, bottom 18); top has a hole at (1,1) -> falls through to low
    let low = try rect("low", left: 10, top: 10, w: 6, h: 6, rgb: (10, 0, 0))                     // bottom 16
    let top = try rect("top", left: 12, top: 12, w: 6, h: 6, rgb: (0, 20, 0), holes: [[1, 1]])     // bottom 18
    let fg = try rect("foreground 1", left: 0, top: 0, w: 100, h: 100, rgb: (0, 0, 30))
    let bg = try rect("background", left: 0, top: 0, w: 1280, h: 825, rgb: (5, 5, 5))
    let scene = H4TownScene(background: H4LayerGroup(layers: [bg, fg]), items: H4TownRender.zOrder([item(9, low), item(4, top)]), errors: [])
    let hits = try scene.hitTest(points: [(11, 11), (13, 13), (14, 14), (16, 16), (17, 17), (18, 18), (50, 50), (-1, 5), (1280, 5), (5, 825)])
    #expect(hits[0].id == 9 && hits[0].name == "b9" && hits[0].stack == [9])           // only low
    #expect(hits[1].id == 9 && hits[1].stack == [9])                                   // hole of top at (13,13): falls through
    #expect(hits[2].id == 4 && hits[2].stack == [4, 9])                                // overlap: topmost first
    #expect(hits[3].id == 4 && hits[3].stack == [4])                                   // (16,16) is outside low (10...15) -> only top
    #expect(hits[4].id == 4 && hits[5].id == nil && hits[5].stack == [])               // (18,18) is outside both
    #expect(hits[6].id == nil && hits[6].name == nil)                                  // foreground only: not clickable, empty ground
    #expect(hits[7].id == nil && hits[8].id == nil && hits[9].id == nil)               // outside the scene
}

@Test func renderOrderBackgroundShadowsBuildingsForegrounds() throws {
    let bg = try rect("background", left: 0, top: 0, w: 1280, h: 825, rgb: (200, 100, 50))
    let fg = try rect("foreground 1", left: 20, top: 20, w: 4, h: 4, rgb: (1, 2, 3))
    let shadow = try rect("x shadow", left: 8, top: 8, w: 6, h: 6, rgb: (9, 9, 9))
    let building = try rect("x", left: 10, top: 10, w: 4, h: 4, rgb: (7, 7, 7))
    var it = item(3, building)
    it.shadow = shadow
    let scene = H4TownScene(background: H4LayerGroup(layers: [bg, fg]), items: [it], errors: [])
    let (img, list) = try scene.render()
    #expect(list.map(\.kind) == [.background, .shadow, .building, .foreground])
    #expect(list.map(\.id) == [nil, 3, 3, nil] && list.map(\.layer) == ["background", "x shadow", "x", "foreground 1"])
    #expect(px(img, 8, 8) == [9, 9, 9, 255] && px(img, 11, 11) == [7, 7, 7, 255] && px(img, 21, 21) == [1, 2, 3, 255])
    #expect(px(img, 0, 0) == [200, 100, 50, 255] && px(img, 1279, 824) == [200, 100, 50, 255])
    // R4: identical to H4Layer.draw on the same canvas
    var ref = H4RGBAImage(width: 1280, height: 825, pixels: [UInt8](repeating: 0, count: 1280 * 825 * 4))
    for l in [bg, shadow, building, fg] { l.draw(into: &ref, originX: 0, originY: 0) }
    #expect(img == ref)
    // a scene with a missing layout layer or without a background layer does not render
    #expect(throws: Error.self) { try H4TownScene(background: H4LayerGroup(layers: [bg]), items: [], errors: ["layout layer missing: x (id 3)"]).render() }
    #expect(throws: Error.self) { try H4TownScene(background: H4LayerGroup(layers: [fg]), items: [], errors: []).render() }
}

// MARK: - Terrain algorithm (R1a)

private struct Grid {
    var cells: [[Int]: Int]            // [x, y] -> terrain; missing = outside the map
    func inMap(_ x: Int, _ y: Int) -> Bool { cells[[x, y]] != nil }
    func at(_ x: Int, _ y: Int) -> Int { cells[[x, y]] ?? 0 }
}

private func run(_ g: Grid, x: Int, y: Int, w: Int, h: Int, eh: Set<Int> = [], ev: Set<Int> = []) -> H4TownTerrain {
    H4TownRender.terrain(x: x, y: y, width: w, height: h,
                         edgesHorizontal: (0..<((h + 1) * w)).map { eh.contains($0) }, edgesVertical: (0..<((w + 1) * h)).map { ev.contains($0) },
                         inMap: g.inMap, terrainAt: g.at)
}

private func block(_ x0: Int, _ y0: Int, _ n: Int, _ m: Int, _ t: Int) -> [[Int]: Int] {
    var d: [[Int]: Int] = [:]
    for x in x0..<(x0 + n) { for y in y0..<(y0 + m) { d[[x, y]] = t } }
    return d
}

@Test func terrainEntranceUsesThePlusOneOffset() {
    // 2x2 footprint at (10,20); horizontal edge bit (i=1,j=0) -> P = (X + i + 1, Y + j) = (12, 20), NOT (11, 20)
    var cells = block(8, 18, 6, 6, 1)
    cells[[12, 20]] = 5
    cells[[11, 20]] = 3
    let r = run(Grid(cells: cells), x: 10, y: 20, w: 2, h: 2, eh: [1])
    #expect(r.entrance?.i == 1 && r.entrance?.j == 0)
    #expect(r.reference == (12, 20) && r.terrain == 5 && r.t0 == 5 && r.mode == .direct)
    // vertical edge bit on the last line (i = W, j = 0): ev[i * H + j] = ev[4]; found after the loop of i = 0, 1 found nothing
    let v = run(Grid(cells: cells), x: 10, y: 20, w: 2, h: 2, ev: [4])
    #expect(v.entrance?.i == 2 && v.entrance?.j == 0 && v.reference == (13, 20))
    // no edge at all: P is the origin and the entrance is nil
    let none = run(Grid(cells: cells), x: 10, y: 20, w: 2, h: 2)
    #expect(none.entrance == nil && none.reference == (10, 20) && none.terrain == 1 && none.mode == .direct)
    // outer loop is i: (i=0, j=2) is found before (i=1, j=0)
    let order = run(Grid(cells: cells), x: 10, y: 20, w: 2, h: 2, eh: [1, 4])
    #expect(order.entrance?.i == 0 && order.entrance?.j == 2 && order.reference == (11, 22))
}

@Test func terrainScanLastTieWins() {
    // entrance at (i=0, j=1) -> P = (X+1, Y+1) = (11, 21) is water. Footprint cells: (10,20) d=2, (11,20) d=1, (10,21) d=1.
    // Scan order a (x) outer, b (y) inner: (10,20), (10,21), (11,20), (11,21): the last cell at distance 1 is (11,20).
    let cells: [[Int]: Int] = [[10, 20]: 2, [10, 21]: 6, [11, 20]: 4, [11, 21]: 0]
    let r = run(Grid(cells: cells), x: 10, y: 20, w: 2, h: 2, eh: [2])
    #expect(r.reference == (11, 21) && r.t0 == 0)
    #expect(r.mode == .scan && r.terrain == 4)
    // swapping the two tied terrains changes the answer: the last of the scan still wins
    var swapped = cells
    swapped[[10, 21]] = 4; swapped[[11, 20]] = 6
    #expect(run(Grid(cells: swapped), x: 10, y: 20, w: 2, h: 2, eh: [2]).terrain == 6)
    // a river/special reference cell (9...18) also triggers the scan; cells outside the map or of terrain 0/9+ never qualify
    var river = cells
    river[[11, 21]] = 11; river[[11, 20]] = 12; river[[10, 21]] = 0
    let rv = run(Grid(cells: river), x: 10, y: 20, w: 2, h: 2, eh: [2])
    #expect(rv.t0 == 11 && rv.terrain == 2 && rv.mode == .scan)
    // the reference cell outside the map reads as 0
    let outside = run(Grid(cells: [[10, 20]: 7]), x: 10, y: 20, w: 2, h: 2, eh: [2])
    #expect(outside.t0 == 0 && outside.terrain == 7 && outside.mode == .scan)
    // no qualifying cell: the terrain stays t0, mode none
    let nothing = run(Grid(cells: block(10, 20, 2, 2, 10)), x: 10, y: 20, w: 2, h: 2, eh: [2])
    #expect(nothing.terrain == 10 && nothing.t0 == 10 && nothing.mode == .none)
}

// MARK: - JSON

@Test func prettyJSONFormatMatchesPythonIndent1() {
    let v = H4PrettyJSON.obj(["b": .arr([.int(1), .arr([]), .null]), "a": .obj([:]), "10": .str("x\"\n"), "2": .int(-3)])
    #expect(H4PrettyJSON.text(v) == "{\n \"10\": \"x\\\"\\n\",\n \"2\": -3,\n \"a\": {},\n \"b\": [\n  1,\n  [],\n  null\n ]\n}\n")
}

// MARK: - Game data (gated)

private let oracle = (env["H4_TOWN_ORACLE_DIR"] ?? "") + "/step3/town8b"

private func text(_ path: String) throws -> String { try String(contentsOfFile: path, encoding: .utf8) }

private func rgba(png path: String) throws -> H4RGBAImage {
    let src = try #require(CGImageSourceCreateWithData(try Data(contentsOf: URL(fileURLWithPath: path)) as CFData, nil))
    let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
    var px = [UInt8](repeating: 0, count: img.width * img.height * 4)
    let ctx = try #require(CGContext(data: &px, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    return H4RGBAImage(width: img.width, height: img.height, pixels: px)
}

@Test(.enabled(if: hasOracle)) func scenesDrawListsAndHitsMatchTheOracle() throws {
    let renderer = H4TownRenderer(store: try H4ResourceStore(dataDirectory: URL(fileURLWithPath: env["H4_DATA_DIR"]!)))
    let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: oracle + "/scenes.json"))) as? [String: Any])
    let scenes = try #require(root["scenes"] as? [[String: Any]])
    #expect(scenes.count == 12)
    var points = 0
    for s in scenes {
        let name = s["name"] as! String
        let fac = try #require(H4TownRules.factions.firstIndex(of: s["faction"] as! String))
        let bg = s["bg"] as! String
        let built = s["built"] as! [Int]
        let terrain = s["terrain"] as! Int
        #expect(H4TownRender.backgroundName(terrain: terrain) == bg, "\(name)")
        let clock = ContinuousClock()
        var result: (image: H4RGBAImage, drawList: [H4TownDrawItem])?
        let elapsed = try clock.measure { result = try renderer.render(faction: fac, background: bg, built: built) }
        let (image, list) = try #require(result)
        print("scene \(name): \(elapsed)")
        // B1: decoded pixels and draw list
        let expected = try rgba(png: oracle + "/" + (s["png"] as! String))
        #expect(image == expected, "pixels of \(name)")
        #expect(H4TownBatch.drawListJSON(list) == (try text(oracle + "/" + (s["draw"] as! String))), "draw list of \(name)")
        // B2: hit-test answers
        let pts = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: oracle + "/hits/\(name).points.json"))) as? [[Int]])
        let hits = try renderer.hitTest(faction: fac, background: bg, built: built, points: pts.map { ($0[0], $0[1]) })
        #expect(H4TownBatch.hitsJSON(hits) == (try text(oracle + "/hits/\(name).hits.json")), "hits of \(name)")
        points += pts.count
    }
    #expect(points == 30)
}

@Test(.enabled(if: hasMaps)) func townTerrainOfTheShippedTownsMatchesTheOracle() throws {
    let json = try H4TownBatch.terrainAllJSON(dataDirectory: URL(fileURLWithPath: env["H4_DATA_DIR"]!),
                                              mapsDirectory: URL(fileURLWithPath: env["H4_MAPS_DIR"]!))
    #expect(json == (try text(oracle + "/towns_terrain.json")))
}

@Test(.enabled(if: hasMaps)) func everyShippedTownHasItsLayersAndThumbnails() throws {
    let r = try H4TownBatch.checkAllJSON(dataDirectory: URL(fileURLWithPath: env["H4_DATA_DIR"]!),
                                         mapsDirectory: URL(fileURLWithPath: env["H4_MAPS_DIR"]!))
    #expect(r.towns == 657 && r.missing == 0 && r.ignored == 2)
    #expect(r.json == (try text(oracle + "/missing.json")))
}

@Test(.enabled(if: hasOracle)) func thumbnailLookupMatchesTheOracle() throws {
    let json = try H4TownBatch.thumbsAllJSON(dataDirectory: URL(fileURLWithPath: env["H4_DATA_DIR"]!))
    #expect(json == (try text(oracle + "/thumbs.json")))
}
