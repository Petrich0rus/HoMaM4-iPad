import CryptoKit
import Foundation
import Testing
@testable import H4Kit

// Slice 6b: tile API (`pixelRect` renders), `H4MapCanvas` (content rect, projection inverse, hit-test), concurrency.

private func object(_ x: Int, _ y: Int, level: Int = 0, _ model: String = "m", army: Bool = false) -> H4ScenarioObject {
    H4ScenarioObject(offset: 0, x: Int32(x), y: Int32(y), level: Int32(level), modelName: army ? "" : model, triple: nil,
                     classID: army ? H4ScenarioObject.armyClassID : 0, payload: .versionOnly)
}

// MARK: - Projection inverse and content rect (synthetic)

@Test func projectionRoundTrip() throws {
    let (scenario, _) = terrainScenario(size: 12)
    let terrain = try H4ScenarioTerrain(scenario: scenario)
    let canvas = H4MapCanvas(terrain: terrain, level: 0, objects: []) { _ in nil }
    #expect(canvas.width == 32 * 24 && canvas.height == 16 * 24)
    var present = 0
    for r in 0..<12 {
        for c in 0..<12 {
            let here = terrain.cell(level: 0, row: r, column: c) != nil
            let o = canvas.origin(row: r, column: c)
            let centre = (x: Double(o.x + 32), y: Double(o.y + 16))
            guard here else { #expect(canvas.cell(atX: centre.x, y: centre.y) == nil); continue }
            present += 1
            // centre and points just inside the four vertices and the middle of the four edges
            for (dx, dy) in [(0.0, 0.0), (30.5, 0), (-30.5, 0), (0, 15), (0, -15), (15, 7), (-15, 7), (15, -7), (-15, -7), (-31.5, 0.1)] {
                let got = canvas.cell(atX: centre.x + dx, y: centre.y + dy)
                #expect(got?.row == r && got?.column == c, "cell \(r),\(c) offset \(dx),\(dy)")
            }
        }
    }
    #expect(present == terrain.geometry.cellCount)
    #expect(canvas.cell(atX: -5, y: -5) == nil && canvas.cell(atX: Double(canvas.width) + 10, y: 10) == nil)
}

@Test func contentRectBoundsPresentCells() throws {
    for size in [8, 12, 36] {
        let (scenario, _) = terrainScenario(size: size)
        let terrain = try H4ScenarioTerrain(scenario: scenario)
        let canvas = H4MapCanvas(terrain: terrain, level: 0, objects: []) { _ in nil }
        let rect = canvas.contentRect
        #expect(rect.x % 8 == 0 && rect.y % 8 == 0 && rect.width % 8 == 0 && rect.height % 8 == 0)
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for (r, range) in terrain.geometry.cellRows.enumerated() {
            for c in range {
                let o = canvas.origin(row: r, column: c)
                #expect(o.x >= rect.x && o.y >= rect.y && o.x + 64 <= rect.x + rect.width && o.y + 32 <= rect.y + rect.height)
                minX = min(minX, o.x); maxX = max(maxX, o.x + 64); minY = min(minY, o.y); maxY = max(maxY, o.y + 32)
            }
        }
        // Tight: every edge is within 8 px of a present cell.
        #expect(minX - rect.x < 8 && rect.x + rect.width - maxX < 8 && minY - rect.y < 8 && rect.y + rect.height - maxY < 8)
        #expect(rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= canvas.width && rect.y + rect.height <= canvas.height)
    }
}

@Test func terrainNameAndHitTest() throws {
    let (scenario, types) = terrainScenario(size: 12)
    let terrain = try H4ScenarioTerrain(scenario: scenario)
    // Footprints: "big" 3x2 (W along rows, H along columns), "flat" 2x2 ground, "ghost" 1x1 without a body.
    let table: [String: H4MapCanvas.Footprint] = [
        "big": .init(width: 3, height: 2), "flat": .init(width: 2, height: 2, isGround: true),
        "ghost": .init(width: 1, height: 1, isVisible: false), "small": .init(width: 1, height: 1),
    ]
    let objs = [object(4, 4, "big"), object(5, 5, "flat"), object(5, 6, "ghost"), object(7, 5, "small"),
                object(4, 5, "small", army: true), object(5, 5, level: 1, "small"), object(6, 6, "nowhere")]
    let canvas = H4MapCanvas(terrain: terrain, level: 0, objects: objs) { table[$0.modelName] }
    func name(_ r: Int, _ c: Int) -> String? { canvas.object(row: r, column: c)?.modelName }
    // big covers rows 4…6, columns 4…5.
    #expect(name(4, 4) == "big" && name(6, 4) == "big" && name(6, 5) == "big" && name(4, 5) == "big")
    #expect(name(7, 4) == nil && name(4, 6) == nil && name(3, 4) == nil)
    // flat covers (5…6) × (5…6): ground objects lose against the big building where both are on a cell.
    #expect(name(5, 5) == "big" && name(6, 5) == "big")
    #expect(name(5, 6) == "flat" && name(6, 6) == "flat")      // ghost (5,6) has no body; the ground flat wins over it
    // Topmost: small at (7,5) is alone; the level-1 object and the army never answer.
    #expect(name(7, 5) == "small")
    // A body-less object ranks below anything visible but is still found alone.
    let only = H4MapCanvas(terrain: terrain, level: 0, objects: [objs[2]]) { table[$0.modelName] }
    #expect(only.object(row: 5, column: 6)?.modelName == "ghost")
    #expect(canvas.object(row: 0, column: 0) == nil)
    // Terrain names.
    let g = terrain.geometry
    let r = 5, c = g.cellRows[r].lowerBound
    var index = 0
    for k in 0..<r { index += g.cellRows[k].count }
    #expect(canvas.terrainName(row: r, column: c) == H4MapTerrainRender.terrainNames[Int(types[index])])
    #expect(canvas.terrainName(row: 0, column: 0) == nil)
}

@Test func samePositionPrefersLaterObjectAndFartherCorner() throws {
    let (scenario, _) = terrainScenario(size: 12)
    let terrain = try H4ScenarioTerrain(scenario: scenario)
    let fp = H4MapCanvas.Footprint(width: 2, height: 2)
    let objs = [object(5, 5, "a"), object(5, 5, "b"), object(4, 4, "c")]
    let canvas = H4MapCanvas(terrain: terrain, level: 0, objects: objs) { _ in fp }
    #expect(canvas.object(row: 5, column: 5)?.modelName == "b")      // same rank: later list entry on top
    #expect(canvas.object(row: 4, column: 4)?.modelName == "c")
    #expect(canvas.object(row: 5, column: 4)?.modelName == "b" || canvas.object(row: 5, column: 4)?.modelName == "c")
    // (5,4): c covers it with x+y = 8; b covers (5…6)x(5…6) and not (5,4): so it is c.
    #expect(canvas.object(row: 5, column: 4)?.modelName == "c")
    #expect(canvas.object(row: 6, column: 6)?.modelName == "b")
}

@Test func tileRequestMapsLayerRectsToPixels() throws {
    let (scenario, _) = terrainScenario(size: 36)
    let terrain = try H4ScenarioTerrain(scenario: scenario)
    let canvas = H4MapCanvas(terrain: terrain, level: 0, objects: []) { _ in nil }
    let c = canvas.contentRect
    // Retina, zoom 1: 2 canvas px per point, 2 device px per point (1:1) → scale 1, a 256-point tile is 512 px.
    let a = canvas.tileRequest(x: 256, y: 512, width: 256, height: 256, canvasPerPoint: 2, deviceScale: 2)
    #expect(a.scale == 1 && a.pixelRect == .init(x: c.x + 512, y: c.y + 1024, width: 512, height: 512))
    #expect(a.destination == (256, 512, 256, 256))
    // Zoomed out 1/4 (device scale 0.5): scale 4, the 2048-point tile is 512 output pixels.
    let b = canvas.tileRequest(x: 2048, y: 0, width: 2048, height: 2048, canvasPerPoint: 2, deviceScale: 0.5)
    #expect(b.scale == 4 && b.pixelRect == .init(x: (c.x + 4096) / 4, y: c.y / 4, width: 1024, height: 1024))
    #expect(b.destination.width == 2048 && b.destination.x == Double((c.x + 4096) / 4 * 4 - c.x) / 2)
    // Magnified 2x (device scale 4): still scale 1; 128 points are 256 canvas pixels, drawn on 512 device pixels.
    let m = canvas.tileRequest(x: 0, y: 0, width: 128, height: 128, canvasPerPoint: 2, deviceScale: 4)
    #expect(m.scale == 1 && m.pixelRect.width == 256 && m.destination.width == 128)
    // In between LODs round down to the finer scale; the largest scale is 8.
    #expect(canvas.tileRequest(x: 0, y: 0, width: 64, height: 64, canvasPerPoint: 2, deviceScale: 0.7).scale == 2)
    #expect(canvas.tileRequest(x: 0, y: 0, width: 64, height: 64, canvasPerPoint: 2, deviceScale: 0.05).scale == 8)
    // Tiles of one scale tile the plane without gaps: neighbours' pixel rects abut.
    let l = canvas.tileRequest(x: 0, y: 0, width: 1024, height: 1024, canvasPerPoint: 2, deviceScale: 0.25)
    let r = canvas.tileRequest(x: 1024, y: 0, width: 1024, height: 1024, canvasPerPoint: 2, deviceScale: 0.25)
    #expect(l.scale == 8 && l.pixelRect.x + l.pixelRect.width == r.pixelRect.x)
}

// MARK: - Pixel rect semantics (synthetic compositor)

@Test func pixelRectOutsideCanvasIsTransparentAndWindowMatches() throws {
    let terrain = try syntheticMap()
    let compositor = try syntheticCompositor(maskAlpha: 5)
    let region = H4MapTerrainRender.Region.whole(size: 8)
    let whole = try compositor.render(terrain: terrain, level: 0, region: region, scale: 1)
    #expect(whole.width == 512 && whole.height == 256 && whole.pixels.contains { $0 != 0 })
    for k in [1, 2] {
        let full = try compositor.render(terrain: terrain, level: 0, region: region, scale: k)
        // An off-grid window, partly outside the canvas on the left/top/right/bottom.
        let r = H4TerrainCompositor.PixelRect(x: -13, y: -7, width: full.width + 20, height: full.height + 30)
        let win = try compositor.render(terrain: terrain, level: 0, region: region, pixelRect: r, scale: k)
        #expect(win.width == r.width && win.height == r.height)
        for y in 0..<win.height {
            for x in 0..<win.width {
                let fx = x + r.x, fy = y + r.y
                let inside = fx >= 0 && fy >= 0 && fx < full.width && fy < full.height
                let a = Array(win.pixels[((y * win.width + x) * 4)..<((y * win.width + x) * 4 + 4)])
                let b = inside ? Array(full.pixels[((fy * full.width + fx) * 4)..<((fy * full.width + fx) * 4 + 4)]) : [0, 0, 0, 0]
                if a != b { Issue.record("scale \(k) pixel \(x),\(y) differs"); return }
            }
        }
    }
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

private struct Scene: @unchecked Sendable {
    let terrain: H4ScenarioTerrain
    let objects: [H4ScenarioObject]
    let level: Int
    let region: H4MapTerrainRender.Region
}

private func scene(_ dirs: (data: URL, maps: URL), _ file: String, level: Int, region: H4MapTerrainRender.Region?,
                   resolver: H4ObjectClassResolver) throws -> Scene {
    let scenario = try H4Scenario(fileData: Data(contentsOf: dirs.maps.appendingPathComponent(file)))
    let body = try H4ScenarioBody(scenario: scenario, resolver: resolver)
    guard case .complete = body.stop else { throw H4Error.malformed("object list incomplete") }
    return Scene(terrain: try H4ScenarioTerrain(scenario: scenario), objects: body.objects, level: level,
                 region: region ?? .whole(size: scenario.size))
}

/// The mosaic of `tile`-pixel `pixelRect` renders of a scale-`k` image of `size`.
private func mosaic(size: (width: Int, height: Int), tile: Int, _ render: (H4TerrainCompositor.PixelRect) throws -> H4RGBAImage) throws -> [UInt8] {
    var out = [UInt8](repeating: 0, count: size.width * size.height * 4)
    for ty in stride(from: 0, to: size.height, by: tile) {
        for tx in stride(from: 0, to: size.width, by: tile) {
            let rect = H4TerrainCompositor.PixelRect(x: tx, y: ty, width: min(tile, size.width - tx), height: min(tile, size.height - ty))
            let img = try render(rect)
            #expect(img.width == rect.width && img.height == rect.height)
            for y in 0..<rect.height {
                let src = y * rect.width * 4, dst = ((ty + y) * size.width + tx) * 4
                out.replaceSubrange(dst..<(dst + rect.width * 4), with: img.pixels[src..<(src + rect.width * 4)])
            }
        }
    }
    return out
}

private let crops: [(file: String, level: Int, row: Int, column: Int, sha1: String)] = [
    ("A Land without a King.h4c", 0, 80, 64, "d267d4da70299168ffde05d0048f9acce08d3581c7c57048e7586b2c4bc1e03a"),
    ("Zanfas's Challenge.h4c", 0, 200, 88, "2e58c1671c50a2ec82050f28e2459daf2d4403280778eee3535423bc94ab839a"),
    ("Zanfas's Challenge.h4c", 1, 152, 152, "eb8d202c7ce15d1f9b270767d1695f1476147a5360f0b4fe118ee6cd14015e4a"),
]

/// B2: the mosaic of `pixelRect` renders equals the region render (= the ref6o PNGs at scale 1), for the three crops with
/// objects, at scale 1 and 4, with 512-pixel tiles and with an odd tile size that cuts the 128-row bands.
@Test(.enabled(if: ProcessInfo.processInfo.environment["H4_DATA_DIR"] != nil))
func realTileMosaicEqualsRegionRender() throws {
    let dirs = try #require(realDirs)
    let store = try H4ResourceStore(dataDirectory: dirs.data)
    let compositor = try H4TerrainCompositor(store: store)
    let models = H4ObjectModelLibrary(store: store)
    let resolver = H4ObjectClassResolver(resources: store)
    for crop in crops {
        let region = H4MapTerrainRender.Region(row: crop.row, column: crop.column, rows: 32, columns: 32)
        let s = try scene(dirs, crop.file, level: crop.level, region: region, resolver: resolver)
        let list = try H4MapObjectRender.drawList(objects: s.objects, level: s.level, region: region, models: models)
        for k in [1, 4] {
            let whole = try compositor.render(terrain: s.terrain, level: s.level, region: region, scale: k, objects: list)
            if k == 1 { #expect(sha256(whole.pixels) == crop.sha1, "\(crop.file) L\(crop.level)") }
            let plan = try compositor.prepare(terrain: s.terrain, level: s.level, region: region)
            for tile in [512, 200] {
                let m = try mosaic(size: (whole.width, whole.height), tile: tile) {
                    try compositor.render(plan: plan, pixelRect: $0, scale: k, objects: list)
                }
                #expect(m == whole.pixels, "\(crop.file) L\(crop.level) scale \(k) tile \(tile)")
            }
            // The public region+pixelRect entry point agrees as well.
            let one = try compositor.render(terrain: s.terrain, level: s.level, region: region,
                                            pixelRect: .init(x: 0, y: 0, width: whole.width, height: whole.height), scale: k, objects: list)
            #expect(one.pixels == whole.pixels)
        }
    }
    #expect(models.missingModels.isEmpty && compositor.missingTextures.isEmpty && compositor.missingMasks.isEmpty)
}

/// B2 (whole map): "A Land without a King" level 0, region = the whole map, scale 4: 512-pixel mosaic == one render;
/// the content rect holds every present cell and leaves no empty row or column of tiles.
@Test(.enabled(if: ProcessInfo.processInfo.environment["H4_DATA_DIR"] != nil))
func realWholeMapMosaicAndContentRect() throws {
    let dirs = try #require(realDirs)
    let store = try H4ResourceStore(dataDirectory: dirs.data)
    let compositor = try H4TerrainCompositor(store: store)
    let models = H4ObjectModelLibrary(store: store)
    let s = try scene(dirs, "A Land without a King.h4c", level: 0, region: nil, resolver: H4ObjectClassResolver(resources: store))
    let list = try H4MapObjectRender.drawList(objects: s.objects, level: 0, region: s.region, models: models)
    let k = 4
    let whole = try compositor.render(terrain: s.terrain, level: 0, region: s.region, scale: k, objects: list)
    let size = H4MapCanvas.canvasSize(region: s.region, scale: k)
    #expect(whole.width == size.width && whole.height == size.height)
    let plan = try compositor.prepare(terrain: s.terrain, level: 0, region: s.region)
    let m = try mosaic(size: size, tile: 512) { try compositor.render(plan: plan, pixelRect: $0, scale: k, objects: list) }
    #expect(m == whole.pixels)

    let canvas = try H4MapCanvas(terrain: s.terrain, level: 0, objects: s.objects, models: models)
    let rect = canvas.contentRect
    #expect(rect.width < canvas.width || rect.height < canvas.height)
    // Every tile (512 px at each scale) of the content rect holds a cell: none of the tile rows/columns is empty.
    for scale in [1, 4] {
        let tileSpan = 512 * scale
        let cols = (rect.width + tileSpan - 1) / tileSpan, rows = (rect.height + tileSpan - 1) / tileSpan
        var colHit = [Bool](repeating: false, count: cols), rowHit = [Bool](repeating: false, count: rows)
        for (r, range) in s.terrain.geometry.cellRows.enumerated() {
            for c in range {
                let o = canvas.origin(row: r, column: c)
                #expect(o.x >= rect.x && o.y >= rect.y && o.x + 64 <= rect.x + rect.width && o.y + 32 <= rect.y + rect.height)
                for x in [o.x, o.x + 63] { colHit[(x - rect.x) / tileSpan] = true }
                for y in [o.y, o.y + 31] { rowHit[(y - rect.y) / tileSpan] = true }
            }
        }
        #expect(colHit.allSatisfy { $0 } && rowHit.allSatisfy { $0 }, "empty tile row/column at scale \(scale)")
    }
    // Every object with a model answers on the first cell of its footprint (some visible one is on top).
    var answered = 0
    for o in s.objects where Int(o.level) == 0 && o.classID != H4ScenarioObject.armyClassID {
        if canvas.object(row: Int(o.x), column: Int(o.y)) != nil { answered += 1 }
    }
    #expect(answered > 100)
    let any = try #require(s.objects.first { $0.classID != H4ScenarioObject.armyClassID && $0.level == 0 })
    let o = canvas.origin(row: Int(any.x), column: Int(any.y))
    let back = canvas.cell(atX: Double(o.x + 32), y: Double(o.y + 16))
    #expect(back?.row == Int(any.x) && back?.column == Int(any.y))
}

/// B2c: six concurrent tasks render the B2 mosaics of the three crops (with objects, scales 1 and 4) against ONE fresh
/// shared compositor and model library (empty caches: the first touches race). Results equal the reference digests.
/// Run under `swift test --sanitize=thread --filter realConcurrentMosaics`.
@Test(.enabled(if: ProcessInfo.processInfo.environment["H4_DATA_DIR"] != nil))
func realConcurrentMosaics() throws {
    let dirs = try #require(realDirs)
    let store = try H4ResourceStore(dataDirectory: dirs.data)
    let resolver = H4ObjectClassResolver(resources: store)
    let regions = crops.map { H4MapTerrainRender.Region(row: $0.row, column: $0.column, rows: 32, columns: 32) }
    let scenes = try crops.indices.map { try scene(dirs, crops[$0].file, level: crops[$0].level, region: regions[$0], resolver: resolver) }
    // Expected scale-4 digests come from a serial reference compositor (a separate instance).
    let reference = try H4TerrainCompositor(store: store)
    let refModels = H4ObjectModelLibrary(store: store)
    var expected4Build: [String] = []
    for i in crops.indices {
        let list = try H4MapObjectRender.drawList(objects: scenes[i].objects, level: scenes[i].level, region: regions[i], models: refModels)
        expected4Build.append(sha256(try reference.render(terrain: scenes[i].terrain, level: scenes[i].level, region: regions[i], scale: 4, objects: list).pixels))
    }

    let expected4 = expected4Build
    let shared = try H4TerrainCompositor(store: store)             // fresh caches, shared by all tasks
    let sharedModels = H4ObjectModelLibrary(store: store)
    let tasks = 6
    let lock = NSLock()
    nonisolated(unsafe) var failures: [String] = []
    nonisolated(unsafe) var done = 0
    DispatchQueue.concurrentPerform(iterations: tasks) { t in
        do {
            for step in 0..<crops.count {
                let i = (t + step) % crops.count                   // different crops first for different tasks
                let list = try H4MapObjectRender.drawList(objects: scenes[i].objects, level: scenes[i].level, region: regions[i], models: sharedModels)
                for k in (t % 2 == 0 ? [1, 4] : [4, 1]) {
                    let size = H4MapCanvas.canvasSize(region: regions[i], scale: k)
                    let m = try mosaic(size: size, tile: t % 3 == 0 ? 512 : 256) {
                        try shared.render(terrain: scenes[i].terrain, level: scenes[i].level, region: regions[i], pixelRect: $0, scale: k, objects: list)
                    }
                    let digest = sha256(m)
                    let want = k == 1 ? crops[i].sha1 : expected4[i]
                    if digest != want { lock.lock(); failures.append("task \(t) crop \(i) scale \(k)"); lock.unlock() }
                }
            }
        } catch {
            lock.lock(); failures.append("task \(t): \(error)"); lock.unlock()
        }
        lock.lock(); done += 1; lock.unlock()
    }
    #expect(done == tasks)
    #expect(failures.isEmpty, "\(failures)")
    #expect(shared.missingTextures.isEmpty && shared.missingMasks.isEmpty && sharedModels.missingModels.isEmpty)
}
