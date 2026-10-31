import Foundation

// Slice 7a — game start: resolution of the random objects of a scenario.
// Normative reference: the rules 1-14 of the frozen reference gamestart_ref.py (heroes4.exe GOG 1.3, tags [D]/[I] as there).

/// MSVC `rand()` on a single global u32 seed [D 0xac16f8].
public struct H4MSVCRand: Sendable {
    public private(set) var state: UInt32
    public private(set) var calls = 0
    public init(seed: UInt32) { state = seed }
    public mutating func next() -> Int {
        state = state &* 214013 &+ 2531011
        calls += 1
        return Int((state >> 16) & 0x7fff)
    }
    /// `rand() % n`, n > 0.
    public mutating func pick(_ n: Int) -> Int { next() % n }
}

/// Placement spec of a random object (rule 4).
public enum H4GamePlace: Sendable, Equatable {
    /// No restriction (spec "none"); a missing spec (nil) means the same.
    case unrestricted
    case player(Int)
    case town(String)
}

/// What the game start needs to know about one scenario object (the fields of the reference dump).
public struct H4GameStartObject: Sendable, Equatable {
    public struct Town: Sendable, Equatable {
        public var name: String
        public var owner: Int
        /// First byte of the custom built set (bits 3...5 give the tier); nil without custom set.
        public var built: UInt8?
        public var flag: Bool
        public init(name: String, owner: Int, built: UInt8?, flag: Bool) {
            self.name = name; self.owner = owner; self.built = built; self.flag = flag
        }
    }
    public var index: Int
    public var x: Int, y: Int, level: Int
    public var className: String
    public var subclass: String?
    public var model: String
    public var owner: Int?
    /// Terrain id under the anchor cell.
    public var terrain: Int?
    public var place: H4GamePlace?
    public var town: Town?
    public var monsterRange: (min: Int, max: Int)?
    public var teacherMask: Int?

    public init(index: Int, x: Int, y: Int, level: Int, className: String, subclass: String? = nil, model: String = "",
                owner: Int? = nil, terrain: Int? = nil, place: H4GamePlace? = nil, town: Town? = nil,
                monsterRange: (min: Int, max: Int)? = nil, teacherMask: Int? = nil) {
        self.index = index; self.x = x; self.y = y; self.level = level; self.className = className
        self.subclass = subclass; self.model = model; self.owner = owner; self.terrain = terrain; self.place = place
        self.town = town; self.monsterRange = monsterRange; self.teacherMask = teacherMask
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.index == b.index && a.x == b.x && a.y == b.y && a.level == b.level && a.className == b.className
            && a.subclass == b.subclass && a.model == b.model && a.owner == b.owner && a.terrain == b.terrain
            && a.place == b.place && a.town == b.town && a.monsterRange?.min == b.monsterRange?.min
            && a.monsterRange?.max == b.monsterRange?.max && a.teacherMask == b.teacherMask
    }
}

public struct H4GameStartPlayer: Sendable, Equatable {
    public var colour: Int
    public var human: Bool
    /// Allowed-alignments mask (6 bits).
    public var alignments: Int
    public init(colour: Int, human: Bool, alignments: Int) {
        self.colour = colour; self.human = human; self.alignments = alignments
    }
}

public struct H4GameStartInput: Sendable {
    public var players: [H4GameStartPlayer]
    public var objects: [H4GameStartObject]
    public init(players: [H4GameStartPlayer], objects: [H4GameStartObject]) { self.players = players; self.objects = objects }

    /// The input of a scenario: its header players, its object list (file order) and the terrain under each anchor.
    public init(scenario: H4Scenario, objects list: [H4ScenarioObject], terrain: H4ScenarioTerrain?) {
        func place(_ p: H4PlacementSpec?) -> H4GamePlace? {
            guard let p else { return nil }
            switch p {
            case .none: return .unrestricted
            case .player(let n): return .player(Int(n))
            case .town(let s): return .town(s)
            }
        }
        func town(_ t: H4AbstractTown) -> H4GameStartObject.Town {
            .init(name: t.name, owner: Int(t.owner), built: t.buildings.map { $0[0].bytes.first ?? 0 },
                  flag: t.buildingFlag ?? false)
        }
        var out: [H4GameStartObject] = []
        for (i, o) in list.enumerated() {
            var d = H4GameStartObject(index: i, x: Int(o.x), y: Int(o.y), level: Int(o.level), className: o.className,
                                      subclass: o.triple?.subclassName, model: o.modelName)
            if let t = terrain, let c = t.cell(level: Int(o.level), row: Int(o.x), column: Int(o.y)) { d.terrain = Int(c.terrain) }
            switch o.payload {
            case .ownedScriptable(let v): d.owner = Int(v.owner)
            case .randomDwelling(let v): d.owner = Int(v.owner); d.place = place(v.placement)
            case .garrison(let v): d.owner = Int(v.owner)
            case .outpost(_, let ow): if let ow { d.owner = Int(ow) }
            case .carryoverHero(let v): if let ow = v.owner { d.owner = Int(ow) }
            case .randomMonster(let v):
                d.place = place(v.placement)
                d.monsterRange = (Int(v.minSize ?? 0), Int(v.maxSize ?? 0))
            case .town(let v): d.owner = Int(v.town.owner); d.town = town(v.town)
            case .randomTown(let v): d.owner = Int(v.town.owner); d.town = town(v.town); d.place = place(v.placement)
            case .shrine(let v): d.place = place(v.placement)
            case .randomTemple(_, let p): d.place = place(p)
            case .conservatory(let v): d.place = place(v.placement)
            case .randomTeacher(let v): d.place = place(v.placement); d.teacherMask = Int(v.allowedMask)
            case .army(let v): d.owner = Int(v.owner)
            default: break
            }
            out.append(d)
        }
        self.init(players: scenario.players.map { .init(colour: $0.colour, human: $0.humanPlayable, alignments: Int($0.alignments)) },
                  objects: out)
    }
}

public enum H4GameStart {
    static let resolverClasses: Set<String> = [
        "random_town", "random_creature_dwelling", "random_monster", "random_random_monster", "random_artifact",
        "random_tome", "random_staff", "random_potion", "random_material_pile", "random_weekly_material_generator",
        "random_shrine", "random_temple", "random_conservatory", "random_teacher", "windmill"]
    static let multipliers: [Double] = [0.6667, 1.0, 1.5, 2.0, 3.0]
    static let budgetInt = [1: 155, 2: 310, 3: 620, 4: 1240]
    static let budgetDouble = [1: 2.0, 2: 2.5, 3: 3.0, 4: 4.0]
    static let artifactLevels = ["item": 0, "treasure": 1, "minor": 2, "major": 3]
    static let artifactCSVLevels = ["Item": 0, "Treasure": 1, "Minor": 2, "Major": 3]

    /// Starts a game: pass order of rule 3, then the placement of every object.
    /// Throws `H4Error.malformed` for an input the game start cannot process (difficulty out of 0...4, a placeholder
    /// lacking the field it needs, an unusable subclass, an impossible teacher mask); never traps.
    public static func start(input: H4GameStartInput, tables: H4GameTables, seed: UInt32, difficulty: H4Difficulty) throws -> H4Game {
        try validate(input, difficulty: difficulty)
        var run = Run(input: input, tables: tables, seed: seed, difficulty: difficulty)
        return try run.run()
    }

    /// Checks everything the resolvers force-unwrap, so that the run itself cannot trap.
    static func validate(_ input: H4GameStartInput, difficulty: Int) throws {
        guard (0..<multipliers.count).contains(difficulty) else { throw H4Error.malformed("difficulty \(difficulty) outside 0...4") }
        for o in input.objects {
            func bad(_ what: String) -> H4Error { .malformed("object \(o.index) (\(o.className)): \(what)") }
            switch o.className {
            case "random_town":
                guard let owner = o.owner, (0...6).contains(owner) else { throw bad("missing or invalid owner") }
                guard o.town != nil else { throw bad("missing town") }
            case "random_creature_dwelling", "random_monster":
                guard let n = levelSuffix(o.subclass), (1...4).contains(n) else { throw bad("subclass '\(o.subclass ?? "")' has no level 1...4") }
                if let m = o.monsterRange, m.min > 0, m.max < m.min { throw bad("monster size range \(m.min)...\(m.max)") }
                // Map files store the range as Int32; larger values would overflow the ×4 budget arithmetic.
                if let m = o.monsterRange, m.min > Int(Int32.max) || m.max > Int(Int32.max) || m.min < Int(Int32.min) || m.max < Int(Int32.min) {
                    throw bad("monster size range \(m.min)...\(m.max) outside Int32")
                }
            case "random_shrine":
                guard levelSuffix(o.subclass) != nil else { throw bad("subclass '\(o.subclass ?? "")' has no level") }
            case "random_artifact":
                guard artifactLevels[(o.subclass ?? "").lowercased()] != nil else { throw bad("unknown artifact level '\(o.subclass ?? "")'") }
            case "random_teacher":
                if let m = o.teacherMask, m != 0, m & 0x1ff == 0 { throw bad("teacher mask \(m) allows none of the 9 kinds") }
            default: break
            }
        }
    }

    /// Game start of a scenario file.
    public static func start(scenario: H4Scenario, store: H4ResourceStore, tables: H4GameTables, seed: UInt32,
                             difficulty: H4Difficulty) throws -> H4Game {
        let resolver = H4ObjectClassResolver(resources: store)
        let body = try H4ScenarioBody(scenario: scenario, resolver: resolver)
        guard case .complete = body.stop else { throw H4Error.malformed("object list stopped at \(body.stop.offset)") }
        let terrain = try? H4ScenarioTerrain(scenario: scenario)
        var input = H4GameStartInput(scenario: scenario, objects: body.objects, terrain: terrain)
        // The file's triple matches the resource's case-insensitively; the game works with the resource's (canonical) name.
        for k in input.objects.indices where input.objects[k].subclass != nil && !input.objects[k].model.isEmpty {
            input.objects[k].subclass = try resolver.resolve(model: input.objects[k].model).subclassName
        }
        return try start(input: input, tables: tables, seed: seed, difficulty: difficulty)
    }

    /// Python's `a % b` for b != 0 (result has the sign of b).
    static func pyMod(_ a: Int, _ b: Int) -> Int { let m = a % b; return (m != 0 && (m < 0) != (b < 0)) ? m + b : m }

    /// The level of a `<name>_<level>` subclass; nil when it has none.
    static func levelSuffix(_ sub: String?) -> Int? {
        let parts = (sub ?? "").split(separator: "_", omittingEmptySubsequences: false)
        return parts.count > 1 ? Int(parts[1]) : nil
    }

    struct State { var faction = 0, creature = 0, filter = -1, school = 0, kind = 0 }

    struct Run {
        let t: H4GameTables
        var rng: H4MSVCRand
        let seed: UInt32
        let difficulty: Int
        var objs: [H4GameStartObject]
        var players: [H4GamePlayer] = []
        var pfaction: [Int: Int] = [:]
        var townFirst: [String: Int] = [:]
        var townFaction: [Int: Int] = [:]
        var used: Set<Int> = [H4GameIdentifiers.parchmentID, H4GameIdentifiers.scrollID]
        var st: [Int: State] = [:]

        init(input: H4GameStartInput, tables: H4GameTables, seed: UInt32, difficulty: Int) {
            t = tables; rng = H4MSVCRand(seed: seed); self.seed = seed; self.difficulty = difficulty; objs = input.objects
            for p in input.players {
                let f = (0..<6).first { p.alignments & (1 << $0) != 0 } ?? 0
                pfaction[p.colour] = f
                players.append(H4GamePlayer(colour: p.colour, human: p.human, faction: f))
            }
            for (k, o) in objs.enumerated() where o.className == "town" || o.className == "random_town" {
                if let town = o.town, townFirst[town.name] == nil { townFirst[town.name] = k }
            }
        }

        // rule 4
        func spec(_ place: H4GamePlace?, _ flag: Int) -> Int {
            guard let place else { return 6 }
            switch place {
            case .unrestricted: return 6
            case .player(let c): return pfaction[c] ?? 6
            case .town(let name):
                if flag == 0 { return 7 }
                guard let k = townFirst[name] else { return 6 }
                let o = objs[k]
                if o.className == "town" { return H4GameIdentifiers.alignmentNames.firstIndex(of: (o.subclass ?? "").lowercased()) ?? 6 }
                return townFaction[k] ?? 6
            }
        }

        // vt74
        mutating func vt74(_ k: Int, _ pass: Int) throws -> Bool {
            let o = objs[k]
            switch o.className {
            case "random_town":
                let s = spec(o.place, 0)
                var f: Int
                if s == 6 || s == 7 {
                    if o.owner! == 6 { f = rng.pick(6) } else if let pf = pfaction[o.owner!] { f = pf } else { f = rng.pick(6) }
                } else { f = s }
                townFaction[k] = f
                st[k] = State(faction: f)
            case "random_creature_dwelling":
                let s = spec(o.place, pass)
                if s == 7 { return true }
                guard let pool = t.dwellingPools[H4GameStart.levelSuffix(o.subclass)!], !pool.isEmpty else {
                    throw H4Error.malformed("no dwelling creature for \(o.subclass ?? "")")
                }
                var cr = 0
                for _ in 0..<100000 {
                    cr = pool[rng.pick(pool.count)]
                    if s != 6 && t.creatures[cr].alignment != s { continue }
                    break
                }
                st[k] = State(creature: cr)
            case "random_monster", "random_random_monster":
                let s = spec(o.place, pass)
                if s == 7 { return true }
                st[k] = State(filter: (0...5).contains(s) ? s : -1)
            case "random_shrine", "random_temple", "random_conservatory":
                let s = spec(o.place, pass)
                if s == 7 { return true }
                st[k] = State(school: (0...4).contains(s) ? s : rng.pick(5))
            case "random_teacher":
                let s = spec(o.place, pass)
                if s == 7 { return true }
                let a = (0...4).contains(s) ? 1 << (4 + s) : (s == 5 ? 0x0f : 0x1ff)
                let allowed = (o.teacherMask ?? 0x1ff) & 0x1ff
                var c = a & allowed
                if c == 0 { c = allowed != 0 ? allowed : a }
                guard c != 0 else { throw H4Error.malformed("random_teacher without a candidate kind") }
                let kk = rng.pick(c.nonzeroBitCount)
                let bits = (0..<9).filter { c & (1 << $0) != 0 }
                st[k] = State(kind: bits[kk])
            case "artifact":
                if let i = t.artifactIDByModel[o.model.lowercased()] { used.insert(i) }
            default: break
            }
            return false
        }

        // rule 8
        mutating func choose(_ pass1: [Int], _ reset: [Int]) -> Int? {
            var cand = pass1
            if cand.isEmpty {
                cand = reset
                for i in reset { used.remove(i) }
            }
            if cand.isEmpty { return nil }
            let i = cand[rng.pick(cand.count)]
            used.insert(i)
            return i
        }

        mutating func pickArtifact(level: Int? = nil, slot: String? = nil) -> Int? {
            func ok(_ i: Int) -> Bool {
                let a = t.artifacts[i]
                if a.flag || t.artifactModels[i] == nil { return false }
                if let level, H4GameStart.artifactCSVLevels[a.level] != level { return false }
                if let slot, a.slot != slot { return false }
                return true
            }
            let p1 = (0..<248).filter { ok($0) && !used.contains($0) }
            let p2 = (0..<248).filter { ok($0) && $0 != H4GameIdentifiers.parchmentID && $0 != H4GameIdentifiers.scrollID }
            return choose(p1, p2)
        }

        mutating func pickList(_ list: [Int]) -> Int? {
            let p1 = list.filter { !used.contains($0) && t.artifactModels[$0] != nil }
            let p2 = list.filter { $0 != H4GameIdentifiers.parchmentID && $0 != H4GameIdentifiers.scrollID && t.artifactModels[$0] != nil }
            return choose(p1, p2)
        }

        // rule 7, pick [D 0x7f3380]
        mutating func scan(_ f: Int, _ special: Bool, _ maxV: Int, _ excl: Int, _ lo: Int, _ hi: Int) -> Int {
            var n = 0, chosen = -1
            for i in 0..<74 {
                let c = t.creatures[i]
                if c.expansion > 2 || c.experience > maxV { continue }
                if excl != -1 && i != excl && c.experience == maxV { continue }
                if H4GameIdentifiers.seaCreatures.contains(i) != special { continue }
                if !(lo <= c.level && c.level <= hi) { continue }
                if f != -1 && c.alignment != f { continue }
                n += 1
                if rng.next() % n == 0 { chosen = i }
            }
            return chosen
        }

        mutating func monster(_ k: Int) -> H4ResolvedObject {
            let o = objs[k]
            let f = st[k]!.filter
            let n: Int, lvLo: Int, lvHi: Int
            if o.className == "random_monster" { n = H4GameStart.levelSuffix(o.subclass)!; lvLo = n; lvHi = n } else { n = 3; lvLo = 0; lvHi = 5 }
            var lo: Int, hi: Int
            if let m = o.monsterRange, m.min > 0 {
                lo = 4 * m.min; hi = 4 * m.max
            } else {
                let base = Double(H4GameStart.budgetInt[n]!) * H4GameStart.budgetDouble[n]!
                lo = Int(base * 0.8); hi = Int(base * 1.2)
            }
            let rv = rng.next()
            let b = Int(Double(lo + H4GameStart.pyMod(rv, hi - lo + 1)) * H4GameStart.multipliers[difficulty])
            let special = o.terrain == 0
            let c = scan(f, special, b, -1, lvLo, lvHi)
            var r = H4ResolvedObject()
            r.budget = b; r.special = special
            if c == -1 { r.model = nil; r.removed = true; return r }
            let cr = t.creatures[c], v = cr.experience
            var n1 = (c == 38 || c == 52) ? b / v : (2 * b + 3 * v - 1) / (3 * v)
            n1 = max(n1, 1)
            var stacks = [H4ArmyStack(creature: c, count: n1)]
            let rem = b - n1 * v
            if rem > 0 && c != 38 && c != 52 {
                let c2 = scan(cr.alignment, special, min(v, rem), c, cr.level - 1, cr.level)
                if c2 != -1 {
                    let n2 = rem / t.creatures[c2].experience
                    if n2 > 0 {
                        if c2 == c { stacks[0].count += n2 } else { stacks.append(H4ArmyStack(creature: c2, count: n2)) }
                    }
                }
            }
            r.model = "adv_actor." + cr.keyword; r.creature = c; r.count = stacks[0].count; r.stacks = stacks
            return r
        }

        // vt70
        mutating func vt70(_ k: Int) -> H4ResolvedObject? {
            let o = objs[k]
            var r = H4ResolvedObject()
            var isArt = false
            var art: Int?
            switch o.className {
            case "random_town":
                let f = st[k]!.faction
                let info = o.town!
                let tier: Int
                if let m = info.built { tier = m & 0x20 != 0 ? 3 : m & 0x10 != 0 ? 2 : m & 0x08 != 0 ? 1 : 0 } else { tier = info.flag ? 1 : 0 }
                let rr = o.subclass?.lowercased() == "right" ? 1 : 0
                r.model = "castle.\(H4GameIdentifiers.factionNames[f]).\(H4GameIdentifiers.tierNames[tier])" + (rr == 1 ? " R" : "")
                r.faction = f; r.tier = tier; r.r = rr
                return r
            case "random_creature_dwelling":
                let cr = st[k]!.creature
                r.model = t.creatures[cr].dwelling; r.creature = cr; r.level = H4GameStart.levelSuffix(o.subclass)!
                return r
            case "random_monster", "random_random_monster": return monster(k)
            case "random_artifact": isArt = true; art = pickArtifact(level: H4GameStart.artifactLevels[(o.subclass ?? "").lowercased()]!)
            case "random_potion": isArt = true; art = pickArtifact(slot: "Potion")
            case "random_tome": isArt = true; art = pickList(H4GameIdentifiers.tomeIDs)
            case "random_staff": isArt = true; art = pickList(H4GameIdentifiers.staffIDs)
            default: break
            }
            if isArt {
                if let i = art { r.model = t.artifactModels[i]; r.artifact = i } else { r.model = nil }
                return r
            }
            switch o.className {
            case "random_material_pile":
                let kind = rng.pick(7)
                let amount: Int
                if kind == 0 { amount = (rng.pick(5) + 4) * 100 } else if kind == 1 || kind == 2 { amount = rng.pick(5) + 4 } else { amount = rng.pick(3) + 2 }
                r.model = H4GameIdentifiers.resourceModels[kind]; r.material = kind; r.amount = amount
            case "random_weekly_material_generator":
                let m = rng.pick(6) + 1
                let gold = rng.next() & 1 == 0
                r.model = H4GameIdentifiers.weeklyModels[m - 1]; r.material = m; r.gold = gold
                r.produces = gold ? 0 : m; r.amount = gold ? 500 : H4GameIdentifiers.weeklyAmounts[m - 1]
            case "random_shrine":
                _ = rng.next()
                let sc = st[k]!.school, lvl = H4GameStart.levelSuffix(o.subclass)!
                r.model = "shrines.\(H4GameIdentifiers.shrineSchools[sc]) \(lvl)"; r.school = sc; r.level = lvl; r.hasNullSpell = true
            case "random_temple":
                let sc = st[k]!.school
                r.model = "moral-luck boosters." + H4GameIdentifiers.templeModels[sc]; r.school = sc
            case "random_conservatory":
                let sc = st[k]!.school
                r.model = "mage_guilds." + H4GameIdentifiers.conservatorySchools[sc]; r.school = sc
            case "random_teacher":
                let kd = st[k]!.kind
                r.model = "Scholars." + H4GameIdentifiers.teacherNames[kd]; r.teacher = kd
            case "windmill":
                let mat = 3 + (rng.next() & 3)
                let amount = rng.next() % 3 + 4
                r.model = o.model; r.material = mat; r.amount = amount
            default: return nil
            }
            return r
        }

        mutating func run() throws -> H4Game {
            var retry: [Int] = []
            for k in objs.indices where try vt74(k, 0) { retry.append(k) }
            var pass = 0
            while !retry.isEmpty {
                pass += 1
                if pass > 16 {
                    for k in retry { objs[k].place = nil; _ = try vt74(k, pass) }
                    break
                }
                retry = try retry.filter { try vt74($0, pass) }
            }
            var out: [H4GameObject] = []
            for k in objs.indices {
                let o = objs[k]
                guard H4GameStart.resolverClasses.contains(o.className), let res = vt70(k) else { continue }
                out.append(H4GameObject(index: o.index, x: o.x, y: o.y, level: o.level, className: o.className,
                                        subclass: o.subclass ?? "", owner: o.owner, resolved: res))
            }
            return H4Game(seed: seed, difficulty: difficulty, players: players, objects: out)
        }
    }
}

// MARK: canonical JSON (Python json.dumps(sort_keys=True, separators=(",", ":")), ASCII)

enum H4JSON {
    case null, bool(Bool), int(Int), string(String), array([H4JSON]), object([String: H4JSON])

    func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .string(let s): H4JSON.writeString(s, to: &out)
        case .array(let a):
            out += "["
            for (i, v) in a.enumerated() { if i > 0 { out += "," }; v.write(to: &out) }
            out += "]"
        case .object(let d):
            out += "{"
            let keys = d.keys.sorted { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes($1.unicodeScalars.map(\.value)) }
            for (i, k) in keys.enumerated() {
                if i > 0 { out += "," }
                H4JSON.writeString(k, to: &out); out += ":"; d[k]!.write(to: &out)
            }
            out += "}"
        }
    }

    static func writeString(_ s: String, to out: inout String) {
        out += "\""
        for u in s.utf16 {
            switch u {
            case 0x22: out += "\\\""
            case 0x5c: out += "\\\\"
            case 0x0a: out += "\\n"
            case 0x0d: out += "\\r"
            case 0x09: out += "\\t"
            case 0x08: out += "\\b"
            case 0x0c: out += "\\f"
            case 0x20..<0x7f: out += String(UnicodeScalar(UInt8(u)))
            default: out += String(format: "\\u%04x", u)
            }
        }
        out += "\""
    }
}

extension H4ResolvedObject {
    var json: H4JSON {
        var d: [String: H4JSON] = ["model": model.map { .string($0) } ?? .null]
        func put(_ k: String, _ v: Int?) { if let v { d[k] = .int(v) } }
        func put(_ k: String, _ v: Bool?) { if let v { d[k] = .bool(v) } }
        put("faction", faction); put("tier", tier); put("r", r); put("creature", creature); put("level", level)
        put("count", count); put("budget", budget); put("special", special); put("removed", removed)
        put("artifact", artifact); put("material", material); put("amount", amount); put("gold", gold)
        put("produces", produces); put("school", school); put("teacher", teacher)
        if let stacks { d["stacks"] = .array(stacks.map { .object(["creature": .int($0.creature), "count": .int($0.count)]) }) }
        if hasNullSpell { d["spell"] = .null }
        return .object(d)
    }
}

extension H4Game {
    /// The reference JSON: canonical (sorted keys, no whitespace, ASCII), no trailing newline.
    public func canonicalJSON() -> String {
        let players = self.players.map { H4JSON.object(["colour": .int($0.colour), "human": .bool($0.human), "faction": .int($0.faction)]) }
        let setup = H4JSON.object(["players": .array(players), "seed": .int(Int(seed)), "difficulty": .int(difficulty),
                                   "expansion": .int(H4Game.expansion)])
        let objects = self.objects.map { o in
            H4JSON.object(["index": .int(o.index), "x": .int(o.x), "y": .int(o.y), "level": .int(o.level),
                           "class": .string(o.className), "subclass": .string(o.subclass),
                           "owner": o.owner.map { .int($0) } ?? .null, "resolved": o.resolved.json])
        }
        var s = ""
        H4JSON.object(["setup": setup, "objects": .array(objects)]).write(to: &s)
        return s
    }
}
