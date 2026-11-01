import Foundation

// Slice 7c: objects, armies and owner flags of a STARTED game (rules T, O1–O5, G0–G9 of the frozen reference
// `render_game_ref.py`). The step-1 object rules (`H4MapObjectRender`) are reused for object items; this file adds the
// started-game item list, army sprites (adv_actor → actor_sequence) and owner flags (animation.Flags.*).

/// `adv_actor.<name>` resource: per action and direction (file order ne, e, se, s, sw, w, nw, n) the name of an
/// `actor_sequence`, then four i32 (x0, y0, x1, y1); the first pair is the flag attach point of the actor [I].
struct H4AdvActor {
    struct Action { var name: String; var speed: UInt8; var sequences: [String] }
    var actions: [Action]
    var tail: (x0: Int, y0: Int, x1: Int, y1: Int)

    init(data: Data) throws {
        var r = ByteReader(data)
        _ = try r.u16()                                   // version 3
        _ = try r.u8(); _ = try r.u16(); _ = try r.u16(); _ = try r.u16()
        let n = Int(try r.u16())
        var acts: [Action] = []
        for _ in 0..<n {
            let name = try r.string16(), speed = try r.u8()
            acts.append(Action(name: name, speed: speed, sequences: try (0..<8).map { _ in try r.string16() }))
        }
        actions = acts
        tail = (Int(try r.i32()), Int(try r.i32()), Int(try r.i32()), Int(try r.i32()))
        guard r.remaining == 0 else { throw H4Error.malformed("\(r.remaining) trailing bytes after adv_actor") }
    }
}

public final class H4GameRender: @unchecked Sendable {
    /// G0: editor-only classes never drawn in a started game.
    static let hiddenClasses: Set<String> = ["deletion_marker", "event_trigger", "obelisk_marker"]
    static let factions = ["life", "order", "death", "chaos", "nature", "might"]
    static let colours = ["Red", "Blue", "Green", "Orange", "Purple", "Teal"]
    /// Hero classes of the "magic" kind (table 0x989a54).
    static let magicClasses: Set<Int> = Set([1, 3, 5, 7, 9] + Array(13...21) + Array(26...29) + Array(31...35) + [40, 47])
    /// G4: the army sprite uses the action `wait` in the direction `se` (file index 2).
    static let waitDirection = 2

    /// One slot of an army reduced to what the sprite name depends on.
    enum ActorSlot: Equatable {
        case empty
        case creature(Int)
        case hero(heroClass: Int, gender: Int)
    }

    /// G3: name of the `adv_actor` of an army (without the `adv_actor.` prefix), nil when nothing is drawn.
    /// `boat` is the record's ship type (-1 none); `level` the creature level; `keyword` the creature keyword;
    /// `heroExists(name)` tells whether `adv_actor.<name>` exists (used for the might fallback of a hero).
    static func actorName(boat: Int, slots: [ActorSlot], level: (Int) -> Int, keyword: (Int) -> String,
                          heroExists: (String) -> Bool) -> String? {
        if (0...5).contains(boat) { return "ships." + factions[boat] }     // any other ship type: not a boat
        for s in slots {
            guard case let .hero(c, gender) = s else { continue }
            if c == -1 { return "hero.chaos_magic_female" }
            guard (0..<factions.count * 8).contains(c) else { return nil }  // in-memory data: class outside 0..47 is not drawn
            let f = factions[c / 8], sex = gender == 1 ? "male" : "female"
            var kind = magicClasses.contains(c) ? "magic" : "might"
            if !heroExists("hero.\(f)_\(kind)_\(sex)") { kind = "might" }
            return "hero.\(f)_\(kind)_\(sex)"
        }
        var best: Int?
        for (i, s) in slots.enumerated() {
            guard case let .creature(c) = s else { continue }
            if let b = best, case let .creature(bc) = slots[b], level(c) <= level(bc) { continue }
            best = i
        }
        if let best, case let .creature(c) = slots[best] { return keyword(c) }
        return nil
    }

    /// G6: flag colour of an owner (0…5), "Gray" for anything else.
    static func flagColour(owner: Int?) -> String {
        if let o = owner, (0...5).contains(o) { return colours[o] }
        return "Gray"
    }

    /// G7 sort key: Python tuple order (lexicographic, a shorter prefix sorts first).
    struct SortKey: Comparable {
        var v: (Double, Double, Double, Double, Double)
        var n: Int
        init(_ a: Double, _ b: Double, _ c: Double) { v = (a, b, c, 0, 0); n = 3 }
        init(_ a: Double, _ b: Double, _ c: Double, _ d: Double) { v = (a, b, c, d, 0); n = 4 }
        init(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ e: Double) { v = (a, b, c, d, e); n = 5 }
        static func == (l: SortKey, r: SortKey) -> Bool { l.n == r.n && l.v == r.v }
        func at(_ i: Int) -> Double {
            switch i { case 0: return v.0; case 1: return v.1; case 2: return v.2; case 3: return v.3; default: return v.4 }
        }
        static func < (l: SortKey, r: SortKey) -> Bool {
            for i in 0..<min(l.n, r.n) { let a = l.at(i), b = r.at(i); if a != b { return a < b } }
            return l.n < r.n
        }
    }

    private struct Flag { var hx: Int, hy: Int, left: Int, top: Int, pixels: H4ObjectLayerPixels }

    private let loader: @Sendable (String) throws -> Data
    private let exists: @Sendable (String) -> Bool
    private let tables: H4GameTables
    private let models: H4ObjectModelLibrary
    private let lock = NSLock()
    private var actors: [String: H4AdvActor?] = [:]
    private var sequences: [String: H4ObjectModel?] = [:]
    private var flags: [String: Flag?] = [:]
    private var missingActorsStore: Set<String> = [], missingSequencesStore: Set<String> = [], missingFlagsStore: Set<String> = []
    public var missingActors: Set<String> { lock.lock(); defer { lock.unlock() }; return missingActorsStore }
    public var missingSequences: Set<String> { lock.lock(); defer { lock.unlock() }; return missingSequencesStore }
    public var missingFlags: Set<String> { lock.lock(); defer { lock.unlock() }; return missingFlagsStore }

    /// `models` is shared with the caller so missing adv_object models are counted in one place.
    public convenience init(store: H4ResourceStore, tables: H4GameTables, models: H4ObjectModelLibrary) {
        self.init(tables: tables, models: models, loader: { try store.data(for: $0) }, exists: { store.locate($0) != nil })
    }

    /// `loader` returns the bytes of a resource (throwing `H4Error.notFound` if there is none), `exists` tells whether a
    /// resource name is present.
    public init(tables: H4GameTables, models: H4ObjectModelLibrary, loader: @escaping @Sendable (String) throws -> Data,
                exists: @escaping @Sendable (String) -> Bool) {
        self.tables = tables; self.models = models; self.loader = loader; self.exists = exists
    }

    // MARK: resources (case-insensitive lookups through the store)

    private func actor(_ name: String) throws -> H4AdvActor? {
        let key = name.lowercased()
        lock.lock(); defer { lock.unlock() }
        if let hit = actors[key] { return hit }
        var made: H4AdvActor?
        do { made = try H4AdvActor(data: loader("adv_actor.\(name).h4d")) }
        catch H4Error.notFound { missingActorsStore.insert(name) }
        actors[key] = .some(made)
        return made
    }

    private func sequenceModel(_ sequence: String, spriteName: String) throws -> H4ObjectModel? {
        let key = sequence.lowercased()
        lock.lock(); defer { lock.unlock() }
        if let hit = sequences[key] { return hit }
        var made: H4ObjectModel?
        do { made = H4ObjectModel(name: spriteName, sequence: try H4ActorSequence(data: loader("actor_sequence.\(sequence).h4d"))) }
        catch H4Error.notFound { missingSequencesStore.insert(sequence) }
        sequences[key] = .some(made)
        return made
    }

    private func flag(_ colour: String) throws -> Flag? {
        lock.lock(); defer { lock.unlock() }
        if let hit = flags[colour] { return hit }
        var made: Flag?
        do {
            let a = try H4Animation(data: loader("animation.Flags.\(colour).h4d"))
            if let l = a.frames.layers.first {
                made = Flag(hx: Int(a.extra?.x ?? 0), hy: Int(a.extra?.y ?? 0), left: l.left, top: l.top, pixels: H4ObjectLayerPixels(l))
            } else { missingFlagsStore.insert(colour) }
        } catch H4Error.notFound { missingFlagsStore.insert(colour) }
        flags[colour] = .some(made)
        return made
    }

    private func heroExists(_ name: String) -> Bool { exists("adv_actor.\(name).h4d") }

    /// Owner of a scenario object as the game start sees it (0…6) or nil when the class has none (same cases as
    /// `H4GameStartInput`).
    static func owner(of o: H4ScenarioObject) -> Int? {
        switch o.payload {
        case .ownedScriptable(let v): return Int(v.owner)
        case .randomDwelling(let v): return Int(v.owner)
        case .garrison(let v): return Int(v.owner)
        case .outpost(_, let ow): return ow.map(Int.init)
        case .carryoverHero(let v): return v.owner.map(Int.init)
        case .town(let v): return Int(v.town.owner)
        case .randomTown(let v): return Int(v.town.owner)
        case .army(let v): return Int(v.owner)
        default: return nil
        }
    }

    // MARK: draw list

    private struct Placed {
        var isArmy: Bool
        /// Path arrow of a session plan: strips keyed like an army, counted in neither objects nor armies.
        var isArrow = false
        var x: Int, y: Int
        var name: String
        var model: H4ObjectModel
        var ax: Int, ay: Int
        var flagPoint: (dx: Int, dy: Int)?
        var colour: String?
    }

    private struct Strip { var key: SortKey; var order: Int; var item: H4ObjectDrawItem }

    /// The draw list (G1–G9) of `level` in `region` for the objects (file order) of a started game.
    ///
    /// `state` (slice 7d-L) is the state of a play session: armies are drawn at their current cells (same position in the
    /// list), picked-up objects are absent, and the arrows of the active plan are appended after the other items.
    /// Without `state`, or with an unmodified session, the list is the 7c list.
    public func drawList(objects: [H4ScenarioObject], game: H4Game, level: Int,
                         region: H4MapTerrainRender.Region, state: H4SessionRenderState? = nil) throws -> H4ObjectDrawList {
        let creatureCount = tables.creatures.count
        let resolved = Dictionary(game.objects.map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })
        let W = region.canvasWidth, H = region.canvasHeight
        var placed: [Placed] = []

        func addObject(_ o: H4ScenarioObject, name: String, owner: Int?, ax: Int, ay: Int) throws {
            guard !name.isEmpty, let m = try models.model(named: name) else { return }
            let (x, y) = (Int(o.x), Int(o.y))
            guard H4MapObjectRender.isIncluded(x: x, y: y, width: m.width, height: m.height, region: region) else { return }
            placed.append(Placed(isArmy: false, x: x, y: y, name: name, model: m, ax: ax, ay: ay, flagPoint: m.flagPoint,
                                 colour: m.flagPoint == nil ? nil : Self.flagColour(owner: owner)))
        }
        func addArmy(x ox: Int, y oy: Int, actorName: String, owner: Int, ax: Int, ay: Int) throws {
            guard let adv = try actor(actorName) else { return }
            guard let wait = adv.actions.first(where: { $0.name == "wait" }) else {
                lock.lock(); missingSequencesStore.insert("adv_actor.\(actorName) wait"); lock.unlock()
                return
            }
            guard let m = try sequenceModel(wait.sequences[Self.waitDirection], spriteName: "adv_actor." + actorName) else { return }
            var colour: String?
            var xs: [Int] = [], xe: [Int] = [], ys: [Int] = [], ye: [Int] = []
            for k in m.shadowLayers + m.bodyLayers {
                let l = m.layers[k]
                xs.append(ax + m.originX + l.left); xe.append(ax + m.originX + l.left + (l.right - l.left))
                ys.append(ay + m.originY + l.top); ye.append(ay + m.originY + l.bottom)
            }
            if (0...5).contains(owner) {
                let c = Self.colours[owner]
                guard let f = try flag(c) else { return }
                let fx = ax + adv.tail.x0 - f.hx + f.left, fy = ay + adv.tail.y0 - f.hy + f.top
                xs.append(fx); xe.append(fx + f.pixels.width); ys.append(fy); ye.append(fy + f.pixels.height)
                colour = c
            }
            guard let x0 = xs.min(), let x1 = xe.max(), let y0 = ys.min(), let y1 = ye.max(),
                  !(x0 >= W || x1 <= 0 || y0 >= H || y1 <= 0) else { return }
            placed.append(Placed(isArmy: true, x: ox, y: oy, name: "adv_actor." + actorName, model: m, ax: ax, ay: ay,
                                 flagPoint: colour == nil ? nil : (adv.tail.x0, adv.tail.y0), colour: colour))
        }

        for (i, o) in objects.enumerated() where Int(o.level) == level {
            let cl = o.className
            if Self.hiddenClasses.contains(cl) || state?.removed.contains(i) == true { continue }
            let at = state?.armyCells[i]
            let (ox, oy) = at.map { ($0.r, $0.c) } ?? (Int(o.x), Int(o.y))
            let a = H4MapObjectRender.anchor(x: ox, y: oy, region: region)
            if cl == "army" {
                guard case .army(let rec) = o.payload else { continue }
                let slots: [ActorSlot] = (rec.army?.slots ?? []).map {
                    switch $0 {
                    case .empty: return .empty
                    case .stack(let s): return (0..<creatureCount).contains(Int(s.creature)) ? .creature(Int(s.creature)) : .empty
                    case .hero(let h): return .hero(heroClass: Int(h.heroClass), gender: Int(h.gender))
                    }
                }
                guard let name = Self.actorName(boat: rec.ai.map(Int.init) ?? -1, slots: slots,
                                                level: { tables.creatures[$0].level }, keyword: { tables.creatures[$0].keyword },
                                                heroExists: heroExists) else { continue }
                try addArmy(x: ox, y: oy, actorName: name, owner: Int(rec.owner), ax: a.x, ay: a.y)
            } else if cl == "random_monster" || cl == "random_random_monster" {
                guard let rr = resolved[i], let model = rr.resolved.model, !model.isEmpty, rr.resolved.removed != true,
                      let c = rr.resolved.creature, (0..<creatureCount).contains(c) else { continue }
                try addArmy(x: ox, y: oy, actorName: tables.creatures[c].keyword, owner: 6, ax: a.x, ay: a.y)
            } else if cl.hasPrefix("random_") || cl == "windmill" {
                guard let rr = resolved[i], let model = rr.resolved.model, !model.isEmpty else { continue }
                try addObject(o, name: model, owner: rr.owner, ax: a.x, ay: a.y)
            } else {
                try addObject(o, name: o.modelName, owner: Self.owner(of: o), ax: a.x, ay: a.y)
            }
        }

        if let state, state.arrowLevel == level {
            for (cell, name) in state.arrows {
                guard let m = try models.model(named: name),
                      H4MapObjectRender.isIncluded(x: cell.r, y: cell.c, width: 1, height: 1, region: region) else { continue }
                let a = H4MapObjectRender.anchor(x: cell.r, y: cell.c, region: region)
                var p = Placed(isArmy: false, x: cell.r, y: cell.c, name: name, model: m, ax: a.x, ay: a.y, flagPoint: nil, colour: nil)
                p.isArrow = true
                placed.append(p)
            }
        }

        var list = H4ObjectDrawList()
        list.objectCount = placed.filter { !$0.isArmy && !$0.isArrow }.count
        list.armyCount = placed.filter(\.isArmy).count

        func item(_ kind: H4ObjectDrawItem.Kind, _ p: Placed, _ k: Int, column: Int?, clip: Range<Int>?) -> H4ObjectDrawItem {
            let l = p.model.layers[k]
            return H4ObjectDrawItem(kind: kind, model: p.name, x: p.x, y: p.y, layerIndex: k, column: column,
                                    left: p.ax + p.model.originX + l.left, top: p.ay + p.model.originY + l.top,
                                    clip: clip, pixels: p.model.layerPixels(k)!)
        }
        func flagItem(_ p: Placed) throws -> H4ObjectDrawItem? {
            guard let c = p.colour, let pt = p.flagPoint, let f = try flag(c) else { return nil }
            return H4ObjectDrawItem(kind: .flag, model: c, x: p.x, y: p.y, layerIndex: 0, column: nil,
                                    left: p.ax + pt.dx - f.hx + f.left, top: p.ay + pt.dy - f.hy + f.top, clip: nil, pixels: f.pixels)
        }

        for p in placed {                                             // pass A
            for k in p.model.shadowLayers { list.items.append(item(.shadow, p, k, column: nil, clip: nil)) }
        }
        var strips: [Strip] = []
        func add(_ key: SortKey, _ it: H4ObjectDrawItem) { strips.append(Strip(key: key, order: strips.count, item: it)) }
        for p in placed {                                             // pass B
            let m = p.model, s = p.x + p.y
            if p.isArmy || p.isArrow {
                for k in m.bodyLayers {
                    let l = m.layers[k]
                    for col in H4MapObjectRender.floorDiv(l.left + m.originX, 32)..<H4MapObjectRender.ceilDiv(l.right + m.originX, 32) {
                        add(SortKey(0, Double(s), Double(s), Double(p.x), Double(col)),
                            item(.body, p, k, column: col, clip: (p.ax + 32 * col)..<(p.ax + 32 * col + 32)))
                    }
                }
                if let f = try flagItem(p) { add(SortKey(0, Double(s) + 0.5, Double(s), Double(p.x), 0), f) }
                continue
            }
            if m.bodyLayers.isEmpty { continue }
            if m.imageKind == 1 || m.drawLayer == 2 {
                for k in m.bodyLayers { add(SortKey(-1, Double(s), Double(p.x)), item(.body, p, k, column: nil, clip: nil)) }
                if let f = try flagItem(p) { add(SortKey(-1, Double(s), Double(p.x), 1), f) }
                continue
            }
            var kmax: Int?
            for k in m.bodyLayers {
                let l = m.layers[k]
                for col in H4MapObjectRender.floorDiv(l.left + m.originX, 32)..<H4MapObjectRender.ceilDiv(l.right + m.originX, 32) {
                    let d = H4MapObjectRender.depth(of: m, column: col)
                    let b = s - d - 1
                    kmax = kmax.map { max($0, b) } ?? b
                    add(SortKey(0, Double(b), Double(s), Double(p.x), Double(col)),
                        item(.body, p, k, column: col, clip: (p.ax + 32 * col)..<(p.ax + 32 * col + 32)))
                }
            }
            if let kmax, let f = try flagItem(p) { add(SortKey(0, Double(kmax) + 0.5, Double(s), Double(p.x), 0), f) }
        }
        strips.sort { $0.key != $1.key ? $0.key < $1.key : $0.order < $1.order }
        list.items.append(contentsOf: strips.map(\.item))
        return list
    }
}
