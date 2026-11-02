import Foundation
import Testing
@testable import H4Kit

// Slice 8c: town queries of a v2 session (buildStatus, recruitPreview, transferPreview, terrain, model override, labels).
//   H4_DATA_DIR, H4_MAPS_DIR     game folders
//   H4_TOWN_ORACLE_DIR           the oracle root (SCRATCH): step3/session2 scripts and logs

private let env = ProcessInfo.processInfo.environment
private let hasData = env["H4_DATA_DIR"] != nil && env["H4_MAPS_DIR"] != nil
private let hasOracle = hasData && env["H4_TOWN_ORACLE_DIR"] != nil

// MARK: - No data

private func creatures() -> [H4GameTables.Creature] {
    (0..<74).map { id in
        H4GameTables.Creature(keyword: "c\(id)", level: 1, alignment: 0, experience: 1, expansion: 0, dwelling: "",
                              weeklyGrowth: 10 + id, cost: [id + 1, 0, 0, 0, 0, 0, 0])
    }
}

private func tables() -> H4TownTables {
    H4TownTables(buildings: H4BuildingTable(costs: (0..<6).map { f in
        Dictionary(uniqueKeysWithValues: H4TownRules.keywords[f].keys.map { ($0, [100 * $0 + f, 0, 0, 0, 0, 0, 0]) })
    }), creatures: creatures())
}

private func town(_ index: Int, owner: Int = 0, mask: Int = 0x101, allowed: Int = (1 << 43) - 1) -> H4TownState {
    H4TownState(index: index, className: "town", faction: 0, right: false, owner: owner, mask: mask, allowed: allowed, builtToday: 0,
                stock: Array(repeating: 0, count: 8), garrison: Array(repeating: .empty, count: 7), visitingArmy: nil)
}

/// A synthetic v2 session: player 0 (human, 3000 gold) with town 0, other towns for the refusals.
private func session(towns: [H4TownState], gold: Int = 3000) -> H4GameSession {
    let s = H4GameSession(players: [(colour: 0, human: true), (colour: 1, human: false)], objects: [], levels: 1, artifactIDByModel: [:],
                          world: { _, placed in H4MoveWorld(size: 4, rows: Array(repeating: 0..<4, count: 4), cell: { _, _ in (1, 0, 0) }, placed: placed) })
    s.townWorld = H4TownWorld(towns: towns, humanOf: [0: true, 1: false], tables: tables())
    s.resourceStore[0] = H4SessionResources(amounts: [gold, 100, 100, 100, 100, 100, 100])
    return s
}

@Test func buildLabelTableIsTotal() {
    // every why build() emits has a non-empty label, and the labels of the plan
    #expect(H4TownLabels.build(nil) == "Build")
    let expected = ["already-built": "Built", "built-today": "Already built today", "resources": "Not enough resources",
                    "requirements": "Requires other buildings", "exclusive-partner": "Excludes a built building",
                    "not-allowed": "Not allowed on this map", "faction-static-set": "Unavailable", "not-own-town": "Unavailable",
                    "not-current-player": "Unavailable"]
    #expect(Set(expected.keys) == Set(H4TownLabels.buildWhys))
    for (why, label) in expected { #expect(H4TownLabels.build(why) == label, "\(why)") }
    // drive the real build() into every why on a synthetic world: the set of whys it gives is exactly buildWhys
    var seen: Set<String> = []
    let s = session(towns: [town(0, mask: 0x101 | 1 << 3 | 1 << 9), town(1, owner: 1), town(2, allowed: 0)])
    s.townWorld!.towns[0]!.allowed &= ~(1 << 6)
    for t in 0...3 {
        for b in [0, 1, 2, 3, 5, 6, 12, 14, 20, 99] {
            let status = s.buildStatus(town: t, building: b)
            if let status { seen.insert(status); #expect(H4TownLabels.buildWhys.contains(status), "unlabelled why \(status)") }
        }
    }
    s.resourceStore[0]!.amounts[0] = 0
    #expect(s.buildStatus(town: 0, building: 1) == "resources")
    seen.insert("resources")
    s.resourceStore[0]!.amounts[0] = 3000
    // built today and exclusive partner need a state change
    s.townWorld!.towns[0]!.mask |= 1 << 12 | 1 << 15
    #expect(s.buildStatus(town: 0, building: 14) == "exclusive-partner")
    seen.insert("exclusive-partner")
    s.townWorld!.towns[0]!.builtToday = 1
    #expect(s.buildStatus(town: 0, building: 1) == "built-today")
    seen.insert("built-today")
    #expect(seen == Set(H4TownLabels.buildWhys), "whys reached: \(seen.sorted())")
}

@Test func syntheticPreviewsMatchTheMutatingCalls() throws {
    var t = town(0, mask: 0x101 | 1 << 3 | 1 << 12)
    t.stock[0] = 700 * 5
    t.visitingArmy = 7
    t.garrison[0] = H4SlotStack(creature: 54, count: 4)
    let s = session(towns: [t], gold: 140)
    s.townWorld!.slots[7] = [.hero, .empty, .empty, .empty, .empty, .empty, .empty]
    s.townWorld!.armyOwner[7] = 0
    // recruit: 5 available, gold 140 / 55 = 2 affordable
    let p = try #require(s.recruitPreview(town: 0, building: 12))
    #expect(p.creature == 54 && p.available == 5 && p.maxAffordable == 2)
    #expect(s.recruitPreview(town: 0, building: 13) == nil && s.recruitPreview(town: 0, building: 3) == nil)
    let before = s.townWorld!.towns[0]!, res = s.resourceStore
    #expect(s.townWorld!.towns[0] == before && s.resourceStore == res)                          // a preview changes nothing
    let r = s.recruit(town: 0, building: 12, count: 1000)
    #expect(r.ok && r.count == p.maxAffordable)
    // transfer preview equals the call
    let pv = s.transferPreview(from: ["town": 0, "slot": 0], to: ["army": 7, "slot": 1], count: 2)
    #expect(s.townWorld!.slots[7]![1] == .empty)
    let tr = s.transfer(from: ["town": 0, "slot": 0], to: ["army": 7, "slot": 1], count: 2)
    #expect(pv == tr && tr.ok && tr.count == 2)
    #expect(s.transferPreview(from: ["town": 0, "slot": 0], to: ["army": 7, "slot": 0]).why == "hero-slot")
}

@Test func syntheticModelOverrideOnlyOnTierChange() {
    let s = session(towns: [town(0)])
    s.townStartMask = [0: 0x101]
    #expect(s.renderState.modelOverride.isEmpty)
    s.townWorld!.towns[0]!.mask |= 1 << 9                                                       // tavern: tier unchanged
    #expect(s.renderState.modelOverride.isEmpty)
    s.townWorld!.towns[0]!.mask |= 1 << 3                                                       // fort: tier 1
    #expect(s.renderState.modelOverride == [0: "castle.haven.fort"])
    s.townWorld!.towns[0]!.mask |= 1 << 5                                                       // castle: tier 3
    #expect(s.renderState.modelOverride == [0: "castle.haven.castle"])
}

// MARK: - Game data

private struct Wheel {
    let store: H4ResourceStore, tables: H4GameTables, scenario: H4Scenario, game: H4Game
    init(map: String) throws {
        let host = try H4MovementSession(dataDirectory: URL(fileURLWithPath: env["H4_DATA_DIR"]!),
                                         mapsDirectory: URL(fileURLWithPath: env["H4_MAPS_DIR"]!), seed: 12345, difficulty: 2)
        store = host.store; tables = host.tables
        let files = try #require(host.mapFiles[map])
        scenario = try H4Scenario(fileData: Data(contentsOf: URL(fileURLWithPath: files[0])))
        game = try H4GameStart.start(scenario: scenario, store: store, tables: tables, seed: 12345, difficulty: 2)
    }
    func session() throws -> H4GameSession { try H4GameSession(game: game, scenario: scenario, resources: store, tables: tables, ruleset: .v2) }
}

private let wheelMaps = ["Wheel-of-Misfortune", "Wheel-of-Misfortune_(Allied)"]

@Test(.enabled(if: hasData), arguments: wheelMaps)
func buildStatusEqualsBuildOnEveryTownAndId(map: String) throws {
    let s = try Wheel(map: map).session()
    let world0 = s.townWorld!, res0 = s.resourceStore
    var checked = 0, ok = 0
    for t in s.towns {
        for b in Array(0...42) + [99] {
            let predicted = s.buildStatus(town: t.index, building: b)
            let record = try s.execute(command: ["op": "build", "town": t.index, "building": b])
            #expect(record.why == predicted, "town \(t.index) building \(b)")
            #expect(record.ok == (predicted == nil))
            if predicted == nil { ok += 1 }
            checked += 1
            s.townWorld = world0; s.resourceStore = res0                                       // a fresh copy for the next pair
        }
    }
    #expect(checked == s.towns.count * 44 && ok > 0)
}

private func script(_ faction: String) throws -> [[String: Any]] {
    let url = URL(fileURLWithPath: env["H4_TOWN_ORACLE_DIR"]! + "/step3/session2/scripts/town_\(faction).json")
    return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
}

private let factionRuns: [(String, String)] = [
    ("life", "Wheel-of-Misfortune"), ("order", "Wheel-of-Misfortune_(Allied)"), ("death", "Wheel-of-Misfortune"),
    ("chaos", "Wheel-of-Misfortune_(Allied)"), ("nature", "Wheel-of-Misfortune"), ("might", "Wheel-of-Misfortune_(Allied)"),
]

private func ints(_ v: Any?) -> [String: Int]? {
    guard let d = v as? [String: Any] else { return nil }
    var out: [String: Int] = [:]
    for (k, x) in d { guard let n = x as? Int else { return nil }; out[k] = n }
    return out
}

@Test(.enabled(if: hasOracle), arguments: factionRuns)
func previewsEqualMutatingResultsOnTheScriptStates(run: (String, String)) throws {
    let s = try Wheel(map: run.1).session()
    var builds = 0, recruits = 0, transfers = 0
    for c in try script(run.0) {
        let op = c["op"] as? String ?? ""
        var predicted: H4TownOp?
        var buildPrediction: String?? = .none
        var maxAffordable: Int?
        switch op {
        case "build":
            if let t = c["town"] as? Int, let b = c["building"] as? Int { buildPrediction = .some(s.buildStatus(town: t, building: b)) }
        case "recruit":
            if let t = c["town"] as? Int, let b = c["building"] as? Int { maxAffordable = s.recruitPreview(town: t, building: b)?.maxAffordable }
        case "transfer":
            if let from = ints(c["from"]), let to = ints(c["to"]) { predicted = s.transferPreview(from: from, to: to, count: c["count"] as? Int) }
        default: break
        }
        let r = try s.execute(command: c)
        switch op {
        case "build":
            if case .some(let p) = buildPrediction { #expect(r.why == p, "build \(c)"); builds += 1 }
        case "recruit":
            if let n = c["count"] as? Int {
                let got = r.int("recruited") ?? 0
                let want = n >= 1 ? min(n, maxAffordable ?? 0) : 0
                #expect(got == want, "recruit \(c)")
                recruits += 1
            }
        case "transfer":
            if let p = predicted { #expect(r.ok == p.ok && r.why == p.why && r.int("moved") == p.count, "transfer \(c)"); transfers += 1 }
        default: break
        }
    }
    #expect(builds > 3 && recruits > 3 && transfers > 3)
}

/// Draw items by (object index, model) of a level, for comparisons.
private func keys(_ l: H4ObjectDrawList) -> [String] {
    l.items.map { "\($0.kind.rawValue) \($0.model) \($0.x),\($0.y) \($0.layerIndex) \($0.column.map(String.init) ?? "-") \($0.left),\($0.top)" }
}

@Test(.enabled(if: hasOracle))
func tierChangingBuildOverridesExactlyThatTown() throws {
    let w = try Wheel(map: "Wheel-of-Misfortune")
    let s = try w.session()
    let render = H4GameRender(store: w.store, tables: w.tables, models: H4ObjectModelLibrary(store: w.store))
    let region = H4MapTerrainRender.Region.whole(size: w.scenario.size)
    func list() throws -> H4ObjectDrawList { try render.drawList(objects: s.scenarioObjects, game: w.game, level: 0, region: region, state: s.renderState) }
    #expect(s.renderState.modelOverride.isEmpty)
    _ = try list()                                                                              // a fresh v2 session renders
    let cmds = try script("life")
    for c in cmds[0...14] { _ = try s.execute(command: c) }                                    // up to the refused builds
    let before = try list()
    #expect(s.renderState.modelOverride.isEmpty)                                               // nothing tier-changing so far
    let built = try s.execute(command: cmds[15])                                               // castle (5) in town 153
    #expect(built.ok)
    let model = try #require(s.townModel(town: 153))
    #expect(model.hasPrefix("castle.haven.castle"), "model \(model)")
    #expect(s.renderState.modelOverride == [153: model], "override \(s.renderState.modelOverride)")
    let after = try list()
    // exactly the items of object 153 change; they carry the derived model name
    let townObject = s.scenarioObjects[153]
    func isTown(_ i: H4ObjectDrawItem) -> Bool { i.x == Int(townObject.x) && i.y == Int(townObject.y) }
    func without(_ l: H4ObjectDrawList) -> H4ObjectDrawList { var o = H4ObjectDrawList(); o.items = l.items.filter { !isTown($0) }; return o }
    #expect(keys(without(before)) == keys(without(after)))
    #expect(after.items.contains { isTown($0) && $0.model == model } && !after.items.contains { isTown($0) && $0.kind != .flag && $0.model != model })
    #expect(before.items.contains { isTown($0) && $0.model != model })
    // a build that keeps the tier changes nothing: next day, tavern or a dwelling
    var pick: (town: Int, building: Int)?
    for _ in 0..<150 where pick == nil {
        _ = try s.execute(command: ["op": "endturn"])
        for t in s.towns where t.owner == s.currentPlayer && pick == nil {
            if let b = H4TownRules.gridBuildings(faction: t.faction).first(where: { ![3, 4, 5].contains($0) && s.buildStatus(town: t.index, building: $0) == nil }) {
                pick = (t.index, b)
            }
        }
    }
    let nt = try #require(pick, "no affordable non-tier building")
    let preList = try list(), preOverride = s.renderState.modelOverride
    #expect(try s.execute(command: ["op": "build", "town": nt.town, "building": nt.building]).ok)
    #expect(s.renderState.modelOverride == preOverride)
    #expect(keys(try list()) == keys(preList))
}

@Test(.enabled(if: hasOracle), arguments: factionRuns)
func townTerrainAndNamesAreAvailable(run: (String, String)) throws {
    let s = try Wheel(map: run.1).session()
    for t in s.towns {
        let id = s.townTerrain(town: t.index)
        #expect(H4TownRender.backgroundName(terrain: id) != nil, "town \(t.index) terrain \(id)")
        #expect(s.townModel(town: t.index) == t.model)
        for b in H4TownRules.gridBuildings(faction: t.faction) {
            #expect(!s.buildingName(faction: t.faction, building: b).isEmpty && s.buildingCost(faction: t.faction, building: b) != nil)
        }
        for b in 12...19 {
            let c = try #require(H4TownRules.dwellingCreature(faction: t.faction, building: b))
            #expect(!s.creatureName(c).isEmpty && !s.creatureName(c, plural: true).isEmpty && s.creatureCost(c) != nil)
        }
    }
}

@Test(.enabled(if: hasData))
func freshV2SessionHasNoOverrideAndRendersAs7c() throws {
    let host = try H4MovementSession(dataDirectory: URL(fileURLWithPath: env["H4_DATA_DIR"]!),
                                     mapsDirectory: URL(fileURLWithPath: env["H4_MAPS_DIR"]!), seed: 12345, difficulty: 2)
    let models = H4ObjectModelLibrary(store: host.store)
    let render = H4GameRender(store: host.store, tables: host.tables, models: models)
    var n = 0
    for name in host.mapNames {
        let files = try #require(host.mapFiles[name])
        let scenario = try H4Scenario(fileData: Data(contentsOf: URL(fileURLWithPath: files[0])))
        let game = try H4GameStart.start(scenario: scenario, store: host.store, tables: host.tables, seed: 12345, difficulty: 2)
        let s = try H4GameSession(game: game, scenario: scenario, resources: host.store, tables: host.tables, ruleset: .v2)
        #expect(s.renderState.modelOverride.isEmpty, "\(name)")
        // the whole level for the two Wheel maps, a window of 64x64 around each of the first three towns elsewhere (debug speed)
        var regions: [(Int, H4MapTerrainRender.Region)] = []
        if name.hasPrefix("Wheel-of-Misfortune") {
            for level in 0..<scenario.levels { regions.append((level, .whole(size: scenario.size))) }
        } else {
            for t in s.towns.prefix(3) {
                let o = s.scenarioObjects[t.index], side = min(64, scenario.size)
                regions.append((Int(o.level), .init(row: max(0, min(Int(o.x) - side / 2, scenario.size - side)),
                                                    column: max(0, min(Int(o.y) - side / 2, scenario.size - side)), rows: side, columns: side)))
            }
        }
        for (level, region) in regions {
            let a = try render.drawList(objects: s.scenarioObjects, game: game, level: level, region: region)
            let b = try render.drawList(objects: s.scenarioObjects, game: game, level: level, region: region, state: s.renderState)
            #expect(keys(a) == keys(b) && a.objectCount == b.objectCount && a.armyCount == b.armyCount, "\(name) level \(level)")
        }
        n += 1
    }
    #expect(n == 105)
}
