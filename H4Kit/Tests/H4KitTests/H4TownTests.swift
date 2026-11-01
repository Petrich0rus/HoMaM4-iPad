import Foundation
import Testing
@testable import H4Kit

// Slice 8a: towns, economy and building rules (reference `session2_ref.py`, rules R1-R6).
// Synthetic worlds exercise the rules without the game; data-gated tests read the game files and replay the frozen oracle.
//   H4_DATA_DIR, H4_MAPS_DIR     game folders
//   H4_TOWN_ORACLE_DIR           the oracle root (SCRATCH): step3/{buildings,session2}, step2/session

private let env = ProcessInfo.processInfo.environment
private let hasData = env["H4_DATA_DIR"] != nil
private let hasOracle = env["H4_DATA_DIR"] != nil && env["H4_MAPS_DIR"] != nil && env["H4_TOWN_ORACLE_DIR"] != nil

// MARK: - Synthetic world

/// 74 creatures: weekly growth 10 + id, cost id + 1 gold (creature 5 also costs 2 ore).
private func creatures() -> [H4GameTables.Creature] {
    (0..<74).map { id in
        H4GameTables.Creature(keyword: "c\(id)", level: 1, alignment: 0, experience: 1, expansion: 0, dwelling: "",
                              weeklyGrowth: 10 + id, cost: [id + 1, 0, id == 5 ? 2 : 0, 0, 0, 0, 0])
    }
}

/// Building costs: gold = 100 * id + faction, nothing else (building 8 and 11 have no row).
private func buildingCosts() -> H4BuildingTable {
    H4BuildingTable(costs: (0..<6).map { f in Dictionary(uniqueKeysWithValues: H4TownRules.keywords[f].keys.map { ($0, [100 * $0 + f, 0, 0, 0, 0, 0, 0]) }) })
}

private func tables() -> H4TownTables { H4TownTables(buildings: buildingCosts(), creatures: creatures()) }

private func town(_ index: Int, faction: Int, owner: Int = 0, mask: Int = 0x101, stock: [Int] = Array(repeating: 0, count: 8),
                  garrison: [H4SlotStack]? = nil, allowed: Int = (1 << 43) - 1) -> H4TownState {
    H4TownState(index: index, className: "town", faction: faction, right: false, owner: owner, mask: mask, allowed: allowed, builtToday: 0,
                stock: stock, garrison: garrison ?? Array(repeating: .empty, count: 7), visitingArmy: nil)
}

private func bag(_ gold: Int = 100_000, wood: Int = 100, ore: Int = 100, crystal: Int = 100, sulfur: Int = 100, mercury: Int = 100,
                 gem: Int = 100) -> H4SessionResources {
    H4SessionResources(amounts: [gold, wood, ore, crystal, sulfur, mercury, gem])
}

private func stacks(_ list: [(Int, Int)]) -> [H4SlotStack] {
    var row = list.map { H4SlotStack(creature: $0.0, count: $0.1) }
    while row.count < 7 { row.append(.empty) }
    return row
}

private func cmd(_ pairs: KeyValuePairs<String, Any>) -> [String: Any] { Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, $0.value) }) }

// MARK: - Tables

@Test func startingResourceRows() {
    // human team rows 0...4, computer team rows 5...9 (exe 0x98e9e8)
    #expect(H4Economy.startingResources(computerTeam: false, difficulty: 0) == [20000, 20, 20, 10, 10, 10, 10])
    #expect(H4Economy.startingResources(computerTeam: false, difficulty: 1) == [15000, 15, 15, 7, 7, 7, 7])
    #expect(H4Economy.startingResources(computerTeam: false, difficulty: 2) == [10000, 10, 10, 5, 5, 5, 5])
    #expect(H4Economy.startingResources(computerTeam: false, difficulty: 3) == [5000, 10, 10, 5, 5, 5, 5])
    #expect(H4Economy.startingResources(computerTeam: false, difficulty: 4) == [0, 10, 10, 5, 5, 5, 5])
    #expect(H4Economy.startingResources(computerTeam: true, difficulty: 0) == [0, 10, 10, 5, 5, 5, 5])
    #expect(H4Economy.startingResources(computerTeam: true, difficulty: 1) == [5000, 10, 10, 5, 5, 5, 5])
    #expect(H4Economy.startingResources(computerTeam: true, difficulty: 2) == [10000, 10, 10, 5, 5, 5, 5])
    #expect(H4Economy.startingResources(computerTeam: true, difficulty: 3) == [15000, 15, 15, 7, 7, 7, 7])
    #expect(H4Economy.startingResources(computerTeam: true, difficulty: 4) == [20000, 20, 20, 10, 10, 10, 10])
}

@Test func requirementTextsParse() {
    for f in 0..<6 {
        #expect(H4TownRules.requirements[f].count == H4TownRules.requirementText[f].count)
        #expect(H4TownRules.keywords[f].count == [30, 29, 29, 30, 30, 24][f])
    }
}

@Test func requirementsPerFaction() {
    // every faction: village hall nothing, town hall needs 0, fort needs 0, level-1 dwellings need the fort
    for f in 0..<6 {
        let r = H4TownRules.requirements[f]
        #expect(r[0] == .nothing && r[1] == .built(0) && r[2] == .built(1) && r[3] == .built(0) && r[12] == .built(3) && r[13] == .built(3))
    }
    // life 14 = fort AND tavern AND (12 OR 13) AND NOT 15 (buildings SPEC section 4)
    let life14 = H4TownRules.requirements[0][14]!
    #expect(life14 == .all([.built(3), .built(9), .any([.built(12), .built(13)]), .not(15)]))
    #expect(life14.satisfied(mask: 1 << 3 | 1 << 9 | 1 << 12, ignoreNot: false))
    #expect(!life14.satisfied(mask: 1 << 3 | 1 << 12, ignoreNot: true))                   // tavern missing
    // Order 19 needs the castle (5), Might 18 needs the castle
    #expect(H4TownRules.requirements[1][19] == .all([.built(5), .any([.built(17), .built(16)]), .not(18)]))
}

@Test func exclusivePairs() {
    // levels 2...4 of every faction: the two dwellings of a level exclude each other, and only through NOT
    for f in 0..<6 {
        for (a, b) in [(14, 15), (16, 17), (18, 19)] {
            for (me, partner) in [(a, b), (b, a)] {
                let tree = H4TownRules.requirements[f][me]!
                #expect(tree.contains(not: partner), "faction \(f) building \(me)")
                // everything built except the NOT node's partner counts as satisfied; with the partner built only the NOT fails
                let all = (1 << 43) - 1
                #expect(tree.satisfied(mask: all & ~(1 << partner), ignoreNot: false))
                #expect(tree.satisfied(mask: all, ignoreNot: true))
                #expect(!tree.satisfied(mask: all, ignoreNot: false))
            }
        }
    }
}

extension H4Requirement {
    func contains(not id: Int) -> Bool {
        switch self {
        case .not(let b): return b == id
        case .all(let l), .any(let l): return l.contains { $0.contains(not: id) }
        default: return false
        }
    }
}

@Test func staticSetsAndDwellings() {
    for f in 0..<6 {
        #expect(H4TownRules.isStaticBuildable(faction: f, building: 0 + 1))
        #expect(!H4TownRules.isStaticBuildable(faction: f, building: 8))               // prison
        #expect(!H4TownRules.isStaticBuildable(faction: f, building: 11))              // grail
        #expect(!H4TownRules.isStaticBuildable(faction: f, building: 43))
        #expect(!H4TownRules.isStaticBuildable(faction: f, building: -1))
        #expect(H4TownRules.dwellingCreature[f].count == 8)
    }
    #expect(!H4TownRules.isStaticBuildable(faction: 5, building: 20))                  // Might has no mage guild
    #expect(H4TownRules.isStaticBuildable(faction: 5, building: 40))                   // breeding pit
}

@Test func buildingTableParsesSectionsBySynthetic() throws {
    var d = Data([0, 0, 0, 0])
    func u16(_ v: Int) { d.append(UInt8(v & 255)); d.append(UInt8(v >> 8)) }
    func str(_ s: String) { u16(s.utf8.count); d.append(contentsOf: Array(s.utf8)) }
    let cols = ["Keyword", "FRENCH", "Gold", "Wood", "Ore", "Crystal", "Sulfur", "Mercury", "Gems", "Help Text"]
    u16(cols.count); cols.forEach(str)
    for (f, names) in H4TownRules.keywords.enumerated() {
        u16(10); ["", "Faction \(f)", "", "", "", "", "", "", "", ""].forEach(str)
        for id in names.keys.sorted() {
            u16(10)
            let c = [f * 1000 + id, id % 2 == 0 ? 0 : 3, 0, 0, 0, 0, 0].map { $0 == 0 ? "" : String($0) }
            ([names[id]!, "fr"] + c + ["help"]).forEach(str)
        }
        if f < 5 { u16(1); str("") }
    }
    let t = try H4BuildingTable(data: d)
    #expect(t.cost(faction: 3, building: 13) == [3013, 3, 0, 0, 0, 0, 0])
    #expect(t.cost(faction: 5, building: 40) == [5040, 0, 0, 0, 0, 0, 0])
    #expect(t.cost(faction: 0, building: 11) != nil)
    #expect(t.cost(faction: 5, building: 30) == nil)
}

// MARK: - Economy arithmetic (docstring examples)

@Test func growthArithmetic() {
    // weekly 21 creatures -> 14700 units, a day = 14700 // 7 = 2100
    #expect(H4Economy.initialStock(weeklyGrowth: 21) == 14700)
    #expect(H4Economy.dailyGrowth(bonus: 0, weeklyGrowth: 21) == 2100)
    #expect(H4Economy.dailyGrowth(bonus: 50, weeklyGrowth: 21) == 3150)               // breeding pit
    #expect(H4Economy.dailyGrowth(bonus: 100, weeklyGrowth: 21) == 4200)              // might grail
    #expect(H4Economy.dailyGrowth(bonus: 25, weeklyGrowth: 9) == (125 * 9 * 700 / 100) / 7)
    #expect(H4Economy.builtStock(weeklyGrowth: 21) == 7700)                            // ((21 + 1) * 700) // 2
    // bonus table: breeding pit 50, might grail 100 else 25 with another might grail town
    #expect(H4Economy.growthBonus(mask: 1 << 40, faction: 5, otherMightGrail: false) == 50)
    #expect(H4Economy.growthBonus(mask: 1 << 40 | 1 << 11, faction: 5, otherMightGrail: true) == 150)
    #expect(H4Economy.growthBonus(mask: 1 << 11, faction: 0, otherMightGrail: true) == 25)
    #expect(H4Economy.growthBonus(mask: 0, faction: 3, otherMightGrail: false) == 0)
    // hall gold: 500 / 750 / 1000, grail +3000
    #expect(H4Economy.townGold(mask: 0x101) == 500)
    #expect(H4Economy.townGold(mask: 0x103) == 750)
    #expect(H4Economy.townGold(mask: 0x107) == 1000)
    #expect(H4Economy.townGold(mask: 0x107 | 1 << 11) == 4000)
}

@Test func treasuryWorkedExample() {
    // R3b: 15000 gold, carry 0, one town hall: t = 52642; gold 15000 + 750 + 205, carry 162
    #expect(H4Economy.treasuryPending(gold: 15000, carry: 0) == 52642)
    var carry = 0
    #expect(H4Economy.payTreasury(carry: &carry, pending: 52642) == 205)
    #expect(carry == 162)
    #expect(H4Economy.treasuryPending(gold: 15955, carry: 162) == 55996)
    var c2 = 255
    #expect(H4Economy.payTreasury(carry: &c2, pending: 0) == 0 && c2 == 255)
    #expect(H4Economy.payTreasury(carry: &c2, pending: 1) == 1 && c2 == 0)
}

@Test func treasuryTwoDaysInAWorld() {
    var t = town(0, faction: 1, mask: 0x101 | 1 << 1 | 1 << 31)
    t.owner = 0
    var w = H4TownWorld(towns: [t], humanOf: [0: true], tables: tables())
    var res = [0: bag(15000, wood: 0, ore: 0, crystal: 0, sulfur: 0, mercury: 0, gem: 0)]
    w.dayTick(day: 1, resources: &res)
    #expect(res[0]!.gold == 15955 && w.carry[0] == 162)
    w.dayTick(day: 2, resources: &res)                                                 // t = 55996: +750, carry 162 + 55996 = 56158
    #expect(res[0]!.gold == 15955 + 750 + (56158 >> 8) && w.carry[0] == 56158 & 255)
}

@Test func computerBonusArithmetic() {
    // whole part only: income 1000 x (1.25 - 1) = 250 every day
    for d in 1...7 { #expect(H4Economy.computerBonus(income: 1000, multiplier: 1.25, resource: 0, day: d) == 250) }
    // fraction spread over 7 days: income 10 x 0.25 = 2.5 -> q = 2, t = 4; extra unit while (d - k + 6) % 7 < 4
    let days = (1...7).map { H4Economy.computerBonus(income: 10, multiplier: 1.25, resource: 0, day: $0) }
    #expect(days == [3, 3, 3, 3, 2, 2, 2])
    #expect((1...7).map { H4Economy.computerBonus(income: 10, multiplier: 1.25, resource: 1, day: $0) } == [2, 3, 3, 3, 3, 2, 2])
    // easy: 1000 x -0.25 = -250; income 10 x -0.25: q = -2, t = trunc(-3) = -3 -> never an extra unit
    #expect(H4Economy.computerBonus(income: 1000, multiplier: 0.75, resource: 0, day: 3) == -250)
    #expect((1...7).map { H4Economy.computerBonus(income: 10, multiplier: 0.75, resource: 0, day: $0) } == Array(repeating: -2, count: 7))
    #expect(H4Economy.computerBonus(income: 123, multiplier: 1.0, resource: 4, day: 5) == 0)
}

@Test func computerBonusClampsToStock() {
    // a computer player with a town (500 gold/day) on easy: -125 gold/day, never below 0
    var w = H4TownWorld(towns: [town(0, faction: 0, owner: 1)], humanOf: [0: true, 1: false], difficulty: 0, tables: tables())
    var res = [0: bag(0), 1: bag(100, wood: 0, ore: 0, crystal: 0, sulfur: 0, mercury: 0, gem: 0)]
    w.dayTick(day: 1, resources: &res)
    #expect(res[1]!.gold == 100 + 500 - 125 && res[0]!.gold == 0)
    var poor = [0: bag(0), 1: bag(0, wood: 0, ore: 0, crystal: 0, sulfur: 0, mercury: 0, gem: 0)]
    w.dayTick(day: 2, resources: &poor)
    #expect(poor[1]!.gold == 500 - 125)
}

@Test func mineGeneratorAndPeasants() {
    let mine = H4MineState(owner: 0, type: 3)
    let gen = H4GeneratorState(owner: 0, type: 2, potType: 2, pot: 10)
    let foreign = H4MineState(owner: 5, type: 0)                                       // owner is not a player: no income
    var w = H4TownWorld(towns: [town(0, faction: 0, owner: 0, garrison: stacks([(47, 30)]))], slots: [9: stacks([(47, 20), (3, 4)])],
                        armyOwner: [9: 0], mines: [1: mine, 2: foreign], gens: [3: gen], humanOf: [0: true], tables: tables())
    var res = [0: bag(0, wood: 0, ore: 0, crystal: 0, sulfur: 0, mercury: 0, gem: 0)]
    w.dayTick(day: 1, resources: &res)
    #expect(res[0]!.amounts == [500 + 50, 0, 10, 1, 0, 0, 0])                          // hall + 50 peasants, crystal mine, generator pays at once
    #expect(w.gens[3]!.counter == 7 && w.gens[3]!.pot == 10)
    for d in 2...7 { w.dayTick(day: d, resources: &res) }
    #expect(res[0]!.amounts[2] == 10 && w.gens[3]!.counter == 1)
    w.dayTick(day: 8, resources: &res)
    #expect(res[0]!.amounts[2] == 20 && w.gens[3]!.counter == 7)
}

@Test func dailyGrowthInAWorld() {
    var stock = Array(repeating: 0, count: 8)
    stock[0] = 100
    let t = town(0, faction: 0, mask: 0x101 | 1 << 12 | 1 << 40, stock: stock)       // life, dwelling 12 (creature 54: weekly 64 here), breeding pit
    var w = H4TownWorld(towns: [t, town(1, faction: 3, owner: 5)], humanOf: [0: true], tables: tables())
    var res = [0: bag()]
    w.dayTick(day: 1, resources: &res)
    #expect(w.towns[0]!.stock[0] == 100 + (150 * 64 * 700 / 100) / 7)
    #expect(w.towns[1]!.stock == Array(repeating: 0, count: 8))                        // neutral-ish owner 5: not a player
    #expect(w.towns[0]!.builtToday == 0)
}

// MARK: - Build (R4)

@Test func buildOrderOfChecks() {
    var w = H4TownWorld(towns: [town(0, faction: 0), town(1, faction: 1), town(2, faction: 2, owner: 1)], humanOf: [0: true, 1: false],
                        tables: tables())
    var res = [0: bag(), 1: bag()]
    func build(_ town: Any, _ id: Any) -> H4TownOp { w.build(cmd(["town": town, "building": id]), current: 0, resources: &res) }
    #expect(build(99, 3).why == "not-own-town")
    #expect(build(true, 3).why == "not-own-town")
    #expect(build("0", 3).why == "not-own-town")
    #expect(build(2, 3).why == "not-current-player")
    #expect(build(0, 43).why == "faction-static-set")
    #expect(build(0, 8).why == "faction-static-set")
    #expect(build(0, "fort").why == "faction-static-set")
    #expect(build(0, true).why == "faction-static-set")
    #expect(build(0, 0).why == "already-built")
    // requirements in LIFE and ORDER (coverage gap of the frozen logs): dwelling 12 without a fort
    #expect(build(0, 12).why == "requirements")
    #expect(build(1, 12).why == "requirements")
    #expect(build(0, 2).why == "requirements")                                         // city hall needs the town hall
    #expect(build(1, 31).why == "requirements")                                        // Order treasury needs town hall and fort
    // success, then one building per day
    let ok = build(0, 3)
    #expect(ok.ok && w.towns[0]!.mask & 8 != 0 && w.towns[0]!.builtToday == 1)
    #expect(res[0]!.gold == 100_000 - 300)                                             // cost 100 * 3 + faction 0
    #expect(build(0, 12).why == "built-today")
    var r2 = res
    w.dayTick(day: 1, resources: &r2)
    res = r2
    #expect(w.towns[0]!.builtToday == 0)
    #expect(build(0, 12).ok)
    #expect(w.towns[0]!.stock[0] == (64 + 1) * 700 / 2)                                // built in game: ((growth + 1) * 700) // 2
    #expect(build(0, 12).why == "already-built")
}

@Test func buildAllowedExclusiveAndResources() {
    // life town with fort, tavern, dwelling 12 and the stables; dwellings 14 / 15 exclude each other
    let m = 0x101 | 1 << 3 | 1 << 9 | 1 << 12 | 1 << 13
    var w = H4TownWorld(towns: [town(0, faction: 0, mask: m, allowed: ((1 << 43) - 1) & ~(1 << 15))], humanOf: [0: true], tables: tables())
    var res = [0: bag()]
    func build(_ id: Int) -> H4TownOp { w.build(cmd(["town": 0, "building": id]), current: 0, resources: &res) }
    #expect(build(15).why == "not-allowed")
    #expect(build(14).ok)
    w.towns[0]!.builtToday = 0
    w.towns[0]!.allowed = (1 << 43) - 1
    #expect(build(15).why == "exclusive-partner")
    res[0]!.amounts[0] = 5
    #expect(build(1).why == "resources")
    #expect(res[0]!.gold == 5)
}

// MARK: - Recruit (R5)

@Test func recruitLimitsAndRefusals() {
    var stock = Array(repeating: 0, count: 8)
    stock[0] = 700 * 7 + 699
    let t = town(0, faction: 0, mask: 0x101 | 1 << 12, stock: stock)
    var w = H4TownWorld(towns: [t], humanOf: [0: true], tables: tables())
    var res = [0: bag(1_000)]
    func rec(_ b: Any, _ n: Any) -> H4TownOp { w.recruit(cmd(["town": 0, "building": b, "count": n]), current: 0, resources: &res) }
    #expect(rec(12, 0).why == "bad-count" && rec(12, -3).why == "bad-count" && rec(12, "2").why == "bad-count" && rec(12, true).why == "bad-count")
    #expect(rec(13, 1).why == "no-dwelling" && rec(3, 1).why == "no-dwelling" && rec(20, 1).why == "no-dwelling")
    // creature 54 costs 55 gold: 1000 gold allow 18, stock allows 7: min(100, 7, 18)
    let a = rec(12, 100)
    #expect(a.ok && a.count == 7 && res[0]!.gold == 1000 - 7 * 55 && w.towns[0]!.stock[0] == 699)
    #expect(w.towns[0]!.garrison[0] == H4SlotStack(creature: 54, count: 7))
    #expect(rec(12, 1).why == "none-available")
    w.towns[0]!.stock[0] = 700 * 50
    res[0]!.amounts[0] = 120                                                          // resources: 120 // 55 = 2
    let b = rec(12, 10)
    #expect(b.count == 2 && w.towns[0]!.garrison[0].count == 9 && res[0]!.gold == 10)
    res[0]!.amounts[0] = 54
    #expect(rec(12, 1).why == "resources" && rec(12, 1).count == 0)
    // a refusal leaves the state alone
    #expect(w.towns[0]!.stock[0] == 700 * 50 - 1400)
}

@Test func recruitGarrisonFull() {
    var stock = Array(repeating: 0, count: 8)
    stock[0] = 700 * 4
    // seven other creatures (a hero slot counts as occupied)
    let full = Array(stacks([(1, 1), (2, 1), (3, 1), (4, 1), (5, 1), (6, 1)]).prefix(6)) + [H4SlotStack.hero]
    var w = H4TownWorld(towns: [town(0, faction: 0, mask: 0x101 | 1 << 12, stock: stock, garrison: full)], humanOf: [0: true],
                        tables: tables())
    var res = [0: bag()]
    func rec() -> H4TownOp { w.recruit(cmd(["town": 0, "building": 12, "count": 1]), current: 0, resources: &res) }
    #expect(rec().why == "garrison-full")
    #expect(res[0]!.gold == 100_000 && w.towns[0]!.stock[0] == 2800)
    // merging into the creature's own stack needs no free slot
    w.towns[0]!.garrison[2] = H4SlotStack(creature: 54, count: 3)
    #expect(rec().ok && w.towns[0]!.garrison[2].count == 4)
}

// MARK: - Transfer (R5)

private func transferWorld(faction: Int = 0) -> (H4TownWorld, [Int: H4SessionResources]) {
    var t = town(0, faction: faction, garrison: stacks([(10, 5), (11, 3)]))
    t.visitingArmy = 7
    let w = H4TownWorld(towns: [t, town(1, faction: faction), town(2, faction: faction, owner: 1)],
                        slots: [7: [.hero, H4SlotStack(creature: 10, count: 4), H4SlotStack(creature: 12, count: 6), .empty, .empty, .empty, .empty],
                                8: stacks([(10, 1)]), 9: stacks([(10, 1)])],
                        armyOwner: [7: 0, 8: 0, 9: 1], humanOf: [0: true, 1: false], tables: tables())
    return (w, [0: bag(), 1: bag()])
}

private func addr(_ kind: String, _ id: Any, _ slot: Any? = nil) -> [String: Any] {
    var d: [String: Any] = [kind: id]
    if let slot { d["slot"] = slot }
    return d
}

@Test func transferCheckOrder() {
    var (w, _) = transferWorld()
    func tr(_ from: Any?, _ to: Any?, _ count: Any? = nil) -> H4TownOp {
        var c: [String: Any] = [:]
        if let from { c["from"] = from }
        if let to { c["to"] = to }
        if let count { c["count"] = count }
        return w.transfer(c, current: 0)
    }
    #expect(tr(nil, addr("town", 0)).why == "bad-container")
    #expect(tr(addr("town", 77, 0), addr("town", 0)).why == "bad-container")
    #expect(tr(addr("army", 99, 0), addr("town", 0)).why == "bad-container")
    #expect(tr(addr("town", 0), addr("town", 1)).why == "bad-slot")                    // slot missing in `from`
    #expect(tr(addr("town", 0, 7), addr("town", 1)).why == "bad-slot")
    #expect(tr(addr("town", 0, true), addr("town", 1)).why == "bad-slot")
    // coverage gap: slot 9 in `from` and an unknown army in `to`: `from` is read first
    #expect(tr(addr("town", 0, 9), addr("army", 4242)).why == "bad-slot")
    #expect(tr(addr("town", 0, 0), addr("army", 4242)).why == "bad-container")
    #expect(tr(addr("town", 0, 0), addr("town", 1, 9)).why == "bad-slot")
    #expect(tr(addr("town", 0, 0), addr("town", 2)).why == "not-own")
    #expect(tr(addr("army", 9, 0), addr("town", 0)).why == "not-own")
    #expect(tr(addr("town", 0, 0), addr("town", 1)).why == "not-visiting")             // two towns
    #expect(tr(addr("army", 7, 1), addr("army", 8)).why == "not-visiting")             // two armies
    #expect(tr(addr("army", 8, 0), addr("town", 0)).why == "not-visiting")             // army 8 does not visit town 0
    #expect(tr(addr("town", 0, 5), addr("army", 7)).why == "empty-source")
    #expect(tr(addr("army", 7, 0), addr("town", 0)).why == "hero-slot")
    #expect(tr(addr("town", 0, 0), addr("army", 7, 0)).why == "hero-slot")
    #expect(tr(addr("town", 0, 0), addr("town", 0, 1), 6).why == "bad-count")
    #expect(tr(addr("town", 0, 0), addr("town", 0, 1), 0).why == "bad-count")
    #expect(tr(addr("town", 0, 0), addr("town", 0, 1), 1.5 as Double).why == "bad-count")
    #expect(tr(addr("town", 0, 0), addr("town", 0, 0)).why == "same-slot")
    #expect(tr(addr("town", 0, 0), addr("town", 0, 1), 2).why == "slot-occupied")      // other creature, partial
}

@Test func transferMovesMergesSwaps() {
    var (w, _) = transferWorld()
    func tr(_ from: [String: Any], _ to: [String: Any], _ count: Int? = nil) -> H4TownOp {
        var c: [String: Any] = ["from": from, "to": to]
        if let count { c["count"] = count }
        return w.transfer(c, current: 0)
    }
    // auto target merges into the creature's stack of the army (slot 1, creature 10)
    let a = tr(addr("town", 0, 0), addr("army", 7), 2)
    #expect(a.ok && a.count == 2 && w.slots[7]![1] == H4SlotStack(creature: 10, count: 6) && w.towns[0]!.garrison[0].count == 3)
    // whole stack to an empty explicit slot
    let b = tr(addr("army", 7, 2), addr("town", 0, 4))
    #expect(b.ok && b.count == 6 && w.slots[7]![2] == .empty && w.towns[0]!.garrison[4] == H4SlotStack(creature: 12, count: 6))
    // swap of whole stacks in the garrison
    let c = tr(addr("town", 0, 0), addr("town", 0, 1))
    #expect(c.ok && c.count == 3 && w.towns[0]!.garrison[0] == H4SlotStack(creature: 11, count: 3) && w.towns[0]!.garrison[1] == H4SlotStack(creature: 10, count: 3))
    // auto target without a free slot: garrison-full (outside chaos and nature)
    w.towns[0]!.garrison = stacks([(20, 1), (21, 1), (22, 1), (23, 1), (24, 1), (25, 1), (26, 1)])
    #expect(tr(addr("army", 7, 1), addr("town", 0)).why == "garrison-full")
    #expect(w.slots[7]![1] == H4SlotStack(creature: 10, count: 6))
    // moving into another slot of the same container: empty target
    w.slots[7]![3] = .empty
    let d = tr(addr("army", 7, 1), addr("army", 7, 3), 2)
    #expect(d.ok && w.slots[7]![1].count == 4 && w.slots[7]![3] == H4SlotStack(creature: 10, count: 2))
    // auto inside one container merges with another stack of the creature, never with the source
    let e = tr(addr("army", 7, 3), addr("army", 7))
    #expect(e.ok && w.slots[7]![1].count == 6 && w.slots[7]![3] == .empty)
}

@Test func transferGarrisonFullInEveryFaction() {
    for f in 0..<6 {
        var (w, _) = transferWorld(faction: f)
        w.towns[0]!.garrison = stacks([(20, 1), (21, 1), (22, 1), (23, 1), (24, 1), (25, 1), (26, 1)])
        let r = w.transfer(cmd(["from": addr("army", 7, 1), "to": addr("town", 0)]), current: 0)
        #expect(r.ok == false && r.why == "garrison-full" && r.count == 0, "faction \(f)")
    }
}

// MARK: - Session v2 (synthetic)

@Test func rulesetDefaultsAndLog() throws {
    // a synthetic session is v1: town commands are unknown ops and the record has no town fields
    let s = H4GameSession(players: [(colour: 0, human: true)], objects: [], levels: 1, artifactIDByModel: [:],
                          world: { _, placed in H4MoveWorld(size: 4, rows: Array(repeating: 0..<4, count: 4), cell: { _, _ in (1, 0, 0) }, placed: placed) })
    #expect(s.ruleset == .v1 && s.towns.isEmpty)
    let log = try s.runScript(Data(#"[{"op":"state"}]"#.utf8))
    #expect(!log.contains("towns") && log.contains("\"resources\":{\"0\":{\"crystal\":0"))
    #expect(throws: Error.self) { try s.runScript(Data(#"[{"op":"build","town":0,"building":3}]"#.utf8)) }
}

// MARK: - Game data (gated)

@Test(.enabled(if: hasData)) func buildingTableCostsMatchCsv() throws {
    let store = try H4ResourceStore(dataDirectory: URL(fileURLWithPath: env["H4_DATA_DIR"]!))
    let table = try H4BuildingTable(store: store)
    let tables = try H4GameTables(store: store)
    // the table has a real cost for the town hall of life (2500 gold, 10 wood, 10 ore) and the creature columns are read
    #expect(table.cost(faction: 0, building: 1) == [2500, 10, 10, 0, 0, 0, 0])
    #expect(tables.creatures[54].weeklyGrowth == 21 && tables.creatures[54].cost == [26, 0, 0, 0, 0, 0, 0])
    guard let root = env["H4_TOWN_ORACLE_DIR"] else { return }
    let rows = try csvRows(root + "/step3/buildings/buildings.csv")
    let head = rows[0]
    let col = { (n: String) in head.firstIndex(of: n)! }
    var n = 0
    for r in rows.dropFirst() where r.count == head.count {
        let f = H4TownRules.factions.firstIndex(of: r[col("faction")])!
        let id = Int(r[col("id")])!
        let expected = ["gold", "wood", "ore", "crystal", "sulfur", "mercury", "gems"].map { Int(r[col($0)]) ?? 0 }
        #expect(table.cost(faction: f, building: id) == expected, "faction \(f) building \(id)")
        n += 1
    }
    #expect(n == 172)
    // dwelling creatures, growth and costs against town_dwellings.csv
    let dw = try csvRows(root + "/step3/economy/town_dwellings.csv")
    let dh = dw[0]
    var m = 0
    for r in dw.dropFirst() where r.count == dh.count {
        let f = Int(r[dh.firstIndex(of: "faction_idx")!])!, bit = Int(r[dh.firstIndex(of: "bit")!])!
        let c = tables.creatures[H4TownRules.dwellingCreature[f][bit - 12]]
        #expect(c.weeklyGrowth == Int(r[dh.firstIndex(of: "weekly_growth")!])!)
        #expect(c.cost == ["gold", "wood", "ore", "crystal", "sulfur", "mercury", "gems"].map { Int(r[dh.firstIndex(of: $0)!]) ?? 0 })
        m += 1
    }
    #expect(m == 48)
}

private func csvRows(_ path: String) throws -> [[String]] {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
    for ch in text {
        if quoted {
            if ch == "\"" { quoted = false } else { field.append(ch) }
        } else if ch == "\"" { quoted = true
        } else if ch == "," { row.append(field); field = ""
        } else if ch == "\n" || ch == "\r\n" { row.append(field); field = ""; rows.append(row); row = []
        } else { field.append(ch) }
    }
    if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
    return rows
}

/// (map, script, log, ruleset) of the frozen oracle.
private let oracleRuns: [(String, String, String, H4Ruleset)] = [
    ("Wheel-of-Misfortune", "step3/session2/scripts/town_life.json", "step3/session2/logs/town_life.json", .v2),
    ("Wheel-of-Misfortune_(Allied)", "step3/session2/scripts/town_order.json", "step3/session2/logs/town_order.json", .v2),
    ("Wheel-of-Misfortune", "step3/session2/scripts/town_death.json", "step3/session2/logs/town_death.json", .v2),
    ("Wheel-of-Misfortune_(Allied)", "step3/session2/scripts/town_chaos.json", "step3/session2/logs/town_chaos.json", .v2),
    ("Wheel-of-Misfortune", "step3/session2/scripts/town_nature.json", "step3/session2/logs/town_nature.json", .v2),
    ("Wheel-of-Misfortune_(Allied)", "step3/session2/scripts/town_might.json", "step3/session2/logs/town_might.json", .v2),
    ("The_Four_Horsemen", "step3/session2/scripts/econ_horsemen.json", "step3/session2/logs/econ_horsemen.json", .v2),
    ("Peasants_Revolt", "step3/session2/scripts/econ_peasants.json", "step3/session2/logs/econ_peasants.json", .v2),
    ("Nature's_Revenge", "step3/session2/scripts/econ_nature.json", "step3/session2/logs/econ_nature.json", .v2),
    ("Ancestral_Home", "step2/session/scripts/s1.json", "step3/session2/logs_v2step2/s1.json", .v2),
    ("Dannte", "step2/session/scripts/s2.json", "step3/session2/logs_v2step2/s2.json", .v2),
    ("Heart_of_Winter", "step2/session/scripts/s3.json", "step3/session2/logs_v2step2/s3.json", .v2),
    ("Bandits_of_the_Rifen_Maze", "step2/session/scripts/s4.json", "step3/session2/logs_v2step2/s4.json", .v2),
    ("Land_of_the_Lamp", "step2/session/scripts/s5.json", "step3/session2/logs_v2step2/s5.json", .v2),
    ("Ancestral_Home", "step2/session/scripts/s1.json", "step2/session/logs/s1.json", .v1),
    ("Dannte", "step2/session/scripts/s2.json", "step2/session/logs/s2.json", .v1),
]

@Test(.enabled(if: hasOracle), arguments: oracleRuns) func replaysFrozenLogs(run: (String, String, String, H4Ruleset)) throws {
    let root = env["H4_TOWN_ORACLE_DIR"]!
    let host = try H4MovementSession(dataDirectory: URL(fileURLWithPath: env["H4_DATA_DIR"]!),
                                     mapsDirectory: URL(fileURLWithPath: env["H4_MAPS_DIR"]!), seed: 12345, difficulty: 2)
    let files = try #require(host.mapFiles[run.0])
    let scenario = try H4Scenario(fileData: Data(contentsOf: URL(fileURLWithPath: files[0])))
    let game = try H4GameStart.start(scenario: scenario, store: host.store, tables: host.tables, seed: 12345, difficulty: 2)
    let session = try H4GameSession(game: game, scenario: scenario, resources: host.store, tables: host.tables, ruleset: run.3)
    let log = try session.runScript(Data(contentsOf: URL(fileURLWithPath: root + "/" + run.1)))
    let expected = try String(contentsOfFile: root + "/" + run.2, encoding: .utf8)
    #expect(log == expected, "\(run.1)")
}
