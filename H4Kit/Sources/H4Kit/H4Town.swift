import Foundation

// Slice 8a — towns of a started game: state, building rules, recruiting, army transfers and the day tick.
//
// Rules R2-R5 of the frozen reference `session2_ref.py` (the economy arithmetic is in `H4GameEconomy`). Tags: [D] decoded from
// heroes4.exe (GOG 1.3, addresses = VA), [V] validated on the data, [I] inferred / pinned by the reference. The numeric and rule
// tables below exist only in the executable; building costs, creature growth and creature costs are read from the game's tables.

/// Which rules a session plays: `v1` = the frozen 7d-L session (no towns, no economy), `v2` = slice 8a.
public enum H4Ruleset: String, Sendable { case v1, v2 }

/// A requirement tree of a building [D 0xacfbe0].
indirect enum H4Requirement: Equatable {
    case nothing
    case built(Int)
    case not(Int)
    case all([H4Requirement])
    case any([H4Requirement])

    /// `ignoreNot`: every NOT node counts as satisfied (the reference's first requirement pass).
    func satisfied(mask: Int, ignoreNot: Bool) -> Bool {
        switch self {
        case .nothing: return true
        case .built(let b): return mask >> b & 1 != 0
        case .not(let b): return ignoreNot ? true : mask >> b & 1 == 0
        case .all(let l): return l.allSatisfy { $0.satisfied(mask: mask, ignoreNot: ignoreNot) }
        case .any(let l): return l.contains { $0.satisfied(mask: mask, ignoreNot: ignoreNot) }
        }
    }

    /// Parses the compact text of `H4TownRules.requirementText`.
    static func parse(_ text: String) -> H4Requirement? {
        let c = Array(text.utf8)
        var p = 0
        func number() -> Int? {
            let s = p
            while p < c.count, c[p] >= 48, c[p] <= 57 { p += 1 }
            return p > s ? Int(String(decoding: c[s..<p], as: UTF8.self)) : nil
        }
        func node() -> H4Requirement? {
            guard p < c.count else { return nil }
            let k = c[p]; p += 1
            switch k {
            case UInt8(ascii: "T"): return .nothing
            case UInt8(ascii: "B"): return number().map { .built($0) }
            case UInt8(ascii: "N"): return number().map { .not($0) }
            case UInt8(ascii: "A"), UInt8(ascii: "O"):
                guard p < c.count, c[p] == UInt8(ascii: "(") else { return nil }
                p += 1
                var kids: [H4Requirement] = []
                while true {
                    guard let n = node() else { return nil }
                    kids.append(n)
                    guard p < c.count else { return nil }
                    let d = c[p]; p += 1
                    if d == UInt8(ascii: ")") { break }
                    guard d == UInt8(ascii: ",") else { return nil }
                }
                return k == UInt8(ascii: "A") ? .all(kids) : .any(kids)
            default: return nil
            }
        }
        guard let r = node(), p == c.count else { return nil }
        return r
    }
}

/// Executable tables of the town rules (R2, R4, R5) and the model naming.
public enum H4TownRules {
    public static let factionCount = 6
    /// Faction names of the scenario subclasses, index = faction (life, order, death, chaos, nature, might).
    public static let factions = H4GameIdentifiers.alignmentNames
    /// Bits of the 43-bit building sets.
    public static let buildingCount = 43

    // [D] exe 0x97dcf8 (common, ids 0...11), 0x97dd58 life, 0x97dde8 order, 0x97de70 death, 0x97def8 chaos, 0x97df88 nature, 0x97e018 might:
    // building id -> keyword of table.buildings (identifier names only); index = faction.
    static let keywords: [[Int: String]] = [
        [
            0: "village hall", 1: "town hall", 2: "city hall", 3: "fort", 4: "citadel", 5: "castle", 6: "shipyard", 7: "caravan",
            8: "prison", 9: "tavern", 10: "blacksmith", 11: "grail", 12: "squire guild", 13: "archery range", 14: "guardhouse",
            15: "ballista works", 16: "barracks", 17: "monastary", 18: "knight chapter", 19: "altar of light",
            20: "mage guild 1", 21: "mage guild 2", 22: "mage guild 3", 23: "mage guild 4", 24: "mage guild 5",
            25: "nature library", 26: "order library", 27: "seminary", 28: "stables", 29: "abbey"
        ],
        [
            0: "village hall", 1: "town hall", 2: "city hall", 3: "fort", 4: "citadel", 5: "castle", 6: "shipyard", 7: "caravan",
            8: "prison", 9: "tavern", 10: "blacksmith", 11: "grail", 12: "dwarven mines", 13: "halfling burrow",
            14: "golem factory", 15: "mage tower", 16: "golden pavilion", 17: "altar of wishes", 18: "dragon factory",
            19: "cloud castle", 20: "mage guild 1", 21: "mage guild 2", 22: "mage guild 3", 23: "mage guild 4",
            24: "mage guild 5", 25: "life library", 26: "death library", 30: "university", 31: "treasury"
        ],
        [
            0: "village hall", 1: "town hall", 2: "city hall", 3: "fort", 4: "citadel", 5: "castle", 6: "shipyard", 7: "caravan",
            8: "prison", 9: "tavern", 10: "blacksmith", 11: "grail", 12: "cemetery", 13: "torture chamber", 14: "barrow mound",
            15: "kennels", 16: "mansion", 17: "spawn pit", 18: "dragon graveyard", 19: "temple of the damned",
            20: "mage guild 1", 21: "mage guild 2", 22: "mage guild 3", 23: "mage guild 4", 24: "mage guild 5",
            25: "order library", 26: "chaos library", 32: "skeleton transformer", 33: "necromancy amplifier"
        ],
        [
            0: "village hall", 1: "town hall", 2: "city hall", 3: "fort", 4: "citadel", 5: "castle", 6: "shipyard", 7: "caravan",
            8: "prison", 9: "tavern", 10: "blacksmith", 11: "grail", 12: "bandit gen", 13: "orc camp", 14: "statuary garden",
            15: "labyrinth", 16: "nightmare", 17: "lava tube", 18: "hydra pond", 19: "dragon cave", 20: "mage guild 1",
            21: "mage guild 2", 22: "mage guild 3", 23: "mage guild 4", 24: "mage guild 5", 25: "death library",
            26: "nature library", 34: "academy", 35: "training grounds", 36: "mana vortex"
        ],
        [
            0: "village hall", 1: "town hall", 2: "city hall", 3: "fort", 4: "citadel", 5: "castle", 6: "shipyard", 7: "caravan",
            8: "prison", 9: "tavern", 10: "blacksmith", 11: "grail", 12: "wolf den", 13: "fae trees", 14: "tiger den",
            15: "homestead", 16: "griffin cliffs", 17: "unicorn glade", 18: "funeral pyre", 19: "magic forest",
            20: "mage guild 1", 21: "mage guild 2", 22: "mage guild 3", 23: "mage guild 4", 24: "mage guild 5",
            25: "chaos library", 26: "life library", 37: "creature portal", 38: "rainbow", 39: "grove"
        ],
        [
            0: "village hall", 1: "town hall", 2: "city hall", 3: "fort", 4: "citadel", 5: "castle", 6: "shipyard", 7: "caravan",
            8: "prison", 9: "tavern", 10: "blacksmith", 11: "grail", 12: "berserker", 13: "centaur stables", 14: "nomad camp",
            15: "harpy nest", 16: "ogre fort", 17: "cyclops cave", 18: "cliff nest", 19: "behemoth crag", 35: "training grounds",
            40: "breeding pit", 41: "magic dampener", 42: "arena"
        ],
    ]

    // [D] exe 0xacfbe0 (t_requires tree per faction and building id, built by 0x8934b0): encoding T = nothing, Bn = building n, Nn = NOT n,
    // A(...) = AND, O(...) = OR. Index = faction (life, order, death, chaos, nature, might).
    static let requirementText: [[Int: String]] = [
        [
            0: "T", 1: "B0", 2: "B1", 3: "B0", 4: "B3", 5: "B4", 6: "B3", 7: "B3", 9: "B0", 10: "B0", 12: "B3", 13: "B3",
            14: "A(B3,B9,O(B12,B13),N15)", 15: "A(B3,B13,N14)", 16: "A(B3,B10,O(B14,B15),N17)", 17: "A(B3,B29,O(B14,B15),N16)",
            18: "A(B3,B28,B10,O(B17,B16),N19)", 19: "A(B3,B27,O(B17,B16),N18)", 20: "B0", 21: "B20", 22: "B21", 23: "B22",
            24: "B23", 25: "B20", 26: "B20", 27: "B29", 28: "B0", 29: "B3"
        ],
        [
            0: "T", 1: "B0", 2: "B1", 3: "B0", 4: "B3", 5: "B4", 6: "B3", 7: "B3", 9: "B0", 10: "B0", 12: "B3", 13: "B3",
            14: "A(B3,B20,O(B12,B13),N15)", 15: "A(B3,B20,O(B12,B13),N14)", 16: "A(B3,B31,O(B15,B14),N17)",
            17: "A(B3,B25,O(B15,B14),N16)", 18: "A(B3,B10,B30,O(B17,B16),N19)", 19: "A(B5,O(B17,B16),N18)", 20: "B0", 21: "B20",
            22: "B21", 23: "B22", 24: "B23", 25: "B20", 26: "B20", 30: "B3", 31: "A(B1,B3)"
        ],
        [
            0: "T", 1: "B0", 2: "B1", 3: "B0", 4: "B3", 5: "B4", 6: "B3", 7: "B3", 9: "B0", 10: "B0", 12: "B3", 13: "B3",
            14: "A(B3,B32,O(B12,B13),N15)", 15: "A(B3,B13,N14)", 16: "A(B3,B9,O(B14,B15),N17)", 17: "A(B3,B20,O(B14,B15),N16)",
            18: "A(B3,B33,O(B16,B17),N19)", 19: "A(B3,B26,O(B16,B17),N18)", 20: "B0", 21: "B20", 22: "B21", 23: "B22", 24: "B23",
            25: "B20", 26: "B20", 32: "B12", 33: "A(B3,B20)"
        ],
        [
            0: "T", 1: "B0", 2: "B1", 3: "B0", 4: "B3", 5: "B4", 6: "B3", 7: "B3", 9: "B0", 10: "B0", 12: "B3", 13: "B3",
            14: "A(B3,B20,O(B12,B13),N15)", 15: "A(B3,B35,O(B12,B13),N14)", 16: "A(B3,B7,O(B14,B15),N17)",
            17: "A(B3,B10,O(B14,B15),N16)", 18: "A(B3,B26,O(B16,B17),N19)", 19: "A(B3,B25,O(B16,B17),N18)", 20: "B0", 21: "B20",
            22: "B21", 23: "B22", 24: "B23", 25: "B20", 26: "B20", 34: "B3", 35: "B3", 36: "B21"
        ],
        [
            0: "T", 1: "B0", 2: "B1", 3: "B0", 4: "B3", 5: "B4", 6: "B3", 7: "B3", 9: "B0", 10: "B0", 12: "B3", 13: "B3",
            14: "A(B3,B39,O(B12,B13),N15)", 15: "A(B3,B10,O(B12,B13),N14)", 16: "A(B3,B4,O(B14,B15),N17)",
            17: "A(B3,B38,O(B14,B15),N16)", 18: "A(B3,B37,O(B17,B16),N19)", 19: "A(B3,B25,O(B17,B16),N18)", 20: "B0", 21: "B20",
            22: "B21", 23: "B22", 24: "B23", 25: "B20", 26: "B20", 37: "A(B20,O(B17,B16))", 38: "B0", 39: "B0"
        ],
        [
            0: "T", 1: "B0", 2: "B1", 3: "B0", 4: "B3", 5: "B4", 6: "B3", 7: "B3", 9: "B0", 10: "B0", 12: "B3", 13: "B3",
            14: "A(B3,B7,O(B12,B13),N15)", 15: "A(B3,B4,O(B12,B13),N14)", 16: "A(B3,B9,O(B14,B15),N17)",
            17: "A(B3,B35,O(B14,B15),N16)", 18: "A(B5,O(B16,B17),N19)", 19: "A(B3,B42,B10,O(B16,B17),N18)", 35: "B0",
            40: "O(B16,B17)", 41: "B3", 42: "B3"
        ],
    ]

    // [D] exe 0xacfbb0: per faction the 43-bit set of buildings buildable at all (low dword, high dword).
    static let staticBuildable: [(lo: UInt32, hi: UInt32)] = [
        (1073739519, 0),
        (3355440895, 0),
        (134215423, 3),
        (134215423, 28),
        (134215423, 224),
        (1046271, 1800),
    ]
    // [D] exe 0x9853d0 (loader 0x656120): creature id of dwelling building 12...19 per faction.
    static let dwellingCreature: [[Int]] = [
        [54, 11, 49, 2, 12, 40, 10, 1],
        [17, 29, 27, 35, 42, 24, 16, 57],
        [53, 33, 25, 9, 61, 14, 7, 15],
        [3, 46, 37, 39, 43, 19, 31, 6],
        [64, 55, 63, 20, 28, 60, 48, 21],
        [26, 8, 44, 30, 45, 13, 56, 4],
    ]

    /// Requirement trees, parsed once.
    static let requirements: [[Int: H4Requirement]] = requirementText.map { $0.compactMapValues(H4Requirement.parse) }

    /// Whether the bit of building `id` is in the static buildable set of the faction [D 0x894090].
    public static func isStaticBuildable(faction: Int, building id: Int) -> Bool {
        guard (0..<buildingCount).contains(id) else { return false }
        let s = staticBuildable[faction]
        return (Int(s.lo) | Int(s.hi) << 32) >> id & 1 != 0
    }

    /// Ids shown in the build grid of a faction: the buildings of its static set, ascending (slice 8c).
    public static func gridBuildings(faction: Int) -> [Int] {
        (0..<buildingCount).filter { isStaticBuildable(faction: faction, building: $0) }
    }

    /// Creature id of dwelling building 12...19 of a faction, nil for any other id.
    public static func dwellingCreature(faction: Int, building id: Int) -> Int? {
        (12...19).contains(id) && dwellingCreature.indices.contains(faction) ? dwellingCreature[faction][id - 12] : nil
    }

    /// Tier of the adventure-map model [D 0x415e40]: castle 3, citadel 2, fort 1, village 0.
    public static func tier(mask: Int) -> Int { mask >> 5 & 1 != 0 ? 3 : mask >> 4 & 1 != 0 ? 2 : mask >> 3 & 1 != 0 ? 1 : 0 }

    /// Adventure-map model of a town: `castle.<haven|...>.<village|...>[ R]`.
    public static func modelName(faction: Int, mask: Int, right: Bool) -> String {
        "castle.\(H4GameIdentifiers.factionNames[faction]).\(H4GameIdentifiers.tierNames[tier(mask: mask)])\(right ? " R" : "")"
    }
}

/// A slot of an army or of a garrison: creature id and count; `-1` = empty, `-2` = hero slot (immovable).
public struct H4SlotStack: Sendable, Equatable {
    public var creature: Int
    public var count: Int
    public static let empty = H4SlotStack(creature: -1, count: 0)
    public static let hero = H4SlotStack(creature: -2, count: 0)
    var json: H4LogJSON { .arr([.int(creature), .int(count)]) }
}

/// What the town rules read from the game's own tables.
public struct H4TownTables: Sendable {
    public let buildings: H4BuildingTable
    public let creatures: [H4GameTables.Creature]
    /// Display names of the creatures (singular, plural), index = creature id; empty in synthetic tables.
    public private(set) var creatureNames: [String] = []
    public private(set) var creaturePlurals: [String] = []

    public init(buildings: H4BuildingTable, creatures: [H4GameTables.Creature]) { self.buildings = buildings; self.creatures = creatures }

    public init(store: H4ResourceStore, tables: H4GameTables) throws {
        self.init(buildings: try H4BuildingTable(store: store), creatures: tables.creatures)
        creatureNames = tables.creatureNames
        creaturePlurals = tables.creaturePlurals
    }

    /// Creature, weekly growth and cost of dwelling building `bit` (12...19) of a faction.
    func dwelling(faction: Int, bit: Int) -> (creature: Int, growth: Int, cost: [Int]) {
        let id = H4TownRules.dwellingCreature[faction][bit - 12]
        return (id, creatures[id].weeklyGrowth, creatures[id].cost)
    }

    func growth(creature: Int) -> Int { creatures.indices.contains(creature) ? creatures[creature].weeklyGrowth : 0 }
}

/// State of one town (R2). `mask`/`allowed` are the 43-bit sets of built and allowed buildings.
public struct H4TownState: Sendable, Equatable {
    public var index: Int
    /// `town` or `random_town`.
    public var className: String
    public var faction: Int
    public var right: Bool
    public var owner: Int
    public var mask: Int
    public var allowed: Int
    public var builtToday: Int
    /// Stock of dwellings 12...19 in 1/700 creature (list index = bit - 12).
    public var stock: [Int]
    public var garrison: [H4SlotStack]
    public var visitingArmy: Int?
    /// Name given by the map (may be empty); display only, not part of the log.
    public var name = ""
    /// Treasury of the day computed in pass A and paid in pass B (1/256 gold).
    var pending = 0

    public var model: String { H4TownRules.modelName(faction: faction, mask: mask, right: right) }

    var record: [String: H4LogJSON] {
        ["index": .int(index), "faction": .int(faction), "model": .str(model), "owner": .int(owner), "mask": .int(mask),
         "allowed": .int(allowed), "builtToday": .int(builtToday), "stock": .ints(stock), "garrison": .arr(garrison.map(\.json)),
         "visitingArmy": visitingArmy.map { .int($0) } ?? .null]
    }
}

/// Result of a town command: ok, why-code, and the count of creatures recruited / moved.
public struct H4TownOp: Sendable, Equatable {
    public var ok: Bool
    public var why: String?
    /// Creatures recruited or moved (0 if refused); nil for a build.
    public var count: Int?
}

/// A garrison or army address of a transfer.
enum H4SlotKey: Hashable { case town(Int), army(Int) }

/// Python-like reading of a decoded JSON value (JSONSerialization): an int is not a bool and not a float.
enum H4Py {
    static func int(_ v: Any?) -> Int? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), !CFNumberIsFloatType(n) else { return nil }
        return n.intValue
    }
    /// `isinstance(v, int)` in Python: a bool counts (True = 1).
    static func intOrBool(_ v: Any?) -> Int? {
        guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() || !CFNumberIsFloatType(n) else { return nil }
        return n.intValue
    }
}

/// Towns, mines, generators and army slots of a started game (v2 ruleset) with the rules that act on them.
struct H4TownWorld {
    var towns: [Int: H4TownState]
    var townOrder: [Int]
    var mines: [Int: H4MineState]
    var gens: [Int: H4GeneratorState]
    /// Slots of every army of the session (id = object index).
    var slots: [Int: [H4SlotStack]]
    var armyOwner: [Int: Int]
    /// Treasury carry per player (1/256 gold).
    var carry: [Int: Int]
    var humanOf: [Int: Bool]
    var difficulty: Int
    var tables: H4TownTables

    static let slotCount = 7

    // MARK: construction (R1, R2)

    struct Player { var colour: Int; var human: Bool; var team: [Int]; var start: [Int] }

    /// Players with team and starting stock (R1).
    static func players(game: H4Game, scenario: H4Scenario) -> [Player] {
        let humans = Set(game.players.filter(\.human).map(\.colour))
        var teamOf: [Int: [Int]] = [:]
        for mask in scenario.teams {
            let members = (0..<8).filter { Int(mask) >> $0 & 1 != 0 }
            for c in members where teamOf[c] == nil { teamOf[c] = members }
        }
        return game.players.sorted { $0.colour < $1.colour }.map { p in
            let team = teamOf[p.colour] ?? [p.colour]
            let computer = !team.contains { humans.contains($0) }
            return Player(colour: p.colour, human: p.human, team: team,
                          start: H4Economy.startingResources(computerTeam: computer, difficulty: game.difficulty))
        }
    }

    static func slots(of army: H4Army?, tables: H4TownTables) -> [H4SlotStack] {
        guard let army else { return Array(repeating: .empty, count: slotCount) }
        return army.slots.map { s in
            switch s {
            case .empty: return .empty
            case .hero: return .hero
            case .stack(let c):
                guard c.creature >= 0 else { return .empty }
                let n = Int(c.count) > 0 ? Int(c.count) : max(1, tables.growth(creature: Int(c.creature)))
                return H4SlotStack(creature: Int(c.creature), count: n)
            }
        }
    }

    static func mask(_ b: H4Bitset) -> Int {
        var v = 0
        for (i, byte) in b.bytes.enumerated() { v |= Int(byte) << (8 * i) }
        return v
    }

    /// Initial state of the game: towns in object order (R2), mines, weekly generators, army slots.
    /// `armies`: id -> owner of every army of the session.
    init(game: H4Game, scenario: H4Scenario, objects: [H4ScenarioObject], armies: [Int: Int], tables: H4TownTables) throws {
        self.tables = tables
        difficulty = game.difficulty
        let players = Self.players(game: game, scenario: scenario)
        carry = Dictionary(uniqueKeysWithValues: players.map { ($0.colour, 0) })
        humanOf = Dictionary(uniqueKeysWithValues: players.map { ($0.colour, $0.human) })
        let resolved = Dictionary(game.objects.map { ($0.index, $0.resolved) }, uniquingKeysWith: { a, _ in a })
        towns = [:]; townOrder = []; mines = [:]; gens = [:]; slots = [:]
        armyOwner = armies
        for id in armies.keys { slots[id] = Array(repeating: .empty, count: Self.slotCount) }
        for (i, o) in objects.enumerated() {
            var town: H4AbstractTown?
            switch o.payload {
            case .town(let v): town = v.town
            case .randomTown(let v): town = v.town
            case .army(let rec): if slots[i] != nil { slots[i] = Self.slots(of: rec.army, tables: tables) }
            default: break
            }
            let cls = o.className
            let owner = H4GameRender.owner(of: o) ?? 6
            if let t = town {
                let faction: Int, right: Bool
                if cls == "random_town" {
                    guard let f = resolved[i]?.faction else { throw H4Error.malformed("random town \(i) without a resolved faction") }
                    faction = f; right = (resolved[i]?.r ?? 0) != 0
                } else {
                    guard let f = H4TownRules.factions.firstIndex(of: o.triple?.subclassName ?? "") else {
                        throw H4Error.malformed("town \(i): unknown faction '\(o.triple?.subclassName ?? "")'")
                    }
                    faction = f; right = o.triple?.indexName == "right"
                }
                var built: Int, allowed: Int
                if let b = t.buildings {
                    built = Self.mask(b[0]) | 0x101
                    allowed = Self.mask(b[1])
                } else {
                    let flag = t.buildingFlag ?? false
                    built = 0x101 | (flag ? 8 : 0)
                    if flag {
                        built |= 1 << 12 | 1 << 13
                        if owner != 6 && faction != 5 { built |= 1 << 20 }
                    } else {
                        built |= 1 << 12
                    }
                    if owner != 6 { built |= 1 << 9 }
                    allowed = (1 << 43) - 1
                }
                var stock = [Int](repeating: 0, count: 8)
                for b in 12..<20 where built >> b & 1 != 0 {
                    stock[b - 12] = H4Economy.initialStock(weeklyGrowth: tables.dwelling(faction: faction, bit: b).growth)
                }
                let garrison = t.garrison.map { Self.slots(of: $0, tables: tables) } ?? Array(repeating: .empty, count: Self.slotCount)
                towns[i] = H4TownState(index: i, className: cls, faction: faction, right: right, owner: owner, mask: built, allowed: allowed,
                                       builtToday: 0, stock: stock, garrison: garrison, visitingArmy: nil)
                towns[i]!.name = t.name
                townOrder.append(i)
            } else if cls == "mine" {
                guard let ty = H4MineState.subclassTypes[o.triple?.subclassName ?? ""] else {
                    throw H4Error.malformed("mine \(i): unknown subclass '\(o.triple?.subclassName ?? "")'")
                }
                mines[i] = H4MineState(owner: owner, type: ty)
            } else if cls == "weekly_material_generator" {
                guard let ty = H4GeneratorState.subclassTypes[o.triple?.subclassName ?? ""] else {
                    throw H4Error.malformed("generator \(i): unknown subclass '\(o.triple?.subclassName ?? "")'")
                }
                gens[i] = H4GeneratorState(owner: owner, type: ty, potType: ty, pot: H4Economy.generatorPot[ty])
            } else if cls == "random_weekly_material_generator" {
                guard let r = resolved[i], let m = r.material, let pt = r.produces, let amount = r.amount else {
                    throw H4Error.malformed("random generator \(i) not resolved")
                }
                gens[i] = H4GeneratorState(owner: owner, type: m, potType: pt, pot: amount)
            }
        }
    }

    /// A world from ready-made parts (tests).
    init(towns list: [H4TownState], slots: [Int: [H4SlotStack]] = [:], armyOwner: [Int: Int] = [:], mines: [Int: H4MineState] = [:],
         gens: [Int: H4GeneratorState] = [:], humanOf: [Int: Bool] = [:], difficulty: Int = 2, tables: H4TownTables) {
        towns = Dictionary(list.map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })
        townOrder = list.map(\.index)
        self.mines = mines; self.gens = gens; self.slots = slots; self.armyOwner = armyOwner
        carry = Dictionary(uniqueKeysWithValues: humanOf.keys.map { ($0, 0) })
        self.humanOf = humanOf; self.difficulty = difficulty; self.tables = tables
    }

    // MARK: helpers

    /// Whether the owner is a player of the game (others are treated as neutral for the economy).
    func isPlayer(_ owner: Int, _ resources: [Int: H4SessionResources]) -> Bool { resources[owner] != nil }

    func peasants(of colour: Int) -> Int {
        var n = 0
        for (id, row) in slots where armyOwner[id] == colour { n += row.filter { $0.creature == H4Economy.peasant }.reduce(0) { $0 + $1.count } }
        for t in towns.values where t.owner == colour { n += t.garrison.filter { $0.creature == H4Economy.peasant }.reduce(0) { $0 + $1.count } }
        return n
    }

    func otherMightGrail(of t: H4TownState) -> Bool {
        towns.values.contains { $0.index != t.index && $0.owner == t.owner && $0.faction == 5 && $0.mask >> 11 & 1 != 0 }
    }

    mutating func clearVisits() { for i in townOrder { towns[i]!.visitingArmy = nil } }

    // MARK: day tick (R3)

    /// `day` = days elapsed since the start after the advance (the first tick has 1).
    mutating func dayTick(day D: Int, resources: inout [Int: H4SessionResources]) {
        // pass A
        for i in townOrder {
            var t = towns[i]!
            guard isPlayer(t.owner, resources) else { continue }
            t.builtToday = max(0, t.builtToday - 1)
            let b = H4Economy.growthBonus(mask: t.mask, faction: t.faction, otherMightGrail: otherMightGrail(of: t))
            for bit in 12..<20 where t.mask >> bit & 1 != 0 {
                t.stock[bit - 12] += H4Economy.dailyGrowth(bonus: b, weeklyGrowth: tables.dwelling(faction: t.faction, bit: bit).growth)
            }
            t.pending = 0
            if t.mask >> 31 & 1 != 0 {
                t.pending = H4Economy.treasuryPending(gold: resources[t.owner]!.amounts[0], carry: carry[t.owner] ?? 0)
            }
            towns[i] = t
        }
        // pass B: towns, mines and generators in object order
        for i in Set(towns.keys).union(mines.keys).union(gens.keys).sorted() {
            if let t = towns[i] {
                guard isPlayer(t.owner, resources) else { continue }
                resources[t.owner]!.amounts[0] += H4Economy.townGold(mask: t.mask)
                if t.mask >> 31 & 1 != 0 {
                    var c = carry[t.owner] ?? 0
                    resources[t.owner]!.amounts[0] += H4Economy.payTreasury(carry: &c, pending: t.pending)
                    carry[t.owner] = c
                }
            } else if let m = mines[i] {
                if isPlayer(m.owner, resources) { resources[m.owner]!.amounts[m.type] += H4Economy.mineIncome[m.type] }
            } else {
                let owner = gens[i]!.owner
                if let paid = gens[i]!.tick(owned: isPlayer(owner, resources)) { resources[owner]!.amounts[paid.resource] += paid.amount }
            }
        }
        // taxpayers [I tick: after pass B]
        for c in resources.keys.sorted() { resources[c]!.amounts[0] += peasants(of: c) }
        // computer bonus
        for c in resources.keys.sorted() where humanOf[c] != true {
            var inc = [Int](repeating: 0, count: 7)
            for m in mines.values where m.owner == c { inc[m.type] += H4Economy.mineIncome[m.type] }
            for t in towns.values where t.owner == c { inc[0] += H4Economy.townGold(mask: t.mask) }
            inc[0] += peasants(of: c)
            let mult = H4Economy.computerMultiplier[difficulty]
            for k in 0..<7 {
                var q = H4Economy.computerBonus(income: inc[k], multiplier: mult, resource: k, day: D)
                let st = resources[c]!.amounts[k]
                if -q > st { q = -st }
                resources[c]!.amounts[k] = max(0, st + q)
            }
        }
    }

    // MARK: commands (R4, R5)

    func townFor(_ v: Any?, current: Int) -> (H4TownState?, String?) {
        guard let idx = H4Py.int(v), let t = towns[idx] else { return (nil, "not-own-town") }
        if t.owner != current { return (nil, "not-current-player") }
        return (t, nil)
    }

    /// R4 build.
    mutating func build(_ cmd: [String: Any], current: Int, resources: inout [Int: H4SessionResources]) -> H4TownOp {
        func refuse(_ why: String) -> H4TownOp { H4TownOp(ok: false, why: why, count: nil) }
        let (found, why) = townFor(cmd["town"], current: current)
        guard var t = found else { return refuse(why!) }
        let f = t.faction
        guard let bid = H4Py.int(cmd["building"]), H4TownRules.isStaticBuildable(faction: f, building: bid) else { return refuse("faction-static-set") }
        if t.allowed >> bid & 1 == 0 { return refuse("not-allowed") }
        if t.mask >> bid & 1 != 0 { return refuse("already-built") }
        guard let tree = H4TownRules.requirements[f][bid], tree.satisfied(mask: t.mask, ignoreNot: true) else { return refuse("requirements") }
        if !tree.satisfied(mask: t.mask, ignoreNot: false) { return refuse("exclusive-partner") }
        if t.builtToday != 0 { return refuse("built-today") }
        guard let cost = tables.buildings.cost(faction: f, building: bid), var bag = resources[current] else { return refuse("resources") }
        if (0..<7).contains(where: { bag.amounts[$0] < cost[$0] }) { return refuse("resources") }
        for k in 0..<7 { bag.amounts[k] -= cost[k] }
        resources[current] = bag
        t.mask |= 1 << bid
        t.builtToday = 1
        if (12...19).contains(bid) { t.stock[bid - 12] = H4Economy.builtStock(weeklyGrowth: tables.dwelling(faction: f, bit: bid).growth) }
        towns[t.index] = t
        return H4TownOp(ok: true, why: nil, count: nil)
    }

    /// R5 recruit.
    mutating func recruit(_ cmd: [String: Any], current: Int, resources: inout [Int: H4SessionResources]) -> H4TownOp {
        func refuse(_ why: String) -> H4TownOp { H4TownOp(ok: false, why: why, count: 0) }
        let (found, why) = townFor(cmd["town"], current: current)
        guard var t = found else { return refuse(why!) }
        guard var n = H4Py.int(cmd["count"]), n >= 1 else { return refuse("bad-count") }
        guard let bid = H4Py.int(cmd["building"]), (12...19).contains(bid), t.mask >> bid & 1 != 0 else { return refuse("no-dwelling") }
        let dw = tables.dwelling(faction: t.faction, bit: bid)
        n = min(n, t.stock[bid - 12] / H4Economy.stockPerCreature)
        if n <= 0 { return refuse("none-available") }
        guard let k = Self.addSlot(t.garrison, dw.creature) else { return refuse("garrison-full") }
        var bag = resources[current] ?? H4SessionResources()
        for r in 0..<7 where dw.cost[r] > 0 { n = min(n, bag.amounts[r] / dw.cost[r]) }
        if n <= 0 { return refuse("resources") }
        for r in 0..<7 { bag.amounts[r] -= dw.cost[r] * n }
        resources[current] = bag
        t.stock[bid - 12] -= H4Economy.stockPerCreature * n
        if t.garrison[k].creature == -1 { t.garrison[k] = H4SlotStack(creature: dw.creature, count: n) } else { t.garrison[k].count += n }
        towns[t.index] = t
        return H4TownOp(ok: true, why: nil, count: n)
    }

    /// First slot holding the creature, else the first empty one.
    static func addSlot(_ row: [H4SlotStack], _ creature: Int) -> Int? {
        row.firstIndex { $0.creature == creature } ?? row.firstIndex { $0.creature == -1 }
    }

    private typealias Address = (key: H4SlotKey, owner: Int, slot: Int?)

    private func container(_ a: Any?, needSlot: Bool) -> (Address?, String?) {
        guard let d = a as? [String: Any] else { return (nil, "bad-container") }
        let key: H4SlotKey, owner: Int
        if let raw = d["town"] {
            guard let i = H4Py.intOrBool(raw), let t = towns[i] else { return (nil, "bad-container") }
            key = .town(i); owner = t.owner
        } else if let raw = d["army"] {
            guard let i = H4Py.intOrBool(raw), slots[i] != nil else { return (nil, "bad-container") }
            key = .army(i); owner = armyOwner[i] ?? 6
        } else {
            return (nil, "bad-container")
        }
        let s = d["slot"]
        if (s == nil || s is NSNull) && !needSlot { return ((key, owner, nil), nil) }
        guard let slot = H4Py.int(s), (0..<Self.slotCount).contains(slot) else { return (nil, "bad-slot") }
        return ((key, owner, slot), nil)
    }

    private func row(_ k: H4SlotKey) -> [H4SlotStack] {
        switch k { case .town(let i): return towns[i]!.garrison; case .army(let i): return slots[i]! }
    }

    private mutating func setRow(_ k: H4SlotKey, _ r: [H4SlotStack]) {
        switch k { case .town(let i): towns[i]!.garrison = r; case .army(let i): slots[i] = r }
    }

    /// R5 transfer.
    mutating func transfer(_ cmd: [String: Any], current: Int) -> H4TownOp {
        func refuse(_ why: String) -> H4TownOp { H4TownOp(ok: false, why: why, count: 0) }
        let (srcA, w1) = container(cmd["from"], needSlot: true)
        guard let src = srcA else { return refuse(w1!) }
        let (dstA, w2) = container(cmd["to"], needSlot: false)
        guard let dst = dstA else { return refuse(w2!) }
        let (k1, k2, s1) = (src.key, dst.key, src.slot!)
        var s2 = dst.slot
        if src.owner != current || dst.owner != current { return refuse("not-own") }
        if k1 != k2 {
            switch (k1, k2) {
            case (.town(let t), .army(let a)), (.army(let a), .town(let t)):
                if towns[t]!.visitingArmy != a { return refuse("not-visiting") }
            default: return refuse("not-visiting")
            }
        }
        var work: [H4SlotKey: [H4SlotStack]] = [:]
        work[k1] = row(k1)
        work[k2] = row(k2)
        let (sc, sn) = (work[k1]![s1].creature, work[k1]![s1].count)
        if sc == -1 { return refuse("empty-source") }
        if sc == -2 || (s2 != nil && work[k2]![s2!].creature == -2) { return refuse("hero-slot") }
        var cnt = sn
        var whole = true
        if let raw = cmd["count"], !(raw is NSNull) {
            guard let c = H4Py.int(raw), (1...sn).contains(c) else { return refuse("bad-count") }
            cnt = c
            whole = c == sn
        }
        if k1 == k2 && s1 == s2 { return refuse("same-slot") }
        if s2 == nil {
            var tgt = work[k2]!.indices.first { work[k2]![$0].creature == sc && !(k1 == k2 && $0 == s1) }
            if tgt == nil {
                tgt = work[k2]!.indices.first { work[k2]![$0].creature == -1 && !(k1 == k2 && $0 == s1 && !whole) }
            }
            guard let t = tgt else { return refuse("garrison-full") }
            s2 = t
        }
        let target = work[k2]![s2!]
        if target.creature == -1 {
            work[k2]![s2!] = H4SlotStack(creature: sc, count: cnt)
        } else if target.creature == sc {
            work[k2]![s2!] = H4SlotStack(creature: sc, count: target.count + cnt)
        } else if whole {
            work[k2]![s2!] = H4SlotStack(creature: sc, count: sn)
            work[k1]![s1] = target
            setRow(k1, work[k1]!); setRow(k2, work[k2]!)
            return H4TownOp(ok: true, why: nil, count: cnt)
        } else {
            return refuse("slot-occupied")
        }
        work[k1]![s1] = whole ? .empty : H4SlotStack(creature: sc, count: sn - cnt)
        setRow(k1, work[k1]!); setRow(k2, work[k2]!)
        return H4TownOp(ok: true, why: nil, count: cnt)
    }

    // MARK: log fields

    func logFields() -> [String: H4LogJSON] {
        var armies: [String: H4LogJSON] = [:]
        for (id, row) in slots where (armyOwner[id] ?? 6) < 6 { armies[String(id)] = .arr(row.map(\.json)) }
        var g: [String: H4LogJSON] = [:]
        for (i, s) in gens where s.owner < 6 { g[String(i)] = .ints([s.counter, s.potType, s.pot]) }
        return ["towns": .arr(townOrder.map { .obj(towns[$0]!.record) }), "armies": .obj(armies), "gens": .obj(g)]
    }
}

/// Initial town state of every map (`h4tool towns-init`; same schema as the reference's `towns_init.json`).
public enum H4TownsInit {
    /// Canonical JSON for every map of `mapsDirectory` in code-point order (seed 12345, difficulty 2).
    public static func json(dataDirectory: URL, mapsDirectory: URL) throws -> String {
        let host = try H4MovementSession(dataDirectory: dataDirectory, mapsDirectory: mapsDirectory, seed: 12345, difficulty: 2)
        let townTables = try H4TownTables(store: host.store, tables: host.tables)
        var maps: [H4LogJSON] = []
        for name in host.mapNames {
            guard let files = host.mapFiles[name], files.count == 1 else {
                throw H4Error.malformed("map name '\(name)' matches \(host.mapFiles[name]?.count ?? 0) files")
            }
            let scenario = try H4Scenario(fileData: Data(contentsOf: URL(fileURLWithPath: files[0])))
            let game = try H4GameStart.start(scenario: scenario, store: host.store, tables: host.tables, seed: host.seed, difficulty: host.difficulty)
            let body = try H4ScenarioBody(scenario: scenario, resources: host.store)
            guard case .complete = body.stop else { throw H4Error.malformed("\(name): object list stopped at \(body.stop.offset)") }
            let world = try H4TownWorld(game: game, scenario: scenario, objects: body.objects, armies: [:], tables: townTables)
            let players = H4TownWorld.players(game: game, scenario: scenario).map { p -> H4LogJSON in
                .obj(["colour": .int(p.colour), "human": .bool(p.human), "team": .ints(p.team), "start": .ints(p.start)])
            }
            let towns = world.townOrder.map { i -> H4LogJSON in
                var r = world.towns[i]!.record
                r["cls"] = .str(world.towns[i]!.className)
                return .obj(r)
            }
            maps.append(.obj(["map": .str(name), "difficulty": .int(game.difficulty), "players": .arr(players), "towns": .arr(towns)]))
        }
        return H4LogJSON.arr(maps).text
    }
}
