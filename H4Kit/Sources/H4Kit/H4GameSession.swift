import Foundation

// Slice 7d-L — turn logic of a started game: select / plan / move / end turn / pickups / path arrows.
//
// Rules: docstring of the frozen reference `session_ref.py` (rules 1-8), reproduced in short; tags [I] inferred/pinned.
//  1. Players: the humans of the game start, by colour ascending, are the hot-seat order; the first one is current (-1 if none).
//     Armies = anonymous army records + random monsters resolved to an `adv_actor.*` model; id = object index; owner 6 = neutral.
//     Only the owner can select an army.
//  2. Calendar: day 1, week 1, month 1; 7 days/week, 4 weeks/month. endTurn: next human (selection and plan cleared); after the
//     last human the day advances and every army's points are reset to 2256. Non-human players are skipped.
//  3. Points: plan = movement query on the current world with the army's points left (full 2256). move takes every day-0 step and
//     charges each (a terminal object step included); points left = max(0, points - spent).
//  4. World mutation: worlds are built from the objects NOT removed and the armies at their CURRENT cells.
//  5. Pickups: only when the LAST step of the plan is taken today onto a terminal object cell; the army stops on the previous
//     cell and the object (lowest-index covering object with an entrance edge facing the step, else lowest covering) is removed
//     with its effect (resources of the army's owner, artifact ids in the army's backpack). No rand() anywhere.
//  6. Arrows: `H4PathArrows`.   7./8. Script and log schemas: `runScript`.

/// Why a command was refused: the reasons of the movement query plus the session's own.
public enum H4SessionWhy: String, Sendable, Error {
    case startInvalid = "start-invalid", goalOutOfMap = "goal-oob", goalArmy = "goal-army", goalBlocked = "goal-blocked"
    case noPath = "no-path"
    case notOwn = "not-own", noSelection = "no-selection", noPlan = "no-plan", noSteps = "no-steps", noPoints = "no-points"
}

/// An army of the session (state after the last command).
public struct H4SessionArmy: Sendable, Equatable {
    public let id: Int
    public let owner: Int
    public let cell: H4MoveCell
    public let level: Int
    public let pointsLeft: Int
}

/// The 7 resources of a player in the order gold, wood, ore, crystal, sulfur, mercury, gem.
public struct H4SessionResources: Sendable, Equatable {
    public static let names = ["gold", "wood", "ore", "crystal", "sulfur", "mercury", "gem"]
    public var amounts = [Int](repeating: 0, count: 7)
    public var gold: Int { amounts[0] }
    public var wood: Int { amounts[1] }
    public var ore: Int { amounts[2] }
    public var crystal: Int { amounts[3] }
    public var sulfur: Int { amounts[4] }
    public var mercury: Int { amounts[5] }
    public var gem: Int { amounts[6] }
    public subscript(name: String) -> Int { Self.names.firstIndex(of: name).map { amounts[$0] } ?? 0 }
}

/// Result of `plan(to:)`: the movement answer plus the arrow model names.
public struct H4PlannedPath: Sendable, Equatable {
    public var ok: Bool
    public var why: H4SessionWhy?
    public var path: [H4MoveCell]
    public var dayOf: [Int]
    public var cost: Int
    public var days: Int
    /// Arrow model names (`adv_object` models), one per path cell k = 1...N; empty when not ok.
    public var arrows: [String]

    public init(ok: Bool, why: H4SessionWhy?, path: [H4MoveCell], dayOf: [Int], cost: Int, days: Int, arrows: [String]) {
        self.ok = ok; self.why = why; self.path = path; self.dayOf = dayOf; self.cost = cost; self.days = days; self.arrows = arrows
    }
}

/// Result of `move()`.
public struct H4MoveOutcome: Sendable, Equatable {
    public var ok: Bool
    public var why: H4SessionWhy?
    /// Steps taken today (a pickup step included).
    public var steps: Int
    /// Index of the object picked up, if any.
    public var picked: Int?
    /// Movement points charged.
    public var spent: Int
    /// v2 ruleset: index of the own town the army entered (it stops on the previous cell and becomes its visitor), if any.
    public var visited: Int? = nil

    public init(ok: Bool, why: H4SessionWhy?, steps: Int, picked: Int?, spent: Int, visited: Int? = nil) {
        self.ok = ok; self.why = why; self.steps = steps; self.picked = picked; self.spent = spent; self.visited = visited
    }
}

/// A pickup object of a level and the cells a plan can end on to collect it.
public struct H4SessionPickup: Sendable, Equatable {
    public var objectIndex: Int
    public var targetCells: [H4MoveCell]
}

/// Session state the renderer needs (see `H4GameRender.drawList(... state:)`).
public struct H4SessionRenderState: Sendable {
    /// Current cell of every army (object index -> cell).
    public var armyCells: [Int: H4MoveCell] = [:]
    public var removed: Set<Int> = []
    /// Level and arrows (cell, `adv_object` model name) of the active plan.
    public var arrowLevel = 0
    public var arrows: [(cell: H4MoveCell, model: String)] = []
    /// Slice 8c, v2 only: object index -> model name of a town whose tier now differs from its tier at the start of the game.
    /// Empty in a fresh session (towns are drawn with their scenario / resolved model).
    public var modelOverride: [Int: String] = [:]
    public init() {}
}

public final class H4GameSession {
    public static let fullPoints = H4MoveWorld.fullPoints
    static let artifactClasses: Set<String> = ["random_artifact", "random_potion", "random_tome", "random_staff"]
    static let pileAmount: [String: Int] = ["gold": 600, "wood": 6, "ore": 6, "crystal": 3, "sulfur": 3, "mercury": 3, "gem": 3]
    static let pileSubclass: [String: String] = ["gold_pile": "gold", "wood_pile": "wood", "ore_pile": "ore", "crystal_pile": "crystal",
                                                 "sulfur_pile": "sulfur", "pot_of_mecury": "mercury", "pot_of_mercury": "mercury",
                                                 "gem_pile": "gem"]

    /// One scenario object reduced to what the session needs.
    struct Object {
        var className: String
        /// Model of the scenario object (the original one, not the resolved one).
        var modelName: String
        var subclass: String
        var x: Int, y: Int, level: Int
        var resolved: H4ResolvedObject?
        /// Footprint of the placed model (nil: not placed, or an army).
        var footprint: H4MoveFootprint?
        /// Non-nil for armies: owner 0...6.
        var armyOwner: Int?
    }

    struct ArmyState { var cell: H4MoveCell; var level: Int; var owner: Int; var points: Int }

    let objects: [Object]
    public let levels: Int
    /// The scenario objects (file order) for `H4GameRender`; empty for synthetic sessions.
    public let scenarioObjects: [H4ScenarioObject]
    let artifactIDByModel: [String: Int]
    private let makeWorld: (Int, [H4MovePlaced]) -> H4MoveWorld

    public let players: [Int]
    let humans: [Int]
    public internal(set) var currentPlayer: Int
    public internal(set) var day = 1, week = 1, month = 1
    var armyStates: [Int: ArmyState] = [:]
    var resourceStore: [Int: H4SessionResources] = [:]
    var backpacks: [Int: [Int]] = [:]
    var removed: Set<Int> = []
    var selected: Int?
    /// Towns, economy and army slots (slice 8a); nil under the v1 ruleset.
    var townWorld: H4TownWorld?
    /// Resources the town queries of slice 8c read (terrain, start masks); nil under v1 and in synthetic sessions.
    var townAux: H4TownAux?
    /// Building mask of every town at the start of the game (v2): the tiers of the map models are compared with it.
    var townStartMask: [Int: Int] = [:]
    public private(set) var ruleset = H4Ruleset.v1
    private var plannedAnswer: H4MoveAnswer?
    private var worlds: [Int: H4MoveWorld] = [:]
    private var placed: [Int: [(id: Int, placed: H4MovePlaced)]] = [:]

    // MARK: construction

    /// A session of a started game. `tables` defaults to the tables read from `resources`.
    /// `ruleset` v1 (default) is the frozen 7d-L session; v2 adds the towns and the economy of slice 8a.
    public convenience init(game: H4Game, scenario: H4Scenario, resources: H4ResourceStore, tables: H4GameTables? = nil,
                            ruleset: H4Ruleset = .v1) throws {
        let body = try H4ScenarioBody(scenario: scenario, resources: resources)
        guard case .complete = body.stop else { throw H4Error.malformed("object list stopped at \(body.stop.offset)") }
        let terrain = try H4ScenarioTerrain(scenario: scenario)
        let tables = try tables ?? H4GameTables(store: resources)
        let models = H4MoveModels(store: resources)
        let resolved = Dictionary(game.objects.map { ($0.index, $0.resolved) }, uniquingKeysWith: { a, _ in a })
        var list: [Object] = []
        list.reserveCapacity(body.objects.count)
        for (i, o) in body.objects.enumerated() {
            let cls = o.className
            var obj = Object(className: cls, modelName: o.modelName, subclass: o.triple?.subclassName ?? "", x: Int(o.x), y: Int(o.y),
                             level: Int(o.level), resolved: resolved[i], footprint: nil, armyOwner: nil)
            if cls == "army" {
                if case .army(let rec) = o.payload { obj.armyOwner = Int(rec.owner) } else { obj.armyOwner = 6 }
            } else {
                var model = o.modelName
                if let r = resolved[i] { model = r.model ?? "" }
                if model.hasPrefix("adv_actor.") {
                    obj.armyOwner = 6
                } else if !model.isEmpty {
                    obj.footprint = try models.footprint(model)
                }
            }
            list.append(obj)
        }
        self.init(players: game.players.map { ($0.colour, $0.human) }, objects: list, levels: scenario.levels,
                  artifactIDByModel: tables.artifactIDByModel, scenarioObjects: body.objects,
                  world: { level, placed in H4MoveWorld(terrain: terrain, level: level, placed: placed) })
        if ruleset == .v2 {
            let townTables = try H4TownTables(store: resources, tables: tables)
            var world = try H4TownWorld(game: game, scenario: scenario, objects: body.objects,
                                        armies: armyStates.mapValues(\.owner), tables: townTables)
            for p in H4TownWorld.players(game: game, scenario: scenario) { resourceStore[p.colour] = H4SessionResources(amounts: p.start) }
            world.clearVisits()
            townAux = H4TownAux(store: resources, terrain: terrain)
            townStartMask = world.towns.mapValues(\.mask)
            townWorld = world
            self.ruleset = .v2
        }
    }

    /// Core initialiser (also used by the synthetic tests).
    init(players: [(colour: Int, human: Bool)], objects: [Object], levels: Int, artifactIDByModel: [String: Int],
         scenarioObjects: [H4ScenarioObject] = [], world: @escaping (Int, [H4MovePlaced]) -> H4MoveWorld) {
        let sorted = players.sorted { $0.colour < $1.colour }
        self.players = sorted.map(\.colour)
        humans = sorted.filter(\.human).map(\.colour)
        currentPlayer = humans.first ?? -1
        self.objects = objects
        self.levels = levels
        self.artifactIDByModel = artifactIDByModel
        self.scenarioObjects = scenarioObjects
        makeWorld = world
        for p in self.players { resourceStore[p] = H4SessionResources() }
        for (i, o) in objects.enumerated() {
            if let owner = o.armyOwner {
                armyStates[i] = ArmyState(cell: H4MoveCell(o.x, o.y), level: o.level, owner: owner, points: Self.fullPoints)
            }
        }
    }

    // MARK: state

    public var armies: [H4SessionArmy] {
        armyStates.keys.sorted().map { id in
            let a = armyStates[id]!
            return H4SessionArmy(id: id, owner: a.owner, cell: a.cell, level: a.level, pointsLeft: a.points)
        }
    }

    public func army(_ id: Int) -> H4SessionArmy? {
        armyStates[id].map { H4SessionArmy(id: id, owner: $0.owner, cell: $0.cell, level: $0.level, pointsLeft: $0.points) }
    }

    public func resources(player: Int) -> H4SessionResources? { resourceStore[player] }
    public func backpack(army: Int) -> [Int] { backpacks[army] ?? [] }
    /// Indices of the objects picked up so far, ascending.
    public var removedObjects: [Int] { removed.sorted() }
    public var selectedArmy: Int? { selected }
    /// The stored plan, if any.
    public var currentPlan: H4PlannedPath? {
        guard let a = plannedAnswer, let s = selected, armyStates[s] != nil else { return nil }
        return Self.planned(a)
    }

    /// Snapshot for `H4GameRender`.
    public var renderState: H4SessionRenderState {
        var s = H4SessionRenderState()
        for (id, a) in armyStates { s.armyCells[id] = a.cell }
        s.removed = removed
        if let a = plannedAnswer, let sel = selected, let army = armyStates[sel], a.reachable,
           let names = H4PathArrows.names(path: a.path, dayOf: a.dayOf) {
            s.arrowLevel = army.level
            s.arrows = zip(a.path.dropFirst(), names).map { ($0, $1) }
        }
        s.modelOverride = townModelOverrides()
        return s
    }

    // MARK: world (rule 4)

    func world(level: Int) -> H4MoveWorld {
        if let w = worlds[level] { return w }
        var list: [(id: Int, placed: H4MovePlaced)] = []
        for (i, o) in objects.enumerated() where o.level == level && !removed.contains(i) {
            if let a = armyStates[i] {
                list.append((i, H4MovePlaced(armyAt: a.cell.r, a.cell.c)))
            } else if let fp = o.footprint {
                list.append((i, H4MovePlaced(className: o.className, x: o.x, y: o.y, footprint: fp)))
            }
        }
        placed[level] = list
        let w = makeWorld(level, list.map(\.placed))
        worlds[level] = w
        return w
    }

    // MARK: commands

    @discardableResult
    public func select(army id: Int) -> Result<Void, H4SessionWhy> {
        guard let a = armyStates[id], a.owner == currentPlayer else { return .failure(.notOwn) }
        selected = id
        plannedAnswer = nil
        return .success(())
    }

    static func planned(_ a: H4MoveAnswer) -> H4PlannedPath {
        H4PlannedPath(ok: a.reachable, why: a.why.flatMap { H4SessionWhy(rawValue: $0.rawValue) }, path: a.path, dayOf: a.dayOf,
                      cost: a.cost, days: a.days, arrows: a.reachable ? (H4PathArrows.names(path: a.path, dayOf: a.dayOf) ?? []) : [])
    }

    /// Plan a path from the selected army to `cell` (rule 3); the plan is stored when reachable, else cleared.
    @discardableResult
    public func plan(to cell: H4MoveCell) -> H4PlannedPath {
        guard let sel = selected, let a = armyStates[sel] else {
            return H4PlannedPath(ok: false, why: .noSelection, path: [], dayOf: [], cost: -1, days: -1, arrows: [])
        }
        let answer = world(level: a.level).query(from: a.cell, to: cell, points: a.points, full: Self.fullPoints)
        plannedAnswer = answer.reachable ? answer : nil
        return Self.planned(answer)
    }

    /// Per-step costs of a path on a world (rule 3 recomputed).
    func stepCosts(_ w: H4MoveWorld, _ path: [H4MoveCell]) -> [Int] {
        var out: [Int] = []
        for i in 1..<max(path.count, 1) {
            let u = w.index(path[i - 1].r, path[i - 1].c), v = w.index(path[i].r, path[i].c)
            let k = H4PathArrows.direction(from: path[i - 1], to: path[i]) ?? 0
            var c: Int
            if w.deck[v] != 0 { c = 75 }
            else if w.road[u] != 0 && w.road[v] != 0 { c = w.road[v] == 2 ? 100 : 75 }
            else { c = Int(H4MoveWorld.terrainCosts[Int(w.terrain[v])]) }
            if k & 1 != 0 { c += c >> 1 }
            out.append(c)
        }
        return out
    }

    /// Execute the stored plan (rules 3 and 5).
    @discardableResult
    public func move() -> H4MoveOutcome {
        func refuse(_ why: H4SessionWhy) -> H4MoveOutcome { H4MoveOutcome(ok: false, why: why, steps: 0, picked: nil, spent: 0) }
        guard let sel = selected, var a = armyStates[sel] else { return refuse(.noSelection) }
        guard let plan = plannedAnswer else { return refuse(.noPlan) }
        let path = plan.path, n = path.count - 1
        guard n >= 1 else { return refuse(.noSteps) }
        let taken = plan.dayOf.filter { $0 == 0 }.count
        guard taken > 0 else { return refuse(.noPoints) }
        let w = world(level: a.level)
        let costs = stepCosts(w, path)
        assert(costs.reduce(0, +) == plan.cost, "step cost mismatch")
        let spent = costs.prefix(taken).reduce(0, +)
        let last = path[taken]
        var end = last
        var picked: Int?
        var visit: Int?
        if taken == n && w.kind[w.index(last.r, last.c)] == 2 {
            end = path[n - 1]
            if let oid = entryObject(level: a.level, world: w, from: path[n - 1], to: last) {
                if townWorld?.towns[oid] != nil { visit = oid } else if pickup(oid, by: sel) { picked = oid }
            }
        }
        a.cell = end
        a.points = max(0, a.points - spent)
        armyStates[sel] = a
        worlds[a.level] = nil
        plannedAnswer = nil
        var visited: Int?
        if townWorld != nil {                                       // v2 R5 VISITING [I]
            for i in townWorld!.townOrder where townWorld!.towns[i]!.visitingArmy == sel { townWorld!.towns[i]!.visitingArmy = nil }
            if let v = visit, townWorld!.towns[v]!.owner == a.owner { townWorld!.towns[v]!.visitingArmy = sel; visited = v }
        }
        return H4MoveOutcome(ok: true, why: nil, steps: taken, picked: picked, spent: spent, visited: visited)
    }

    /// Next player; after the last human the day advances and every army's points are reset (rule 2).
    public func endTurn() {
        selected = nil
        plannedAnswer = nil
        townWorld?.clearVisits()
        if let last = humans.last, currentPlayer != last {
            currentPlayer = humans[humans.firstIndex(of: currentPlayer)! + 1]
            return
        }
        if let first = humans.first { currentPlayer = first }
        day += 1
        if day == 8 {
            day = 1; week += 1
            if week == 5 { week = 1; month += 1 }
        }
        for id in armyStates.keys { armyStates[id]!.points = Self.fullPoints }
        if townWorld != nil {                                       // v2 R3: day tick, D = days elapsed after the advance
            townWorld!.dayTick(day: (day - 1) + 7 * (week - 1) + 28 * (month - 1), resources: &resourceStore)
        }
    }

    // MARK: pickups (rule 5)

    /// The object whose terminal cell `v` is entered from `u` (lowest index with an entrance edge facing the step, else the
    /// lowest covering `v`).
    func entryObject(level: Int, world w: H4MoveWorld, from u: H4MoveCell, to v: H4MoveCell) -> Int? {
        guard let k = H4PathArrows.direction(from: u, to: v) else { return nil }
        var first: Int?
        for (id, p) in placed[level] ?? [] {
            guard let g = p.footprint, p.className != "bridge", p.className != "ferry" else { continue }
            let ii = v.r - p.x, jj = v.c - p.y, W = g.width, H = g.height
            guard (0..<W).contains(ii), (0..<H).contains(jj), g.blocked[jj * W + ii] else { continue }
            if first == nil { first = id }
            guard let eh = g.edgesHorizontal, let ev = g.edgesVertical else { continue }
            var mask: UInt8 = 0
            if ii == 0 && ev[jj] { mask |= H4MoveWorld.up }
            if ii == W - 1 && ev[W * H + jj] { mask |= H4MoveWorld.down }
            if jj == 0 && eh[ii] { mask |= H4MoveWorld.left }
            if jj == H - 1 && eh[H * W + ii] { mask |= H4MoveWorld.right }
            if mask & w.sides[k] != 0 { return id }
        }
        return first
    }

    static func pileResource(modelName: String, subclass: String) -> String? {
        var nm = (modelName.split(separator: ".", omittingEmptySubsequences: false).last.map(String.init) ?? modelName).lowercased()
        if pileAmount[nm] == nil { nm = pileSubclass[subclass.lowercased()] ?? nm }
        return pileAmount[nm] != nil ? nm : nil
    }

    /// Applies the pickup effect of object `oid` for `army` and removes the object; false when the class has none.
    private func pickup(_ oid: Int, by army: Int) -> Bool {
        let o = objects[oid]
        let owner = armyStates[army]!.owner
        let res = o.resolved
        switch o.className {
        case "random_material_pile":
            guard let m = res?.material, let amount = res?.amount, (0..<7).contains(m) else { return false }
            resourceStore[owner]?.amounts[m] += amount
        case "material_pile":
            if let nm = Self.pileResource(modelName: o.modelName, subclass: o.subclass), let i = H4SessionResources.names.firstIndex(of: nm) {
                resourceStore[owner]?.amounts[i] += Self.pileAmount[nm]!
            }
        case let c where Self.artifactClasses.contains(c):
            if let id = res?.artifact { backpacks[army, default: []].append(id) }
        case "artifact":
            backpacks[army, default: []].append(artifactIDByModel[o.modelName.lowercased()] ?? -1)
        case "treasure":
            resourceStore[owner]?.amounts[0] += 1000
        case "campfire":
            resourceStore[owner]?.amounts[0] += 500
            resourceStore[owner]?.amounts[1] += 5
        default:
            return false
        }
        removed.insert(oid)
        worlds.removeAll()
        return true
    }

    /// Whether the object has a defined pickup effect (pinned [I]).
    func isPickup(_ o: Object) -> Bool {
        switch o.className {
        case "random_material_pile": return o.resolved?.material != nil && o.resolved?.amount != nil
        case "material_pile": return Self.pileResource(modelName: o.modelName, subclass: o.subclass) != nil
        case let c where Self.artifactClasses.contains(c): return o.resolved?.artifact != nil
        case "artifact", "treasure", "campfire": return true
        default: return false
        }
    }

    /// Cells of `object` a plan can end on from a free cell: its terminal cells (footprint cells with an entrance edge) that
    /// some free cell can step into (rule 2 of the movement), sorted by (row, column). Army-independent: a cell only the
    /// army's own start cell can enter is not listed here (see `nearestPickup(for:)`).
    func targetCells(of id: Int, world w: H4MoveWorld) -> [H4MoveCell] {
        guard let g = objects[id].footprint else { return [] }
        let o = objects[id]
        var out: [H4MoveCell] = []
        for i in 0..<g.width {
            for j in 0..<g.height where g.blocked[j * g.width + i] && w.inMap(o.x + i, o.y + j) {
                let v = w.index(o.x + i, o.y + j)
                guard w.kind[v] == 2 else { continue }
                if (0..<8).contains(where: { k in w.kind[v - w.offsets[k]] == 1 && w.entrance[v] & w.sides[k] != 0 }) {
                    out.append(H4MoveCell(o.x + i, o.y + j))
                }
            }
        }
        return out.sorted { ($0.r, $0.c) < ($1.r, $1.c) }
    }

    /// Pickup objects of a level with the cells a plan can end on from a free cell, by object index. Objects without such a
    /// cell are left out. Army-independent.
    public func pickups(level: Int) -> [H4SessionPickup] {
        let w = world(level: level)
        var out: [H4SessionPickup] = []
        for (id, _) in placed[level] ?? [] where isPickup(objects[id]) {
            let cells = targetCells(of: id, world: w)
            if !cells.isEmpty { out.append(H4SessionPickup(objectIndex: id, targetCells: cells)) }
        }
        return out
    }

    /// The reachable pickup target of least cost from the army's cell with its points left; ties by object index, then (row,
    /// column). Candidates are the terminal cells of pickup objects reached by the army's own search tree, i.e. exactly the
    /// cells `plan(to:)` accepts (this includes a cell only the army's start cell can enter). nil when none is reachable.
    public func nearestPickup(for army: Int) -> (objectIndex: Int, targetCell: H4MoveCell, cost: Int)? {
        guard let a = armyStates[army] else { return nil }
        let w = world(level: a.level)
        guard let tree = w.tree(from: a.cell) else { return nil }
        var best: (objectIndex: Int, targetCell: H4MoveCell, cost: Int)?
        for (id, _) in placed[a.level] ?? [] where isPickup(objects[id]) {
            guard let g = objects[id].footprint else { continue }
            let o = objects[id]
            for i in 0..<g.width {
                for j in 0..<g.height where g.blocked[j * g.width + i] && w.inMap(o.x + i, o.y + j) {
                    let v = w.index(o.x + i, o.y + j)
                    guard w.kind[v] == 2, tree.dist[v] != H4MoveWorld.unreached else { continue }
                    let cand = (objectIndex: id, targetCell: H4MoveCell(o.x + i, o.y + j), cost: Int(tree.dist[v]))
                    if let b = best, (b.cost, b.objectIndex, b.targetCell.r, b.targetCell.c) <= (cand.cost, cand.objectIndex, cand.targetCell.r, cand.targetCell.c) { continue }
                    best = cand
                }
            }
        }
        return best
    }
}

// MARK: - Script and log (rules 7 and 8)

/// Canonical JSON (sorted keys, compact separators, ASCII) as the reference log writer.
enum H4LogJSON {
    case int(Int), bool(Bool), null, str(String), arr([H4LogJSON]), obj([String: H4LogJSON])

    var text: String {
        switch self {
        case .int(let v): return String(v)
        case .bool(let v): return v ? "true" : "false"
        case .null: return "null"
        case .str(let s): return H4MovementSession.jsonString(s)
        case .arr(let a): return "[" + a.map(\.text).joined(separator: ",") + "]"
        case .obj(let o):
            let keys = o.keys.sorted { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes($1.unicodeScalars.map(\.value)) }
            return "{" + keys.map { H4MovementSession.jsonString($0) + ":" + o[$0]!.text }.joined(separator: ",") + "}"
        }
    }

    /// A parsed JSON value (JSONSerialization) echoed as is; non-integer numbers are rejected.
    init(echo v: Any) throws {
        switch v {
        case is NSNull: self = .null
        case let s as String: self = .str(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) }
            else if CFNumberIsFloatType(n) { throw H4Error.malformed("non-integer number \(n) in a script command") }
            else { self = .int(n.intValue) }
        case let a as [Any]: self = .arr(try a.map { try H4LogJSON(echo: $0) })
        case let d as [String: Any]: self = .obj(try d.mapValues { try H4LogJSON(echo: $0) })
        default: throw H4Error.malformed("unsupported value in a script command")
        }
    }

    static func cell(_ c: H4MoveCell) -> H4LogJSON { .arr([.int(c.r), .int(c.c)]) }
    static func ints(_ v: [Int]) -> H4LogJSON { .arr(v.map { .int($0) }) }
}

extension H4GameSession {
    /// The state fields of a log record.
    func logState() -> [String: H4LogJSON] {
        var o: [String: H4LogJSON] = [
            "player": .int(currentPlayer), "day": .int(day), "week": .int(week), "month": .int(month),
            "selected": selected.map { .int($0) } ?? .null, "cell": .null, "level": .null, "points": .null,
            "removed": .ints(removed.sorted()),
        ]
        var res: [String: H4LogJSON] = [:]
        for p in players {
            let r = resourceStore[p]!
            res[String(p)] = .obj(Dictionary(uniqueKeysWithValues: H4SessionResources.names.enumerated().map { ($1, .int(r.amounts[$0])) }))
        }
        o["resources"] = .obj(res)
        var bags: [String: H4LogJSON] = [:]
        for (id, b) in backpacks where !b.isEmpty { bags[String(id)] = .ints(b) }
        o["backpacks"] = .obj(bags)
        if let s = selected, let a = armyStates[s] {
            o["cell"] = .cell(a.cell); o["level"] = .int(a.level); o["points"] = .int(a.points)
        }
        if let w = townWorld { o.merge(w.logFields()) { a, _ in a } }
        return o
    }

    /// Runs one script command (rule 7) and returns its log record (rule 8).
    func run(command: [String: Any]) throws -> H4LogJSON {
        guard let op = command["op"] as? String else { throw H4Error.malformed("script command without op") }
        var rec: [String: H4LogJSON] = ["op": .str(op)]
        var why: H4SessionWhy?
        var townWhy: String?
        let townOp = townWorld != nil && ["build", "recruit", "transfer"].contains(op)
        if !townOp { for k in ["army", "to"] { if let v = command[k] { rec[k] = try H4LogJSON(echo: v) } } }       // the command's own argument, as given
        switch op {
        case "select":
            guard let id = command["army"] as? Int else { throw H4Error.malformed("select without army") }
            if case .failure(let w) = select(army: id) { why = w }
        case "plan":
            guard let to = command["to"] as? [Int], to.count == 2 else { throw H4Error.malformed("plan without to") }
            let p = plan(to: H4MoveCell(to[0], to[1]))
            why = p.why
            if why != .noSelection {                          // without a selection the record has no answer fields
                rec["path"] = .arr(p.path.map { .cell($0) }); rec["day_of"] = .ints(p.dayOf)
                rec["cost"] = .int(p.cost); rec["days"] = .int(p.days); rec["arrows"] = .arr(p.arrows.map { .str($0) })
            }
        case "move":
            let m = move()
            why = m.why
            rec["steps"] = .int(m.steps); rec["picked"] = m.picked.map { .int($0) } ?? .null; rec["spent"] = .int(m.spent)
            if townWorld != nil { rec["visited"] = m.visited.map { .int($0) } ?? .null }
        case _ where townOp:
            for k in ["town", "building", "count", "from", "to"] { if let v = command[k] { rec[k] = try H4LogJSON(echo: v) } }
            let r = townCommand(op, command)
            townWhy = r.ok ? nil : (r.why ?? "")
            if op == "recruit" { rec["recruited"] = .int(r.count ?? 0) } else if op == "transfer" { rec["moved"] = .int(r.count ?? 0) }
        case "endturn": endTurn()
        case "state": break
        default: throw H4Error.malformed("unknown op '\(op)'")
        }
        let whyText = townWhy ?? why?.rawValue
        rec["ok"] = .bool(whyText == nil)
        rec["why"] = whyText.map { .str($0) } ?? .null
        for (k, v) in logState() { rec[k] = v }
        return .obj(rec)
    }

    /// Runs one command given as a script dictionary (rule 7) and returns its log record (rule 8). This is the single entry
    /// through which a front end changes the game state; `runScript` loops over it.
    public func execute(command: [String: Any]) throws -> H4LogRecord { H4LogRecord(json: try run(command: command)) }

    /// Runs a script (JSON list of commands) and returns the canonical log text (no trailing newline).
    public func runScript(_ data: Data) throws -> String {
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw H4Error.malformed("script is not a JSON list of commands")
        }
        return "[" + (try list.map { try execute(command: $0).text }).joined(separator: ",") + "]"
    }
}

// MARK: - Town commands (slice 8a, v2 ruleset)

extension H4GameSession {
    /// The towns in object order (empty under the v1 ruleset).
    public var towns: [H4TownState] { townWorld.map { w in w.townOrder.map { w.towns[$0]! } } ?? [] }

    /// Slots of an army of the session (7), nil under v1 or for an unknown id.
    public func slots(army id: Int) -> [H4SlotStack]? { townWorld?.slots[id] }

    /// Runs a v2 town command given as a script dictionary.
    func townCommand(_ op: String, _ command: [String: Any]) -> H4TownOp {
        guard townWorld != nil else { return H4TownOp(ok: false, why: "bad-ruleset", count: nil) }
        switch op {
        case "build": return townWorld!.build(command, current: currentPlayer, resources: &resourceStore)
        case "recruit": return townWorld!.recruit(command, current: currentPlayer, resources: &resourceStore)
        default: return townWorld!.transfer(command, current: currentPlayer)
        }
    }

    /// R4: builds `building` in town `town` for the current player.
    @discardableResult
    public func build(town: Int, building: Int) -> H4TownOp { townCommand("build", ["town": town, "building": building]) }

    /// R5: recruits `count` creatures of dwelling `building` of the town into its garrison.
    @discardableResult
    public func recruit(town: Int, building: Int, count: Int) -> H4TownOp {
        townCommand("recruit", ["town": town, "building": building, "count": count])
    }

    /// R5: moves creatures between garrisons / armies; a container is `["town": i, "slot": s]` or `["army": id, "slot": s]`.
    @discardableResult
    public func transfer(from: [String: Int], to: [String: Int], count: Int? = nil) -> H4TownOp {
        var c: [String: Any] = ["from": from, "to": to]
        if let count { c["count"] = count }
        return townCommand("transfer", c)
    }
}

/// A log record (rule 8) of one executed command, in the canonical JSON of the script logs.
public struct H4LogRecord: Sendable {
    let json: H4LogJSON

    /// Canonical JSON text of the record (what `runScript` joins into the log).
    public var text: String { json.text }

    /// The record as a Foundation dictionary.
    public var fields: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }

    private var object: [String: H4LogJSON] { if case .obj(let o) = json { return o }; return [:] }
    public var ok: Bool { if case .bool(let b)? = object["ok"] { return b }; return false }
    public var why: String? { if case .str(let t)? = object["why"] { return t }; return nil }
    public func int(_ key: String) -> Int? { if case .int(let v)? = object[key] { return v }; return nil }
    /// An array of integers, e.g. `day_of`.
    public func ints(_ key: String) -> [Int]? {
        guard case .arr(let a)? = object[key] else { return nil }
        return a.compactMap { if case .int(let v) = $0 { return v }; return nil }
    }
    /// Number of elements of an array field (e.g. `path`).
    public func count(_ key: String) -> Int? { if case .arr(let a)? = object[key] { return a.count }; return nil }
}
