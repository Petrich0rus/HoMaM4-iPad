import CryptoKit
import Foundation

// Slice 8b — town screen rendering: terrain id and background of a town, draw list, 1280x825 RGBA scene, hit-test, build thumbnails.
//
// Rules R1-R7 of the frozen reference `town_ref.py` (the reference code governs). Tags: [D] decoded from heroes4.exe (GOG 1.3,
// addresses = VA), [V] validated on the data, [I] inferred and pinned by the reference. The scene is drawn at scale 1; the window
// scale (clientWidth * 0.00078125, [D] 0x8b6140/0x8b6230) belongs to the app.

// MARK: - Results

/// How the terrain id of a town was found (R1a).
public enum H4TownTerrainMode: String, Sendable { case direct, scan, none }

/// Result of the town terrain algorithm [D 0x894bc0].
public struct H4TownTerrain: Sendable, Equatable {
    /// Terrain id used to pick the background (0...18).
    public var terrain: Int
    /// Footprint offset (i, j) of the entrance found by the edge scan, or nil.
    public var entrance: (i: Int, j: Int)?
    /// Cell whose terrain was read first (the "ref" of the reference).
    public var reference: (x: Int, y: Int)
    public var mode: H4TownTerrainMode
    /// Terrain of the reference cell (the value the town stores).
    public var t0: Int

    public static func == (a: H4TownTerrain, b: H4TownTerrain) -> Bool {
        a.terrain == b.terrain && a.entrance?.i == b.entrance?.i && a.entrance?.j == b.entrance?.j
            && a.reference == b.reference && a.mode == b.mode && a.t0 == b.t0
    }
}

/// One entry of the draw list (R7), in drawing order.
public struct H4TownDrawItem: Sendable, Equatable {
    public enum Kind: String, Sendable { case background, shadow, building, foreground }
    public var kind: Kind
    /// Building id for shadows and buildings.
    public var id: Int?
    public var layer: String
    public var x: Int
    public var y: Int
}

/// Answer of a hit-test (R5): the topmost displayed building and the whole stack (topmost first).
public struct H4TownHit: Sendable, Equatable {
    public var x: Int, y: Int
    public var id: Int?
    public var name: String?
    public var stack: [Int]
}

/// Build-dialog thumbnail of a building (R6).
public struct H4TownThumbnail: Sendable {
    public var keyword: String
    public var layer: H4Layer?
}

// MARK: - Tables and rules

public enum H4TownRender {
    /// Scene size at scale 1.
    public static let sceneWidth = 1280, sceneHeight = 825

    // [D] exe 0x8ab0d0 (per-faction 19-entry tables indexed by the adventure terrain id; names 0x9958dc..0x9958f8, faction names 0x996634):
    // slots 1...8 = grass, rough, swamp, volcanic, snow, sand, dirt, subterranean; 9...18 are first filled with grass, then
    // 0 := sand, 9 := sand, 10 := volcanic, 11 := snow. "volcano" (chaos) is not referenced by the exe.
    static let backgroundNames = ["sand", "grass", "rough", "swamp", "volcanic", "snow", "sand", "dirt", "subterranean",
                                  "sand", "volcanic", "snow", "grass", "grass", "grass", "grass", "grass", "grass", "grass"]

    /// Background name of a terrain id 0...18 (R1b); nil for ids that do not exist.
    public static func backgroundName(terrain id: Int) -> String? {
        backgroundNames.indices.contains(id) ? backgroundNames[id] : nil
    }

    /// Resource name of the background / layout group of a faction.
    public static func resourceName(faction: Int, group: String) -> String {
        "layers.town.\(H4TownRules.factions[faction]).\(group).h4d"
    }

    /// Keyword (layer name) of a building id for a faction, nil if the faction has no such building (R2b).
    public static func keyword(faction: Int, building id: Int) -> String? { H4TownRules.keywords[faction][id] }

    static let halls = [0, 1, 2], keeps = [3, 4, 5], guilds = [20, 21, 22, 23, 24]
    static let shadowAlias = ["magic dampener": "magic dampner shadow", "cemetery": "cemetary shadow"]   // [D data] typos of the shipped layer names

    /// Ids drawn for a set of built ids (R2b): ids that are no building of the faction are ignored; only the highest hall, keep and
    /// mage guild is kept. Ascending.
    public static func displayed(faction: Int, built: [Int]) -> [Int] {
        let table = H4TownRules.keywords[faction]
        var out = Set(built.filter { table[$0] != nil })
        let all = out
        for group in [halls, keeps, guilds] {
            let have = group.filter { all.contains($0) }
            for b in have.dropLast() { out.remove(b) }
        }
        return out.sorted()
    }

    /// Ids of the bits set in a building mask (0...42).
    public static func maskIDs(_ mask: Int) -> [Int] { (0..<H4TownRules.buildingCount).filter { mask >> $0 & 1 != 0 } }

    /// R3 [I]: ascending bottom edge of the displayed layout layer, ties by ascending building id (shadows follow the same order).
    static func zOrder(_ items: [H4TownSceneItem]) -> [H4TownSceneItem] {
        items.sorted { ($0.layout.bottom, $0.id) < ($1.layout.bottom, $1.id) }
    }

    // MARK: R1a terrain

    /// Terrain id of a town [D 0x894bc0]. `(x, y)` = the town object's cell, `width`/`height` = footprint of its model,
    /// `edgesHorizontal[j * width + i]` / `edgesVertical[i * height + j]` = the model's edge bits, `inMap` / `terrainAt` read the
    /// level of the town (a cell outside the map reads as 0).
    public static func terrain(x X: Int, y Y: Int, width W: Int, height H: Int, edgesHorizontal eh: [Bool], edgesVertical ev: [Bool],
                               inMap: (Int, Int) -> Bool, terrainAt: (Int, Int) -> Int) -> H4TownTerrain {
        // 1. entrance search: i = 0...W outer, j = 0...H inner, first hit stops both loops
        var found: (i: Int, j: Int)?
        search: for i in 0...W {
            for j in 0...H where (i < W && eh[j * W + i]) || (j < H && ev[i * H + j]) {
                found = (i, j)
                break search
            }
        }
        // [D] the asm adds the already incremented outer counter: P = (X + i + 1, Y + j)
        let p = found.map { (x: X + $0.i + 1, y: Y + $0.j) } ?? (x: X, y: Y)
        let t0 = inMap(p.x, p.y) ? terrainAt(p.x, p.y) : 0
        if (1...8).contains(t0) { return H4TownTerrain(terrain: t0, entrance: found, reference: p, mode: .direct, t0: t0) }
        // 3. nearest footprint cell with terrain 1...8; d <= best: the last cell among equal minima wins
        var best = 1000, result = t0
        var mode = H4TownTerrainMode.none
        for a in 0..<W {
            for b in 0..<H {
                let cx = X + a, cy = Y + b
                guard inMap(cx, cy) else { continue }
                let t = terrainAt(cx, cy)
                guard (1...8).contains(t) else { continue }
                let d = (p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)
                if d <= best { best = d; result = t; mode = .scan }
            }
        }
        return H4TownTerrain(terrain: result, entrance: found, reference: p, mode: mode, t0: t0)
    }
}

// MARK: - Scene

/// A displayed building with its layout layer, shadow and sprite parts (R2).
public struct H4TownSceneItem: Sendable {
    public var id: Int
    public var keyword: String
    public var layout: H4Layer
    public var shadow: H4Layer?
    /// Sprite parts in drawing order (a layer and the canvas position of its top-left corner).
    public var parts: [(layer: H4Layer, x: Int, y: Int)]
}

/// The layers of a town scene for one faction, background and built set (R2, R3).
public struct H4TownScene: Sendable {
    public var background: H4LayerGroup
    /// In R3 order (ascending layout bottom, then building id).
    public var items: [H4TownSceneItem]
    /// Displayed buildings without a layout layer (must be empty to render).
    public var errors: [String]
}

extension H4TownScene {
    /// The 1280x825 RGBA scene and its draw list (R3, R4, R7). The canvas starts transparent; the opaque background fills it.
    public func render() throws -> (image: H4RGBAImage, drawList: [H4TownDrawItem]) {
        let scene = self
        if !scene.errors.isEmpty { throw H4Error.malformed(scene.errors.joined(separator: "; ")) }
        var canvas = H4RGBAImage(width: H4TownRender.sceneWidth, height: H4TownRender.sceneHeight,
                                 pixels: [UInt8](repeating: 0, count: H4TownRender.sceneWidth * H4TownRender.sceneHeight * 4))
        var list: [H4TownDrawItem] = []
        guard let bgl = scene.background.layers.first, bgl.name.lowercased() == "background" else {
            throw H4Error.malformed("town background without a 'background' layer")
        }
        /// Draws `layer` with its top-left corner at (x, y).
        func put(_ layer: H4Layer, _ x: Int, _ y: Int) { layer.draw(into: &canvas, originX: x - layer.left, originY: y - layer.top) }
        put(bgl, bgl.left, bgl.top)
        list.append(H4TownDrawItem(kind: .background, id: nil, layer: bgl.name, x: bgl.left, y: bgl.top))
        for it in scene.items {
            if let s = it.shadow {
                put(s, s.left, s.top)
                list.append(H4TownDrawItem(kind: .shadow, id: it.id, layer: s.name, x: s.left, y: s.top))
            }
        }
        for it in scene.items {
            for p in it.parts {
                put(p.layer, p.x, p.y)
                list.append(H4TownDrawItem(kind: .building, id: it.id, layer: p.layer.name, x: p.x, y: p.y))
            }
        }
        for f in scene.background.layers.dropFirst() where !f.isEmpty {
            put(f, f.left, f.top)
            list.append(H4TownDrawItem(kind: .foreground, id: nil, layer: f.name, x: f.left, y: f.top))
        }
        return (canvas, list)
    }

    /// Hit-test (R5) of scene points: the topmost displayed building with alpha > 0 at the point; shadows and foregrounds are ignored.
    public func hitTest(points: [(x: Int, y: Int)]) throws -> [H4TownHit] {
        let scene = self
        if !scene.errors.isEmpty { throw H4Error.malformed(scene.errors.joined(separator: "; ")) }
        return points.map { pt in
            var stack: [H4TownSceneItem] = []
            if (0..<H4TownRender.sceneWidth).contains(pt.x), (0..<H4TownRender.sceneHeight).contains(pt.y) {
                for it in scene.items.reversed() where it.parts.contains(where: { H4TownScene.opaque($0.layer, at: pt.x - $0.x, pt.y - $0.y) }) {
                    stack.append(it)
                }
            }
            return H4TownHit(x: pt.x, y: pt.y, id: stack.first?.id, name: stack.first?.keyword, stack: stack.map(\.id))
        }
    }

    /// Alpha > 0 at (column, row) relative to the layer's top-left corner.
    static func opaque(_ layer: H4Layer, at column: Int, _ row: Int) -> Bool {
        guard row >= 0, row < layer.spans.count else { return false }
        let s = layer.spans[row]
        guard column >= s.start, column < s.end else { return false }
        return layer.alphaValue(s.offset + column - s.start) > 0
    }
}

/// Reads the town resources of a store and renders scenes. Groups are cached.
public final class H4TownRenderer: @unchecked Sendable {
    public let store: H4ResourceStore
    private var groups: [String: H4LayerGroup] = [:]
    private var animations: [String: (group: H4LayerGroup, order: [Int]?)?] = [:]

    public init(store: H4ResourceStore) { self.store = store }

    /// A layer group resource (throws `H4Error.notFound` when missing); cached.
    public func group(_ name: String) throws -> H4LayerGroup {
        let key = name.lowercased()
        if let g = groups[key] { return g }
        let g = try H4LayerGroup(data: store.data(for: name))
        groups[key] = g
        return g
    }

    /// `animation.town.*`: a group followed by u16 version, u16 duration, u32 count, count * u32 order [, version >= 2: 10 bytes].
    /// The reference does not check the order against the frame count here. nil when the resource does not exist.
    private func animation(_ name: String) throws -> (group: H4LayerGroup, order: [Int]?)? {
        let key = name.lowercased()
        if let a = animations[key] { return a }
        let value: (group: H4LayerGroup, order: [Int]?)?
        if (try? store.resolve(name)) == nil {
            value = nil
        } else {
            var r = ByteReader(try store.data(for: name))
            let g = try H4LayerGroup.read(&r)
            var order: [Int]?
            if r.remaining > 0 {
                let version = try r.u16()
                _ = try r.u16()
                let n = Int(try r.u32())
                guard n <= r.remaining / 4 else { throw H4Error.truncated(at: r.offset, needed: n * 4) }
                order = try (0..<n).map { _ in Int(try r.u32()) }
                if version >= 2 { _ = try r.bytes(10) }
            }
            guard r.remaining == 0 else { throw H4Error.malformed("trailing bytes in \(name)") }
            value = (g, order)
        }
        animations[key] = .some(value)
        return value
    }

    /// Layers of the scene of `built` ids in a faction on a background name (R2, R3).
    public func plan(faction: Int, background: String, built: [Int]) throws -> H4TownScene {
        let layout = try group(H4TownRender.resourceName(faction: faction, group: "layout"))
        let bg = try group(H4TownRender.resourceName(faction: faction, group: background))
        var items: [H4TownSceneItem] = []
        var errors: [String] = []
        for b in H4TownRender.displayed(faction: faction, built: built) {
            let kw = H4TownRender.keyword(faction: faction, building: b)!
            guard let l = layout.layer(named: kw) else {
                errors.append("layout layer missing: \(kw) (id \(b))")
                continue
            }
            var shadow = layout.layer(named: H4TownRender.shadowAlias[kw] ?? kw + " shadow")
            if let s = shadow, s.isEmpty { shadow = nil }
            var parts: [(layer: H4Layer, x: Int, y: Int)] = [(l, l.left, l.top)]
            if let anim = try animation("animation.town.\(H4TownRules.factions[faction]).\(kw).h4d"),
               let base = anim.group.layer(named: "base"), let order = anim.order, !order.isEmpty {
                parts = []
                if !base.isEmpty { parts.append((base, l.left + base.left, l.top + base.top)) }
                if order[0] < anim.group.layers.count {
                    let f = anim.group.layers[order[0]]
                    if !f.isEmpty { parts.append((f, l.left + f.left, l.top + f.top)) }
                }
            }
            items.append(H4TownSceneItem(id: b, keyword: kw, layout: l, shadow: shadow, parts: parts))
        }
        return H4TownScene(background: bg, items: H4TownRender.zOrder(items), errors: errors)
    }

    /// The 1280x825 RGBA scene and its draw list (R3, R4, R7).
    public func render(faction: Int, background: String, built: [Int]) throws -> (image: H4RGBAImage, drawList: [H4TownDrawItem]) {
        try plan(faction: faction, background: background, built: built).render()
    }

    /// Hit-test (R5) of scene points.
    public func hitTest(faction: Int, background: String, built: [Int], points: [(x: Int, y: Int)]) throws -> [H4TownHit] {
        try plan(faction: faction, background: background, built: built).hitTest(points: points)
    }

    /// Thumbnail of a building in the build dialog (R6): the layer of `layers.town.<fac>.thumbnails` named like the keyword.
    public func thumbnail(faction: Int, building id: Int) throws -> H4TownThumbnail? {
        guard let kw = H4TownRender.keyword(faction: faction, building: id) else { return nil }
        let g = try group(H4TownRender.resourceName(faction: faction, group: "thumbnails"))
        return H4TownThumbnail(keyword: kw, layer: g.layer(named: kw))
    }
}

// MARK: - Canonical JSON (Python json.dump(sort_keys=True, indent=1, ensure_ascii=False) + newline)

enum H4PrettyJSON {
    case int(Int), null, str(String), arr([H4PrettyJSON]), obj([String: H4PrettyJSON])

    static func text(_ v: H4PrettyJSON) -> String {
        var out = ""
        v.write(&out, level: 0)
        return out + "\n"
    }

    private static func quote(_ s: String) -> String {
        var o = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": o += "\\\""
            case "\\": o += "\\\\"
            case "\n": o += "\\n"
            case "\r": o += "\\r"
            case "\t": o += "\\t"
            case "\u{8}": o += "\\b"
            case "\u{c}": o += "\\f"
            default:
                if u.value < 0x20 { o += String(format: "\\u%04x", u.value) } else { o.unicodeScalars.append(u) }
            }
        }
        return o + "\""
    }

    private func write(_ out: inout String, level: Int) {
        let pad = String(repeating: " ", count: level + 1), end = String(repeating: " ", count: level)
        switch self {
        case .int(let v): out += String(v)
        case .null: out += "null"
        case .str(let s): out += Self.quote(s)
        case .arr(let a):
            if a.isEmpty { out += "[]"; return }
            out += "[\n"
            for (k, e) in a.enumerated() {
                out += pad
                e.write(&out, level: level + 1)
                out += k + 1 < a.count ? ",\n" : "\n"
            }
            out += end + "]"
        case .obj(let o):
            if o.isEmpty { out += "{}"; return }
            let keys = o.keys.sorted { $0.unicodeScalars.map(\.value).lexicographicallyPrecedes($1.unicodeScalars.map(\.value)) }
            out += "{\n"
            for (k, key) in keys.enumerated() {
                out += pad + Self.quote(key) + ": "
                o[key]!.write(&out, level: level + 1)
                out += k + 1 < keys.count ? ",\n" : "\n"
            }
            out += end + "}"
        }
    }

    static func opt(_ v: Int?) -> H4PrettyJSON { v.map { .int($0) } ?? .null }
}

// MARK: - Batch outputs (h4tool town-*; same files as the reference commands)

/// A town of a started map with its terrain (record of `towns_terrain.json`).
public struct H4TownTerrainRecord: Sendable {
    public var map: String
    public var index: Int
    public var faction: Int
    public var x: Int, y: Int, level: Int
    public var model: String
    public var mask: Int
    public var terrain: H4TownTerrain
    public var background: String

    fileprivate var json: H4PrettyJSON {
        .obj(["map": .str(map), "index": .int(index), "faction": .int(faction), "x": .int(x), "y": .int(y), "level": .int(level),
              "model": .str(model), "mask": .int(mask), "terrain": .int(terrain.terrain), "bg": .str(background),
              "entrance": terrain.entrance.map { .arr([.int($0.i), .int($0.j)]) } ?? .null,
              "ref": .arr([.int(terrain.reference.x), .int(terrain.reference.y)]), "mode": .str(terrain.mode.rawValue), "t0": .int(terrain.t0)])
    }
}

public enum H4TownBatch {
    /// Terrain id of the 657 towns of the maps folder (R1a), maps in code-point order, towns in object order.
    public static func townTerrains(dataDirectory: URL, mapsDirectory: URL) throws -> [H4TownTerrainRecord] {
        let host = try H4MovementSession(dataDirectory: dataDirectory, mapsDirectory: mapsDirectory, seed: 12345, difficulty: 2)
        let townTables = try H4TownTables(store: host.store, tables: host.tables)
        var models: [String: H4AdventureObject] = [:]
        var out: [H4TownTerrainRecord] = []
        for name in host.mapNames {
            guard let files = host.mapFiles[name], files.count == 1 else {
                throw H4Error.malformed("map name '\(name)' matches \(host.mapFiles[name]?.count ?? 0) files")
            }
            let scenario = try H4Scenario(fileData: Data(contentsOf: URL(fileURLWithPath: files[0])))
            let game = try H4GameStart.start(scenario: scenario, store: host.store, tables: host.tables, seed: host.seed, difficulty: host.difficulty)
            let body = try H4ScenarioBody(scenario: scenario, resources: host.store)
            guard case .complete = body.stop else { throw H4Error.malformed("\(name): object list stopped at \(body.stop.offset)") }
            let world = try H4TownWorld(game: game, scenario: scenario, objects: body.objects, armies: [:], tables: townTables)
            let terrain = try H4ScenarioTerrain(scenario: scenario)
            for i in world.townOrder {
                let town = world.towns[i]!
                let o = body.objects[i]
                let model: H4AdventureObject
                let key = town.model.lowercased()
                if let m = models[key] { model = m } else {
                    model = try H4AdventureObject(data: host.store.data(for: "adv_object.\(town.model).h4d"))
                    models[key] = model
                }
                guard let eh = model.edgesHorizontal, let ev = model.edgesVertical else {
                    throw H4Error.malformed("model \(town.model) has no edge grids")
                }
                let level = Int(o.level)
                let rows = terrain.geometry.cellRows
                let inMap: (Int, Int) -> Bool = { x, y in (0..<terrain.levels).contains(level) && x >= 0 && x < rows.count && rows[x].contains(y) }
                let at: (Int, Int) -> Int = { x, y in Int(terrain.cells[level][x][y - rows[x].lowerBound].terrain) & 0x1f }
                let t = H4TownRender.terrain(x: Int(o.x), y: Int(o.y), width: model.width, height: model.height,
                                             edgesHorizontal: eh, edgesVertical: ev, inMap: inMap, terrainAt: at)
                guard let bg = H4TownRender.backgroundName(terrain: t.terrain) else {
                    throw H4Error.malformed("terrain id \(t.terrain) has no background")
                }
                out.append(H4TownTerrainRecord(map: name, index: i, faction: town.faction, x: Int(o.x), y: Int(o.y), level: level,
                                               model: town.model, mask: town.mask, terrain: t, background: bg))
            }
        }
        return out
    }

    public static func terrainAllJSON(dataDirectory: URL, mapsDirectory: URL) throws -> String {
        H4PrettyJSON.text(.arr(try townTerrains(dataDirectory: dataDirectory, mapsDirectory: mapsDirectory).map(\.json)))
    }

    /// `missing.json`: every town with its initial built set must have all its layers and thumbnails.
    public static func checkAllJSON(dataDirectory: URL, mapsDirectory: URL) throws -> (json: String, towns: Int, missing: Int, ignored: Int) {
        let store = try H4ResourceStore(dataDirectory: dataDirectory)
        let renderer = H4TownRenderer(store: store)
        let towns = try townTerrains(dataDirectory: dataDirectory, mapsDirectory: mapsDirectory)
        var missing: [H4PrettyJSON] = [], ignored: [H4PrettyJSON] = []
        for t in towns {
            let fac = H4TownRules.factions[t.faction]
            func rec(_ extra: [String: H4PrettyJSON]) -> H4PrettyJSON {
                .obj(["map": .str(t.map), "index": .int(t.index), "faction": .str(fac)].merging(extra) { a, _ in a })
            }
            let table = H4TownRules.keywords[t.faction]
            let all = H4TownRender.maskIDs(t.mask)
            for b in all where table[b] == nil { ignored.append(rec(["id": .int(b)])) }
            let ids = all.filter { table[$0] != nil }
            func resourceMissing(_ e: Error) -> H4PrettyJSON? {
                if case H4Error.notFound(let n) = e { return rec(["problem": .str("resource missing: '\(n)'")]) }
                return nil
            }
            do {
                let scene = try renderer.plan(faction: t.faction, background: t.background, built: ids)
                for e in scene.errors { missing.append(rec(["problem": .str(e)])) }
                if scene.background.layers.first?.name.lowercased() != "background" { missing.append(rec(["problem": .str("no background layer")])) }
            } catch {
                guard let m = resourceMissing(error) else { throw error }
                missing.append(m)
            }
            do {
                let thumbs = try renderer.group(H4TownRender.resourceName(faction: t.faction, group: "thumbnails"))
                for b in ids where thumbs.layer(named: table[b]!) == nil { missing.append(rec(["problem": .str("thumbnail missing"), "id": .int(b)])) }
            } catch {
                guard let m = resourceMissing(error) else { throw error }
                missing.append(m)
            }
        }
        let json = H4PrettyJSON.text(.obj(["towns_checked": .int(towns.count), "missing": .arr(missing), "ignored_bits_not_in_faction": .arr(ignored)]))
        return (json, towns.count, missing.count, ignored.count)
    }

    /// `thumbs.json`: thumbnail lookup of every building of every faction, with the SHA-256 of the layer's RGBA pixels.
    public static func thumbsAllJSON(dataDirectory: URL) throws -> String {
        let renderer = H4TownRenderer(store: try H4ResourceStore(dataDirectory: dataDirectory))
        var result: [String: H4PrettyJSON] = [:]
        for (f, fac) in H4TownRules.factions.enumerated() {
            var r: [String: H4PrettyJSON] = [:]
            for b in H4TownRules.keywords[f].keys.sorted() {
                guard let th = try renderer.thumbnail(faction: f, building: b) else { continue }
                guard let l = th.layer else { r[String(b)] = .obj(["keyword": .str(th.keyword), "layer": .null]); continue }
                let digest = SHA256.hash(data: Data(l.rgba().pixels)).map { String(format: "%02x", $0) }.joined()
                r[String(b)] = .obj(["keyword": .str(th.keyword), "layer": .str(l.name), "kind": .int(Int(l.kind)), "w": .int(max(l.width, 0)),
                                     "h": .int(max(l.height, 0)), "left": .int(l.left), "top": .int(l.top), "sha256": .str(digest)])
            }
            result[fac] = .obj(r)
        }
        return H4PrettyJSON.text(.obj(result))
    }

    /// Draw list as JSON (R7).
    public static func drawListJSON(_ list: [H4TownDrawItem]) -> String {
        H4PrettyJSON.text(.arr(list.map {
            .obj(["kind": .str($0.kind.rawValue), "id": H4PrettyJSON.opt($0.id), "layer": .str($0.layer), "x": .int($0.x), "y": .int($0.y)])
        }))
    }

    /// Hit-test answers as JSON (R5/R7).
    public static func hitsJSON(_ hits: [H4TownHit]) -> String {
        H4PrettyJSON.text(.arr(hits.map {
            .obj(["x": .int($0.x), "y": .int($0.y), "id": H4PrettyJSON.opt($0.id), "name": $0.name.map { .str($0) } ?? .null,
                  "stack": .arr($0.stack.map { .int($0) })])
        }))
    }
}
