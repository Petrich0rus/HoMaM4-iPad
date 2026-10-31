import Foundation

// Slice 7b — movement of a land hero on the adventure map (headless).
//
// Rules: docstring of the frozen reference `move_ref.py` (rules 1-9), reproduced here; tags [D] decoded from the exe,
// [I] inferred. Cell = (row x, column y) of a level. The 8 directions are numbered as the exe does, (dr, dc):
// 0 NE(-1,0) 1 E(-1,+1) 2 SE(0,+1) 3 S(+1,+1) 4 SW(+1,0) 5 W(+1,-1) 6 NW(0,-1) 7 N(-1,-1); odd directions are diagonal.
//
//  1. A cell is in the map iff rows[r].lowerBound <= c < rows[r].upperBound. Hard-blocked: water (terrain 0) or rock (b != 0),
//     except deck cells (rule 8). Objects of the started game add footprint cells (bit j*W+i of the model, anchor = minimum
//     corner) and ARMY cells (1 cell, fully blocked, never a destination). Resolved random objects replace their placeholder.
//  2. Entrances: only the boundary lines of the eh/ev grids count; a footprint-blocked cell is entered only by a step whose
//     crossed edge(s) are entrance edges (diagonal: either edge); it is TERMINAL (a path end, never expanded). The start
//     cell is expanded even when it is an army/object cell.
//  3. Step cost [D]: 75 on a deck cell; else 100 (75 if the destination road class is not 2) when both cells have a road
//     class != 0; else the terrain table (default 100). Odd directions: c + (c >> 1).
//  4. Movement points: full allowance 2256 [I].
//  5. Dijkstra, 8 neighbours in exe order, heap order (cost, push counter), push only on a strictly smaller cost.
//  6. Day split: rest if points <= 0; a step with c >= remaining ends the day (overflow not carried).
//  7. Corner cutting allowed. 8. Bridges/ferries: footprint cells with bit 1 are decks (passable over water, cost 75).
//  9. Output: reachable, cost, days, path, day_of, and `why` when unreachable.

/// A cell of a level: row (x), column (y).
public struct H4MoveCell: Sendable, Equatable, Hashable {
    public var r: Int, c: Int
    public init(_ r: Int, _ c: Int) { self.r = r; self.c = c }
}

/// Footprint and entrance grids of an `adv_object` model (movement-relevant part only).
public struct H4MoveFootprint: Sendable, Equatable {
    public let width: Int, height: Int
    /// Row-major `j * width + i`.
    public let blocked: [Bool]
    /// `(height + 1) * width` bits, index `j * width + i`; nil without edge grids.
    public let edgesHorizontal: [Bool]?
    /// `(width + 1) * height` bits, index `i * height + j`.
    public let edgesVertical: [Bool]?

    public init(width: Int, height: Int, blocked: [Bool], edgesHorizontal: [Bool]? = nil, edgesVertical: [Bool]? = nil) {
        self.width = width; self.height = height; self.blocked = blocked
        self.edgesHorizontal = edgesHorizontal; self.edgesVertical = edgesVertical
    }

    public init(_ object: H4AdventureObject) {
        self.init(width: object.width, height: object.height, blocked: object.blockedCells,
                  edgesHorizontal: object.edgesHorizontal, edgesVertical: object.edgesVertical)
    }
}

/// An object (or army) placed on a level. `footprint == nil` is an army: one blocking cell at (x, y).
public struct H4MovePlaced: Sendable {
    public let className: String
    public let x: Int, y: Int, width: Int, height: Int
    public let footprint: H4MoveFootprint?

    public init(className: String, x: Int, y: Int, footprint: H4MoveFootprint) {
        self.className = className; self.x = x; self.y = y
        width = footprint.width; height = footprint.height; self.footprint = footprint
    }

    public init(armyAt x: Int, _ y: Int) {
        className = "army"; self.x = x; self.y = y; width = 1; height = 1; footprint = nil
    }

    /// Boundary entrance edges as (inside cell, outside cell), in the order of the reference `entry_cells`.
    public var entryCells: [(inside: H4MoveCell, outside: H4MoveCell)] {
        guard let g = footprint, let eh = g.edgesHorizontal, let ev = g.edgesVertical, className != "bridge", className != "ferry"
        else { return [] }
        let W = width, H = height
        var out: [(H4MoveCell, H4MoveCell)] = []
        for jj in 0..<H {
            if ev[jj] { out.append((H4MoveCell(x, y + jj), H4MoveCell(x - 1, y + jj))) }
            if ev[W * H + jj] { out.append((H4MoveCell(x + W - 1, y + jj), H4MoveCell(x + W, y + jj))) }
        }
        for ii in 0..<W {
            if eh[ii] { out.append((H4MoveCell(x + ii, y), H4MoveCell(x + ii, y - 1))) }
            if eh[H * W + ii] { out.append((H4MoveCell(x + ii, y + H - 1), H4MoveCell(x + ii, y + H))) }
        }
        return out
    }
}

public enum H4MoveWhy: String, Sendable {
    case startInvalid = "start-invalid", goalOutOfMap = "goal-oob", goalArmy = "goal-army"
    case goalBlocked = "goal-blocked", noPath = "no-path"
}

public struct H4MoveAnswer: Sendable, Equatable {
    public var reachable: Bool
    public var cost: Int
    public var days: Int
    public var path: [H4MoveCell]
    public var dayOf: [Int]
    public var why: H4MoveWhy?

    /// Canonical JSON (sorted keys, compact separators), as the reference `canon`.
    public var canonicalJSON: String {
        var s = "{\"cost\":\(cost),\"day_of\":["
        s += dayOf.map(String.init).joined(separator: ",")
        s += "],\"days\":\(days),\"path\":["
        s += path.map { "[\($0.r),\($0.c)]" }.joined(separator: ",")
        s += "],\"reachable\":\(reachable ? "true" : "false")"
        if let why { s += ",\"why\":\"\(why.rawValue)\"" }
        return s + "}"
    }
}

/// Result of a Dijkstra search (flat padded indices of the world).
public struct H4MoveTree: Sendable {
    let src: Int
    let dist: [Int32]
    let parent: [Int32]
}

/// Passability grid of one level and the movement search.
public final class H4MoveWorld {
    public static let fullPoints = 2256
    static let unreached = Int32.max
    static let up: UInt8 = 1, down: UInt8 = 2, left: UInt8 = 4, right: UInt8 = 8
    static let dirs: [(dr: Int, dc: Int)] = [(-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1)]
    static let terrainCosts: [Int32] = {
        var t = [Int32](repeating: 100, count: 32)
        for (k, v) in [2: 125, 3: 200, 4: 125, 5: 175, 6: 150, 9: 150, 11: 150, 15: 125, 16: 125, 18: 125] { t[k] = Int32(v) }
        return t
    }()

    public let size: Int
    public let rows: [Range<Int>]
    let stride: Int
    let total: Int
    var valid: [UInt8], terrain: [UInt8], road: [UInt8], rock: [UInt8]
    var footprint: [UInt8], entrance: [UInt8], army: [UInt8], deck: [UInt8]
    /// 0 closed, 1 free, 2 object entry cell (footprint-blocked, enterable through an entrance edge).
    var kind: [UInt8]
    let offsets: [Int]
    let sides: [UInt8]

    /// `cell(r, c)` gives (terrain, road class a, rock b) of a cell inside the map.
    public init(size: Int, rows: [Range<Int>], cell: (Int, Int) -> (terrain: UInt8, road: UInt8, rock: UInt8),
                placed: [H4MovePlaced]) {
        self.size = size
        self.rows = rows
        let s = rows.map(\.upperBound).max() ?? 0
        stride = s + 2
        total = (size + 2) * stride
        offsets = Self.dirs.map { $0.dr * (s + 2) + $0.dc }
        sides = Self.dirs.map { d in
            (d.dr == 1 ? Self.up : d.dr == -1 ? Self.down : 0) | (d.dc == 1 ? Self.left : d.dc == -1 ? Self.right : 0)
        }
        valid = [UInt8](repeating: 0, count: total); terrain = valid; road = valid; rock = valid
        footprint = valid; entrance = valid; army = valid; deck = valid; kind = valid
        for r in 0..<size {
            for c in rows[r] {
                let k = (r + 1) * stride + c + 1
                let t = cell(r, c)
                valid[k] = 1; terrain[k] = t.terrain; road[k] = t.road; rock[k] = t.rock
            }
        }
        for o in placed {
            guard let g = o.footprint else {
                if inMap(o.x, o.y) { army[index(o.x, o.y)] = 1 }
                continue
            }
            let isDeck = o.className == "bridge" || o.className == "ferry"
            let W = g.width, H = g.height
            for i in 0..<W {
                for j in 0..<H where g.blocked[j * W + i] && inMap(o.x + i, o.y + j) {
                    let k = index(o.x + i, o.y + j)
                    if isDeck { deck[k] = 1 } else { footprint[k] = 1 }
                }
            }
            if isDeck { continue }
            for e in o.entryCells {
                // entry cells are listed with their outside neighbour; the side of the INSIDE cell is the direction to it
                let side: UInt8 = e.outside.r < e.inside.r ? Self.up : e.outside.r > e.inside.r ? Self.down
                    : e.outside.c < e.inside.c ? Self.left : Self.right
                if inMap(e.inside.r, e.inside.c), footprint[index(e.inside.r, e.inside.c)] != 0 {
                    entrance[index(e.inside.r, e.inside.c)] |= side
                }
            }
        }
        for k in 0..<total {
            if valid[k] == 0 || army[k] != 0 { continue }
            if rock[k] != 0 || (terrain[k] == 0 && deck[k] == 0) { continue }
            if footprint[k] != 0 {
                if entrance[k] != 0 { kind[k] = 2 }
                continue
            }
            kind[k] = 1
        }
    }

    /// World of one level of a terrain.
    public convenience init(terrain t: H4ScenarioTerrain, level: Int, placed: [H4MovePlaced]) {
        self.init(size: t.geometry.size, rows: t.geometry.cellRows, cell: { r, c in
            let cl = t.cells[level][r][c - t.geometry.cellRows[r].lowerBound]
            return (cl.terrain, cl.a, cl.b)
        }, placed: placed)
    }

    public func inMap(_ r: Int, _ c: Int) -> Bool { r >= 0 && r < size && rows[r].contains(c) }
    func index(_ r: Int, _ c: Int) -> Int { (r + 1) * stride + c + 1 }
    func cell(_ k: Int) -> H4MoveCell { H4MoveCell(k / stride - 1, k % stride - 1) }

    /// A free cell (not water/rock/object/army).
    public func isPassable(_ r: Int, _ c: Int) -> Bool { inMap(r, c) && kind[index(r, c)] == 1 }

    /// Every free cell of the level, in row-major order.
    public var freeCells: [H4MoveCell] {
        var out: [H4MoveCell] = []
        for r in 0..<size { for c in rows[r] where kind[index(r, c)] == 1 { out.append(H4MoveCell(r, c)) } }
        return out
    }

    /// A start is valid iff inside the map and not hard-blocked (an army/object cell is fine).
    public func isValidStart(_ s: H4MoveCell) -> Bool {
        guard inMap(s.r, s.c) else { return false }
        let k = index(s.r, s.c)
        return rock[k] == 0 && (terrain[k] != 0 || deck[k] == 1)
    }

    // MARK: Search (rule 5)

    struct HeapEntry { var key: UInt64; var cell: Int32 }

    /// Dijkstra from `src` (flat index); stops when `goal` is popped.
    func search(src: Int, goal: Int?) -> H4MoveTree {
        var dist = [Int32](repeating: Self.unreached, count: total)
        var parent = [Int32](repeating: -1, count: total)
        var heap: [HeapEntry] = []
        heap.reserveCapacity(1024)
        func push(_ e: HeapEntry) {
            heap.append(e)
            var i = heap.count - 1
            while i > 0 {
                let p = (i - 1) >> 1
                if heap[p].key <= e.key { break }
                heap[i] = heap[p]
                i = p
            }
            heap[i] = e
        }
        func pop() -> HeapEntry {
            let top = heap[0]
            let last = heap.removeLast()
            if !heap.isEmpty {
                var i = 0
                let n = heap.count
                while true {
                    var ch = 2 * i + 1
                    if ch >= n { break }
                    if ch + 1 < n && heap[ch + 1].key < heap[ch].key { ch += 1 }
                    if heap[ch].key >= last.key { break }
                    heap[i] = heap[ch]
                    i = ch
                }
                heap[i] = last
            }
            return top
        }
        dist[src] = 0
        push(HeapEntry(key: 0, cell: Int32(src)))
        var counter: UInt64 = 1
        let goalIndex = goal ?? -1
        let offsets = self.offsets, sides = self.sides, tcost = Self.terrainCosts
        kind.withUnsafeBufferPointer { kind in
        road.withUnsafeBufferPointer { road in
        terrain.withUnsafeBufferPointer { terrain in
        deck.withUnsafeBufferPointer { deck in
        entrance.withUnsafeBufferPointer { ent in
        dist.withUnsafeMutableBufferPointer { dist in
        parent.withUnsafeMutableBufferPointer { parent in
            while !heap.isEmpty {
                let e = pop()
                let d = Int32(truncatingIfNeeded: e.key >> 32)
                let u = Int(e.cell)
                if d > dist[u] { continue }
                if u == goalIndex { break }
                if kind[u] == 2 && u != src { continue }     // terminal object cell
                let ru = road[u]
                for k in 0..<8 {
                    let v = u + offsets[k]
                    let kv = kind[v]
                    if kv == 0 { continue }
                    if kv == 2 && ent[v] & sides[k] == 0 { continue }
                    var c: Int32
                    if deck[v] != 0 {
                        c = 75
                    } else if ru != 0 && road[v] != 0 {
                        c = road[v] == 2 ? 100 : 75
                    } else {
                        c = tcost[Int(terrain[v])]
                    }
                    if k & 1 != 0 { c += c >> 1 }
                    let nd = d + c
                    if nd < dist[v] {
                        dist[v] = nd
                        parent[v] = Int32(u)
                        push(HeapEntry(key: UInt64(nd) << 32 | counter, cell: Int32(v)))
                        counter += 1
                    }
                }
            }
        }}}}}}}
        return H4MoveTree(src: src, dist: dist, parent: parent)
    }

    /// Full search tree from a valid start, to answer several goals.
    public func tree(from start: H4MoveCell) -> H4MoveTree? {
        isValidStart(start) ? search(src: index(start.r, start.c), goal: nil) : nil
    }

    // MARK: Day split (rule 6)

    public static func daySplit(costs: [Int], points: Int, full: Int) -> (dayOf: [Int], days: Int) {
        var day = 0, rem = points
        if rem <= 0 { day = 1; rem = full }
        var out: [Int] = []
        out.reserveCapacity(costs.count)
        for c in costs {
            out.append(day)
            if c < rem { rem -= c } else { day += 1; rem = full }
        }
        return (out, out.last.map { $0 + 1 } ?? 0)
    }

    // MARK: Query (rule 9)

    /// Answer for a hero at `start` with `points` left today and `full` points on the following days. `tree` is an optional
    /// precomputed full search from `start`; without it a single-goal search stops when the goal is popped.
    public func query(from start: H4MoveCell, to goal: H4MoveCell, points: Int = H4MoveWorld.fullPoints,
                      full: Int = H4MoveWorld.fullPoints, tree: H4MoveTree? = nil) -> H4MoveAnswer {
        func bad(_ why: H4MoveWhy) -> H4MoveAnswer {
            H4MoveAnswer(reachable: false, cost: -1, days: -1, path: [], dayOf: [], why: why)
        }
        guard isValidStart(start) else { return bad(.startInvalid) }
        guard inMap(goal.r, goal.c) else { return bad(.goalOutOfMap) }
        let s = index(start.r, start.c), g = index(goal.r, goal.c)
        let t = tree ?? search(src: s, goal: g)
        guard t.dist[g] != Self.unreached else {
            return bad(army[g] != 0 ? .goalArmy : kind[g] == 0 || kind[g] == 2 ? .goalBlocked : .noPath)
        }
        var cells = [g]
        while cells[cells.count - 1] != s { cells.append(Int(t.parent[cells[cells.count - 1]])) }
        cells.reverse()
        var costs: [Int] = []
        costs.reserveCapacity(cells.count)
        for i in 1..<max(cells.count, 1) { costs.append(Int(t.dist[cells[i]] - t.dist[cells[i - 1]])) }
        let (dayOf, days) = Self.daySplit(costs: costs, points: points, full: full)
        return H4MoveAnswer(reachable: true, cost: Int(t.dist[g]), days: days, path: cells.map(cell), dayOf: dayOf, why: nil)
    }
}

// MARK: - Models

/// Footprints of `adv_object` models, loaded on demand from the resource store (case-insensitive names).
public final class H4MoveModels {
    private let store: H4ResourceStore
    private var cache: [String: H4MoveFootprint?] = [:]

    public init(store: H4ResourceStore) { self.store = store }

    /// nil when the model has no resource.
    public func footprint(_ model: String) throws -> H4MoveFootprint? {
        let key = model.lowercased()
        if let hit = cache[key] { return hit }
        let value: H4MoveFootprint?
        do {
            value = H4MoveFootprint(try H4AdventureObject(data: store.data(for: "adv_object.\(model).h4d")))
        } catch H4Error.notFound(_) {
            value = nil
        }
        cache[key] = .some(value)
        return value
    }
}

// MARK: - A started map

/// The movement worlds of one scenario of a started game (objects of `H4Game`, terrain of the scenario).
public final class H4MovementMap {
    public let name: String
    public let levels: Int
    private let terrain: H4ScenarioTerrain
    private let objects: [H4ScenarioObject]
    private let resolved: [Int: H4ResolvedObject]
    private let models: H4MoveModels
    private var worlds: [Int: H4MoveWorld] = [:]

    public init(name: String, scenario: H4Scenario, store: H4ResourceStore, game: H4Game, models: H4MoveModels) throws {
        let body = try H4ScenarioBody(scenario: scenario, resources: store)
        guard case .complete = body.stop else { throw H4Error.malformed("object list stopped at \(body.stop.offset)") }
        self.name = name
        terrain = try H4ScenarioTerrain(scenario: scenario)
        levels = scenario.levels
        objects = body.objects
        resolved = Dictionary(game.objects.map { ($0.index, $0.resolved) }, uniquingKeysWith: { a, _ in a })
        self.models = models
    }

    /// Placed objects of a level in object-list order, with the placeholders of the started game replaced (rule 1b).
    public func placedObjects(level: Int) throws -> [H4MovePlaced] {
        var out: [H4MovePlaced] = []
        for (i, o) in objects.enumerated() where Int(o.level) == level {
            let x = Int(o.x), y = Int(o.y)
            let cls = o.className
            if cls == "army" { out.append(H4MovePlaced(armyAt: x, y)); continue }
            var model = o.modelName
            if let r = resolved[i] {
                model = r.model ?? ""
                if model.isEmpty { continue }
                if model.hasPrefix("adv_actor.") { out.append(H4MovePlaced(armyAt: x, y)); continue }
            }
            if model.isEmpty { continue }
            guard let fp = try models.footprint(model) else { continue }
            out.append(H4MovePlaced(className: cls, x: x, y: y, footprint: fp))
        }
        return out
    }

    public func world(level: Int) throws -> H4MoveWorld {
        if let w = worlds[level] { return w }
        guard (0..<levels).contains(level) else { throw H4Error.malformed("level \(level) outside 0..<\(levels)") }
        let w = H4MoveWorld(terrain: terrain, level: level, placed: try placedObjects(level: level))
        worlds[level] = w
        return w
    }
}

// MARK: - Batch driver (h4tool moves / towns)

/// Loads scenarios of a maps folder by name and answers the oracle queries.
public final class H4MovementSession {
    public let store: H4ResourceStore
    public let tables: H4GameTables
    public let seed: UInt32
    public let difficulty: Int
    public let mapFiles: [String: [String]]
    private let models: H4MoveModels
    private var maps: [String: H4MovementMap] = [:]

    /// The map name of a file: stem without extension and folder, " " replaced by "_" (reference name rule).
    public static func mapName(ofFile path: String) -> String {
        let file = (path as NSString).lastPathComponent
        let stem = file.lowercased().hasSuffix(".h4c") ? String(file.dropLast(4)) : file
        return stem.replacingOccurrences(of: " ", with: "_")
    }

    /// Code-point order, as Python's string sort.
    static func lessCodePoints(_ a: String, _ b: String) -> Bool {
        a.unicodeScalars.map(\.value).lexicographicallyPrecedes(b.unicodeScalars.map(\.value))
    }

    public init(dataDirectory: URL, mapsDirectory: URL, seed: UInt32 = 12345, difficulty: Int = 2) throws {
        store = try H4ResourceStore(dataDirectory: dataDirectory)
        tables = try H4GameTables(store: store)
        self.seed = seed
        self.difficulty = difficulty
        models = H4MoveModels(store: store)
        var files: [String: [String]] = [:]
        let found = FileManager.default.enumerator(atPath: mapsDirectory.path)?.compactMap { $0 as? String }
            .filter { $0.lowercased().hasSuffix(".h4c") } ?? []
        for rel in found { files[Self.mapName(ofFile: rel), default: []].append(mapsDirectory.appendingPathComponent(rel).path) }
        mapFiles = files
    }

    /// All map names, in code-point order.
    public var mapNames: [String] { mapFiles.keys.sorted(by: Self.lessCodePoints) }

    /// The started map of that name; a name matching 0 or 2+ files is an error.
    public func map(named name: String) throws -> H4MovementMap {
        if let m = maps[name] { return m }
        guard let paths = mapFiles[name], paths.count == 1 else {
            throw H4Error.malformed("map name '\(name)' matches \(mapFiles[name]?.count ?? 0) files")
        }
        let scenario = try H4Scenario(fileData: Data(contentsOf: URL(fileURLWithPath: paths[0])))
        let game = try H4GameStart.start(scenario: scenario, store: store, tables: tables, seed: seed, difficulty: difficulty)
        let m = try H4MovementMap(name: name, scenario: scenario, store: store, game: game, models: models)
        maps[name] = m
        return m
    }

    /// Drops a started map (the towns command visits 105 maps).
    public func release(_ name: String) { maps[name] = nil }

    /// Answers of a query list (JSON array of {map, level, from, to, points?, full?}) as canonical JSON.
    public func answersJSON(queries data: Data) throws -> String {
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw H4Error.malformed("queries are not a JSON array of objects")
        }
        struct Query { var map: String; var level: Int; var from: H4MoveCell; var to: H4MoveCell; var points: Int?; var full: Int }
        func cellOf(_ v: Any?) throws -> H4MoveCell {
            guard let a = v as? [Int], a.count == 2 else { throw H4Error.malformed("query cell is not [r, c]") }
            return H4MoveCell(a[0], a[1])
        }
        let queries: [Query] = try list.map { q in
            guard let map = q["map"] as? String, let level = q["level"] as? Int else { throw H4Error.malformed("query without map/level") }
            return Query(map: map, level: level, from: try cellOf(q["from"]), to: try cellOf(q["to"]),
                         points: q["points"] as? Int, full: q["full"] as? Int ?? H4MoveWorld.fullPoints)
        }
        struct Group: Hashable { var map: String; var level: Int; var from: H4MoveCell }
        var groups: [Group: [Int]] = [:]
        for (i, q) in queries.enumerated() { groups[Group(map: q.map, level: q.level, from: q.from), default: []].append(i) }
        var out = [String](repeating: "", count: queries.count)
        for (g, ids) in groups {
            let w = try map(named: g.map).world(level: g.level)
            let tree = w.tree(from: g.from)
            for i in ids {
                let q = queries[i]
                out[i] = w.query(from: q.from, to: q.to, points: q.points ?? q.full, full: q.full, tree: tree).canonicalJSON
            }
        }
        return "[" + out.joined(separator: ",") + "]"
    }

    /// Canonical JSON string literal with ASCII escapes (Python `json.dumps` default).
    static func jsonString(_ s: String) -> String {
        var o = "\""
        for u in s.utf16 {
            switch u {
            case 0x22: o += "\\\""
            case 0x5C: o += "\\\\"
            case 0x0A: o += "\\n"
            case 0x0D: o += "\\r"
            case 0x09: o += "\\t"
            case 0x08: o += "\\b"
            case 0x0C: o += "\\f"
            case 0x20..<0x7F: o += String(UnicodeScalar(UInt8(u)))
            default: o += String(format: "\\u%04x", u)
            }
        }
        return o + "\""
    }

    /// One record per town / random town: first free outside entrance cell and reachability of the town cell from it.
    public func townsJSON() throws -> String {
        var records: [String] = []
        for name in mapNames {
            let m = try map(named: name)
            for level in 0..<m.levels {
                let w = try m.world(level: level)
                for o in try m.placedObjects(level: level) where o.className == "town" || o.className == "random_town" {
                    let object = "[\(Self.jsonString(o.className)),\(o.x),\(o.y),\(o.width)]"
                    var rec = "{"
                    if let e = o.entryCells.first(where: { w.isPassable($0.outside.r, $0.outside.c) }) {
                        let reachable = w.query(from: e.outside, to: e.inside).reachable
                        rec += "\"entrance\":[\(e.outside.r),\(e.outside.c)],\"level\":\(level),\"map\":\(Self.jsonString(name)),"
                        rec += "\"object\":\(object),\"reachable\":\(reachable),\"town_cell\":[\(e.inside.r),\(e.inside.c)]}"
                    } else {
                        rec += "\"entrance\":null,\"level\":\(level),\"map\":\(Self.jsonString(name)),\"object\":\(object),\"reachable\":false}"
                    }
                    records.append(rec)
                }
            }
            release(name)
        }
        return "[" + records.joined(separator: ",") + "]"
    }
}
