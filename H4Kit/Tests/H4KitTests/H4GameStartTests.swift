import Foundation
import Testing
@testable import H4Kit

// Slice 7a: game start. The tests that need the game files read H4_DATA_DIR (Data folder), H4_MAPS_DIR (maps folder)
// and H4_GAMESTART_REF_DIR (folder of the frozen reference: creatures.csv, artifacts.csv, artmodel.json, ref_out/<seed>/).

private let env = ProcessInfo.processInfo.environment
private let hasData = env["H4_DATA_DIR"] != nil
private let hasMaps = env["H4_DATA_DIR"] != nil && env["H4_MAPS_DIR"] != nil
private let hasRef = env["H4_DATA_DIR"] != nil && env["H4_MAPS_DIR"] != nil && env["H4_GAMESTART_REF_DIR"] != nil
private let hasTableRef = env["H4_DATA_DIR"] != nil && env["H4_GAMESTART_REF_DIR"] != nil

private func realStore() throws -> H4ResourceStore { try H4ResourceStore(dataDirectory: URL(fileURLWithPath: env["H4_DATA_DIR"]!)) }

/// Tables with made-up statistics: enough for the parts of the game start that do not depend on the game's numbers.
private func syntheticTables() throws -> H4GameTables {
    let creatures = H4DataTable(columns: ["Keyword", "Level", "Alignment", "Experience"],
                                rows: H4GameIdentifiers.creatureKeywords.map { [$0, "1", "life", "10"] })
    let artifacts = H4DataTable(columns: ["Keyword", "Slot", "Level", "Allowed By Default"],
                                rows: H4GameIdentifiers.artifactKeywords.map { [$0, "Torso", "Minor", ""] })
    return try H4GameTables(creatures: creatures, artifacts: artifacts)
}

private func csv(_ path: String) throws -> [[String]] {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
    var it = text.makeIterator()
    while let ch = it.next() {
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

private func fnv1a(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    return h
}

private func monsterObjects(_ specs: [(String, String, (Int, Int)?)]) -> H4GameStartInput {
    H4GameStartInput(
        players: [.init(colour: 0, human: true, alignments: 3), .init(colour: 1, human: false, alignments: 32)],
        objects: specs.enumerated().map { i, s in
            H4GameStartObject(index: i, x: i + 1, y: i + 1, level: 0, className: s.0, subclass: s.1, model: "m", terrain: 3,
                              place: .unrestricted, monsterRange: s.2 ?? (0, 0))
        })
}

// MARK: - RNG

@Test func msvcRandKnownValues() {
    var r = H4MSVCRand(seed: 1)
    #expect((0..<5).map { _ in r.next() } == [41, 18467, 6334, 26500, 19169])
    var z = H4MSVCRand(seed: 0)
    #expect((0..<3).map { _ in z.next() } == [38, 7719, 21238])
    var w = H4MSVCRand(seed: 0xFFFF_FFFF)               // wraps modulo 2^32
    _ = w.next()
    #expect(w.state == 0xFFFF_FFFF &* 214013 &+ 2531011)
    var p = H4MSVCRand(seed: 1)
    #expect(p.pick(10) == 1 && p.calls == 1)
}

// MARK: - Budget (rule 7), all five difficulties

/// Budget of a lone monster (the first rand of the run) at difficulties 0...4, as computed by gamestart_ref.py:
/// level_1...level_4, random_random_monster, level_2 with the stack range 5...12.
@Test func budgetFollowsDifficultyForEachLevel() throws {
    let tables = try syntheticTables()
    let kinds: [(String, String, (Int, Int)?)] = [("random_monster", "level_1", nil), ("random_monster", "level_2", nil),
        ("random_monster", "level_3", nil), ("random_monster", "level_4", nil), ("random_random_monster", "x", nil),
        ("random_monster", "level_2", (5, 12))]
    let expected: [UInt32: [[Int]]] = [
        1: [[192, 289, 433, 578, 867], [440, 661, 991, 1322, 1983], [1019, 1529, 2293, 3058, 4587],
            [2672, 4009, 6013, 8018, 12027], [1019, 1529, 2293, 3058, 4587], [21, 32, 48, 64, 96]],
        12345: [[221, 332, 498, 664, 996], [493, 740, 1110, 1480, 2220], [1081, 1622, 2433, 3244, 4866],
                [3731, 5597, 8395, 11194, 16791], [1081, 1622, 2433, 3244, 4866], [23, 35, 52, 70, 105]],
    ]
    for (seed, perKind) in expected {
        for (k, kind) in kinds.enumerated() {
            for d in 0...4 {
                let game = try H4GameStart.start(input: monsterObjects([kind]), tables: tables, seed: seed, difficulty: d)
                #expect(game.objects[0].resolved.budget == perKind[k][d], "seed \(seed) \(kind.0) \(kind.1) difficulty \(d)")
            }
        }
    }
}

/// Whole-game comparison with gamestart_ref.py at every difficulty (budgets of several monsters depend on all earlier scans).
@Test(.enabled(if: hasData)) func budgetsAllDifficultiesMatchReferenceWithRealTables() throws {
    let tables = try H4GameTables(store: realStore())
    let specs: [(String, String, (Int, Int)?)] = [("random_monster", "level_1", nil), ("random_monster", "level_2", nil),
        ("random_monster", "level_3", nil), ("random_monster", "level_4", nil), ("random_random_monster", "x", nil),
        ("random_monster", "level_2", (5, 12))]
    let expected: [UInt32: [[Int]]] = [
        1: [[192, 521, 1347, 3578, 1261, 16], [289, 782, 2021, 5367, 1892, 21], [433, 1173, 3031, 8050, 2838, 31],
            [578, 1564, 4042, 10734, 3784, 42], [867, 2346, 6063, 16101, 5676, 63]],
        12345: [[221, 558, 1311, 2647, 1442, 14], [332, 837, 1967, 3971, 2163, 34], [498, 1255, 2950, 5956, 3244, 31],
                [664, 1674, 3934, 7942, 4326, 42], [996, 2511, 5901, 11913, 6489, 63]],
    ]
    for (seed, perDifficulty) in expected {
        for d in 0...4 {
            let game = try H4GameStart.start(input: monsterObjects(specs), tables: tables, seed: seed, difficulty: d)
            #expect(game.objects.map { $0.resolved.budget ?? -1 } == perDifficulty[d], "seed \(seed) difficulty \(d)")
        }
    }
}

// MARK: - Rand consumption order, town tier, JSON

/// Synthetic scenario whose expected output is the one of gamestart_ref.py (seed 7, difficulty 1): vt74 of every object
/// (retry pass for town placements) before vt70 of every object, in file order.
@Test func randConsumptionOrderMatchesReference() throws {
    let tables = try syntheticTables()
    func o(_ i: Int, _ cls: String, _ sub: String, owner: Int? = nil, place: H4GamePlace? = nil,
           town: H4GameStartObject.Town? = nil, mask: Int? = nil, model: String = "m") -> H4GameStartObject {
        H4GameStartObject(index: i, x: i + 1, y: i + 1, level: 0, className: cls, subclass: sub, model: model, owner: owner,
                          place: place, town: town, teacherMask: mask)
    }
    let input = H4GameStartInput(
        players: [.init(colour: 0, human: true, alignments: 3), .init(colour: 1, human: false, alignments: 32)],
        objects: [
            o(0, "random_material_pile", "x"),
            o(1, "random_shrine", "level_3", place: .player(1)),
            o(2, "windmill", "x", owner: 6, model: "windmill.model"),
            o(3, "random_weekly_material_generator", "x", owner: 6),
            o(4, "random_teacher", "", place: .unrestricted, mask: 48),
            o(5, "random_temple", "x", place: .town("Home")),
            o(6, "random_town", "right", owner: 6, place: nil, town: .init(name: "Home", owner: 6, built: 0x20, flag: false)),
            o(7, "random_town", "left", owner: 0, place: .player(1), town: .init(name: "B", owner: 0, built: nil, flag: true)),
            o(8, "random_conservatory", "x", place: .town("Nowhere")),
        ])
    let game = try H4GameStart.start(input: input, tables: tables, seed: 7, difficulty: 1)
    let expected = #"{"objects":[{"class":"random_material_pile","index":0,"level":0,"owner":null,"resolved":{"amount":4,"material":6,"model":"resources.gem"},"subclass":"x","x":1,"y":1},{"class":"random_shrine","index":1,"level":0,"owner":null,"resolved":{"level":3,"model":"shrines.Order 3","school":1,"spell":null},"subclass":"level_3","x":2,"y":2},{"class":"windmill","index":2,"level":0,"owner":6,"resolved":{"amount":5,"material":6,"model":"windmill.model"},"subclass":"x","x":3,"y":3},{"class":"random_weekly_material_generator","index":3,"level":0,"owner":6,"resolved":{"amount":10,"gold":false,"material":1,"model":"mine.weekly.woodcutters_cottage","produces":1},"subclass":"x","x":4,"y":4},{"class":"random_teacher","index":4,"level":0,"owner":null,"resolved":{"model":"Scholars.Priest","teacher":4},"subclass":"","x":5,"y":5},{"class":"random_temple","index":5,"level":0,"owner":null,"resolved":{"model":"moral-luck boosters.Temple of Light","school":0},"subclass":"x","x":6,"y":6},{"class":"random_town","index":6,"level":0,"owner":6,"resolved":{"faction":5,"model":"castle.stronghold.castle R","r":1,"tier":3},"subclass":"right","x":7,"y":7},{"class":"random_town","index":7,"level":0,"owner":0,"resolved":{"faction":5,"model":"castle.stronghold.fort","r":0,"tier":1},"subclass":"left","x":8,"y":8},{"class":"random_conservatory","index":8,"level":0,"owner":null,"resolved":{"model":"mage_guilds.order","school":1},"subclass":"x","x":9,"y":9}],"setup":{"difficulty":1,"expansion":2,"players":[{"colour":0,"faction":0,"human":true},{"colour":1,"faction":5,"human":false}],"seed":7}}"#
    #expect(game.canonicalJSON() == expected)

    // Independent replay of the documented order with the bare generator.
    var r = H4MSVCRand(seed: 7)
    let shrineSchool = r.pick(5)             // vt74 shrine (player 1 = faction 5 -> random school)
    let teacherIndex = r.pick(2)             // vt74 teacher (mask 48 = bits 4, 5 -> pick(2))
    let townFaction = r.pick(6)              // vt74 random_town (neutral owner)
    #expect(shrineSchool == 1)
    #expect([4, 5][teacherIndex] == 4)
    #expect(townFaction == 5)
    // The temple (waits for town Home) and the conservatory (unknown town) draw their school in pass 1, before any vt70.
    let templeSchool = r.pick(5), conservatorySchool = r.pick(5)
    #expect(templeSchool == 0 && conservatorySchool == 1)
    #expect(r.pick(7) == 6)                  // vt70 of the material pile is the first of all vt70 calls
}

@Test func townTierComesFromTheBuiltSet() throws {
    let tables = try syntheticTables()
    func tier(built: UInt8?, flag: Bool) -> Int {
        let o = H4GameStartObject(index: 0, x: 0, y: 0, level: 0, className: "random_town", subclass: "left", owner: 6, place: .unrestricted,
                                  town: .init(name: "T", owner: 6, built: built, flag: flag))
        return try! H4GameStart.start(input: .init(players: [], objects: [o]), tables: tables, seed: 3, difficulty: 2)
            .objects[0].resolved.tier!
    }
    #expect(tier(built: 0x20, flag: false) == 3 && tier(built: 0x30, flag: false) == 3)
    #expect(tier(built: 0x10, flag: false) == 2 && tier(built: 0x18, flag: false) == 2)
    #expect(tier(built: 0x08, flag: false) == 1 && tier(built: 0x07, flag: false) == 0 && tier(built: 0, flag: true) == 0)
    #expect(tier(built: nil, flag: true) == 1 && tier(built: nil, flag: false) == 0)
}

@Test func canonicalJSONEscapesLikePython() {
    var s = ""
    H4JSON.object(["b": .array([.int(1), .bool(true), .null]), "a": .string("x\"y\\z\n\u{e9}")]).write(to: &s)
    #expect(s == #"{"a":"x\"y\\z\n"# + "\\u00" + "e9" + #"","b":[1,true,null]}"#)
}

@Test func factionIsLowestAllowedAlignment() throws {
    let tables = try syntheticTables()
    let g = try H4GameStart.start(input: .init(players: [.init(colour: 2, human: true, alignments: 0b101000),
                                                     .init(colour: 3, human: false, alignments: 0)], objects: []),
                              tables: tables, seed: 1, difficulty: 2)
    #expect(g.players.map(\.faction) == [3, 0] && g.players.map(\.human) == [true, false] && g.day == 1)
}

// MARK: - Tables (game files)

@Test(.enabled(if: hasTableRef)) func tablesEqualTheReferenceFiles() throws {
    let tables = try H4GameTables(store: realStore())
    let base = env["H4_GAMESTART_REF_DIR"]!
    let rows = try csv(base + "/creatures.csv")
    let head = rows[0]
    func col(_ n: String) -> Int { head.firstIndex(of: n)! }
    #expect(rows.count == 75 && tables.creatures.count == 74)
    for r in rows.dropFirst() {
        let id = Int(r[col("id")])!
        let c = tables.creatures[id]
        #expect(c.keyword == r[col("keyword")], "keyword \(id)")
        #expect(c.level == Int(r[col("level")])! && c.alignment == Int(r[col("alignment_idx")])!, "level/alignment \(id)")
        #expect(c.experience == Int(r[col("exp_value_0x74")])! && c.expansion == Int(r[col("expansion")])!, "exp/expansion \(id)")
        #expect(c.dwelling == r[col("dwelling_model")], "dwelling \(id)")
    }
    let arts = try csv(base + "/artifacts.csv")
    #expect(arts.count == 249 && tables.artifacts.count == 248)
    for r in arts.dropFirst() {
        let a = tables.artifacts[Int(r[0])!]
        #expect(a.slot == r[3] && a.level == r[4] && a.flag == (r[6] != "X"), "artifact \(r[0])")
        #expect(H4GameIdentifiers.artifactKeywords[Int(r[0])!] == r[1])
    }
    let model = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: base + "/artmodel.json"))) as! [String: String]
    #expect(model.count == 197 && tables.artifactModels.count == 197)
    for (k, v) in model { #expect(tables.artifactModels[Int(k)!] == v, "model \(k)") }
    #expect(tables.dwellingPools.values.allSatisfy { !$0.isEmpty } && !tables.dwellingPools[1]!.contains(50))
}

// MARK: - Whole maps (game files)

private func mapFiles() -> [String] {
    let dir = env["H4_MAPS_DIR"]!
    let found = FileManager.default.enumerator(atPath: dir)?.compactMap { $0 as? String }.filter { $0.lowercased().hasSuffix(".h4c") } ?? []
    return found.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
}

@Test(.enabled(if: hasRef)) func gameStartEqualsReferenceOnEveryMap() throws {
    let store = try realStore()
    let tables = try H4GameTables(store: store)
    let maps = mapFiles()
    #expect(maps.count == 105)
    var same = 0
    for seed in [UInt32(1), 12345, 0xC0FFEE] {
        for rel in maps {
            let scenario = try H4Scenario(fileData: Data(contentsOf: URL(fileURLWithPath: env["H4_MAPS_DIR"]! + "/" + rel)))
            let game = try H4GameStart.start(scenario: scenario, store: store, tables: tables, seed: seed, difficulty: 2)
            let name = String(rel.dropLast(4)).replacingOccurrences(of: "/", with: "__")
            let ref = try String(contentsOfFile: "\(env["H4_GAMESTART_REF_DIR"]!)/ref_out/\(seed)/\(name).json", encoding: .utf8)
            if game.canonicalJSON() == ref { same += 1 } else { Issue.record("differs: seed \(seed) \(rel)") }
        }
    }
    #expect(same == 315)
}

/// Digests (FNV-1a 64 of the canonical JSON) of gamestart_ref.py at difficulties 0, 1, 3, 4 (seed 12345).
@Test(.enabled(if: hasMaps)) func otherDifficultiesEqualReferenceDigests() throws {
    let store = try realStore()
    let tables = try H4GameTables(store: store)
    let expected: [(String, Int, UInt64)] = [
        ("A Land without a King", 0, 0x9240a2930c6057e8), ("A Land without a King", 1, 0x33e17e05f6311932),
        ("A Land without a King", 3, 0x578d45d9922b3788), ("A Land without a King", 4, 0xc1eeaaa44b302405),
        ("Contest Maps/Diaspora", 0, 0x57f4895aac2f2369), ("Contest Maps/Diaspora", 1, 0x8f27b488101b04ac),
        ("Contest Maps/Diaspora", 3, 0x5a90b9916f007c49), ("Contest Maps/Diaspora", 4, 0x951dac341001c091),
    ]
    for (map, d, digest) in expected {
        let scenario = try H4Scenario(fileData: Data(contentsOf: URL(fileURLWithPath: env["H4_MAPS_DIR"]! + "/" + map + ".h4c")))
        let game = try H4GameStart.start(scenario: scenario, store: store, tables: tables, seed: 12345, difficulty: d)
        #expect(fnv1a(game.canonicalJSON()) == digest, "\(map) difficulty \(d)")
    }
}

/// G3: every chosen model exists as an adv_object / adv_actor resource.
@Test(.enabled(if: hasMaps)) func everyChosenModelExists() throws {
    let store = try realStore()
    let tables = try H4GameTables(store: store)
    var missing: Set<String> = [], checked = 0
    for seed in [UInt32(1), 12345, 0xC0FFEE] {
        for rel in mapFiles() {
            let scenario = try H4Scenario(fileData: Data(contentsOf: URL(fileURLWithPath: env["H4_MAPS_DIR"]! + "/" + rel)))
            let game = try H4GameStart.start(scenario: scenario, store: store, tables: tables, seed: seed, difficulty: 2)
            for o in game.objects {
                guard let model = o.resolved.model else { continue }
                let resource = model.hasPrefix("adv_actor.") ? model + ".h4d" : "adv_object." + model + ".h4d"
                checked += 1
                if store.locate(resource) == nil { missing.insert(resource) }
            }
        }
    }
    #expect(checked > 10000)
    #expect(missing.isEmpty, "missing: \(missing.sorted())")
}

// MARK: - Robustness: hostile inputs throw H4Error, never trap

private func obj(_ cls: String, _ sub: String?, owner: Int? = nil, place: H4GamePlace? = .unrestricted,
                 town: H4GameStartObject.Town? = nil, mask: Int? = nil) -> H4GameStartObject {
    H4GameStartObject(index: 0, x: 1, y: 1, level: 0, className: cls, subclass: sub, model: "m", owner: owner, place: place,
                      town: town, teacherMask: mask)
}

private func game(_ o: H4GameStartObject, difficulty: Int = 1) throws -> H4Game {
    try H4GameStart.start(input: .init(players: [], objects: [o]), tables: syntheticTables(), seed: 5, difficulty: difficulty)
}

private func expectMalformed(_ body: () throws -> Void, _ what: String) {
    do { try body(); Issue.record("\(what): no error") } catch is H4Error {} catch { Issue.record("\(what): \(error)") }
}

@Test func teacherMaskWithoutAKnownKindThrows() throws {
    for mask in [0x200, 0x400, 0xfe00, 0x10000, 0xffff_fe00] {
        expectMalformed({ _ = try game(obj("random_teacher", "", mask: mask)) }, "mask \(mask)")
    }
    // Valid masks are unchanged; high bits beside a known bit are ignored; mask 0 follows the reference fallback.
    #expect(try game(obj("random_teacher", "", mask: 0x1ff)).canonicalJSON() == game(obj("random_teacher", "", mask: 0xffff)).canonicalJSON())
    #expect(try game(obj("random_teacher", "", mask: 0)).canonicalJSON() == game(obj("random_teacher", "", mask: nil)).canonicalJSON())
    #expect(try game(obj("random_teacher", "", mask: 0x100)).objects[0].resolved.teacher == 8)
}

@Test func subclassCaseDoesNotMatter() throws {
    let lower = try game(obj("random_artifact", "treasure")), upper = try game(obj("random_artifact", "TREASURE"))
    #expect(lower.objects[0].resolved == upper.objects[0].resolved)
    expectMalformed({ _ = try game(obj("random_artifact", "legendary")) }, "unknown artifact level")
    expectMalformed({ _ = try game(obj("random_artifact", nil)) }, "artifact without level")
    let town = H4GameStartObject.Town(name: "T", owner: 6, built: 0, flag: false)
    for sub in ["right", "Right", "RIGHT"] {
        #expect(try game(obj("random_town", sub, owner: 6, place: nil, town: town)).objects[0].resolved.r == 1, "\(sub)")
    }
    #expect(try game(obj("random_town", "Left", owner: 6, place: nil, town: town)).objects[0].resolved.r == 0)
}

@Test func tablesWithZeroExperienceOrNoColumnsThrow() throws {
    let artifacts = H4DataTable(columns: ["Keyword", "Slot", "Level", "Allowed By Default"],
                                rows: H4GameIdentifiers.artifactKeywords.map { [$0, "Torso", "Minor", ""] })
    var rows = H4GameIdentifiers.creatureKeywords.map { [$0, "1", "life", "10"] }
    rows[3][3] = "0"
    expectMalformed({ _ = try H4GameTables(creatures: .init(columns: ["Keyword", "Level", "Alignment", "Experience"], rows: rows),
                                           artifacts: artifacts) }, "experience 0")
    rows[3][3] = "-4"
    expectMalformed({ _ = try H4GameTables(creatures: .init(columns: ["Keyword", "Level", "Alignment", "Experience"], rows: rows),
                                           artifacts: artifacts) }, "negative experience")
    let noColumns = Data([0, 0, 7, 0] + Array("Keyword".utf8) + [1, 0, 0, 0])
    expectMalformed({ _ = try H4DataTable(data: noColumns) }, "0 columns")
}

@Test func emptyDwellingPoolThrows() throws {
    // The synthetic tables only have level 1 creatures: no level 2 dwelling can be drawn.
    expectMalformed({ _ = try game(obj("random_creature_dwelling", "level_2")) }, "empty pool")
    #expect(try game(obj("random_creature_dwelling", "level_1")).objects[0].resolved.creature != nil)
}

@Test func invalidStartInputsThrow() throws {
    for d in [-1, 5, 100] { expectMalformed({ _ = try game(obj("random_monster", "level_1"), difficulty: d) }, "difficulty \(d)") }
    let town = H4GameStartObject.Town(name: "T", owner: 6, built: 0, flag: false)
    expectMalformed({ _ = try game(obj("random_town", "left", owner: nil, town: town)) }, "town without owner")
    expectMalformed({ _ = try game(obj("random_town", "left", owner: 6, town: nil)) }, "town without data")
    expectMalformed({ _ = try game(obj("random_town", "left", owner: 99, town: town)) }, "owner 99")
    for sub in [nil, "", "level", "level_x", "level_0", "level_9", "level_-1"] as [String?] {
        expectMalformed({ _ = try game(obj("random_monster", sub)) }, "monster \(sub ?? "nil")")
        expectMalformed({ _ = try game(obj("random_creature_dwelling", sub)) }, "dwelling \(sub ?? "nil")")
    }
    expectMalformed({ _ = try game(obj("random_shrine", "level")) }, "shrine without level")
    var m = obj("random_monster", "level_1"); m.monsterRange = (9, 3)
    expectMalformed({ _ = try game(m) }, "inverted monster range")
    #expect(try game(obj("random_monster", "level_1"), difficulty: 0).objects.count == 1)
    #expect(try game(obj("random_monster", "level_1"), difficulty: 4).objects.count == 1)
}

/// Crafted copies of real maps (never committed): H4_CRAFT_DIR holds mask200.h4c and case_art2.h4c.
@Test(.enabled(if: hasData && env["H4_CRAFT_DIR"] != nil)) func craftedMapsDoNotTrap() throws {
    let store = try realStore(), tables = try H4GameTables(store: store)
    for name in ["mask200.h4c", "case_art2.h4c"] {
        let scenario = try H4Scenario(fileData: Data(contentsOf: URL(fileURLWithPath: env["H4_CRAFT_DIR"]! + "/" + name)))
        do {
            let g = try H4GameStart.start(scenario: scenario, store: store, tables: tables, seed: 1, difficulty: 2)
            #expect(name == "case_art2.h4c")
            #expect(!g.objects.contains { $0.className == "random_artifact" && $0.subclass != $0.subclass.lowercased() })
        } catch is H4Error { #expect(name == "mask200.h4c") }
    }
}
