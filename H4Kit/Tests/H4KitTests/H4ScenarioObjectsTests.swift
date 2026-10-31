import Foundation
import Testing
@testable import H4Kit

// MARK: - Fixtures

func cat(_ parts: Data...) -> Data { parts.reduce(Data(), +) }
func cat2(_ parts: [Data]) -> Data { parts.reduce(Data(), +) }
func u8s(_ v: UInt8...) -> Data { Data(v) }

/// Minimal `adv_object` resource: version 2, 1×1 footprint, classification triple (sprite omitted;
/// the resolver stops reading after the triple).
func advObjectResource(cls: String, sub: String = "", index: String = "") -> Data {
    cat(le16(2), u8s(0), le16(1), le16(1), u8s(1), u8s(1),
        le16(0), le16(1), str16(cls), le16(2), str16(sub), le16(3), str16(index))
}

func resourceStore(_ models: [String: Data]) throws -> H4ResourceStore {
    let entries = models.map { FixtureEntry(name: "adv_object.\($0.key).h4d", payload: $0.value) }
    return try H4ResourceStore(archives: [H4RArchive(data: buildArchive(entries))])
}

/// Version-29 sections with one header player, every list empty.
func emptySections(extraA: Data = Data(), countA: UInt16 = 0, availability0: Data? = nil) -> Data {
    var d = cat(le16(countA), extraA, le16(0), le16(0), le16(0))
    let defaultBlock = cat(le16(0), u8s(0), le16(0xFFFF))
    for i in 0..<12 { d += (i == 0 ? availability0 : nil) ?? defaultBlock }
    d += u8s(0, 0, 0)                          // player block: colour 0, flag 0, extra
    d += u8s(0, 0, 0, 0)                       // bitset248, blob, set36, bitset188: absent
    d += cat(le16(0), le16(0), le16(0), le16(0))   // two empty bitsets
    for _ in 0..<3 { d += cat(le16(0), le16(0)) }
    return d
}

func record(x: Int32 = 1, y: Int32 = 2, level: Int32 = 0, model: String, cls: String, sub: String = "",
            index: String = "", payload: Data) -> Data {
    cat(le32(UInt32(bitPattern: x)), le32(UInt32(bitPattern: y)), le32(UInt32(bitPattern: level)), u8s(0),
        str16(model), le16(0), le16(1), str16(cls), le16(2), str16(sub), le16(3), str16(index), payload)
}

func objectScenario(sections: Data = emptySections(), count: UInt32? = nil, records: [Data]) -> H4Scenario {
    let c = count ?? UInt32(records.count)
    return try! H4Scenario(scenario: cat(scenarioHeader(size: 8, levels: 1), sections, le32(c), cat2(records)),
                           containerVersion: 22)
}

let testModels: [String: Data] = [
    "deco.Tree": advObjectResource(cls: "decorative"),
    "kelp.Bed": advObjectResource(cls: "kelp_beds"),
    "sanct.Uary": advObjectResource(cls: "sanctuary"),
    "gates.Gate": advObjectResource(cls: "gateway"),
    "signs.Sign": advObjectResource(cls: "sign"),
    "obe.Marker": advObjectResource(cls: "obelisk_marker"),
    "out.Post": advObjectResource(cls: "outpost"),
    "light.House": advObjectResource(cls: "lighthouse"),
    "art.Sword": advObjectResource(cls: "artifact", sub: "sword"),
    "art.Scroll": advObjectResource(cls: "artifact", sub: "Scroll"),
    "town.Castle": advObjectResource(cls: "town", sub: "castle"),
]

func nodeBytes(_ name: String, _ payload: Data = Data()) -> Data { str16(name) + payload }

// MARK: - Sections

@Test func parsesMinimalSections() throws {
    let s = objectScenario(records: [])
    let sections = try H4ScenarioSections(scenario: s)
    #expect(sections.objectListOffset == emptySections().count)
    #expect(sections.availability.count == 12 && sections.availability.allSatisfy { !$0.hasExplicitList && $0.value == 0xFFFF })
    #expect(sections.playerSettings.count == 1 && sections.bitsets.count == 2 && sections.idMaps.count == 3)
    #expect(sections.listA.isEmpty && sections.bitset248 == nil && sections.blob == nil)
}

@Test func parsesScriptsAndAvailabilityLists() throws {
    // List A element: entry (script v2: if(==(lit 5, day), seq[no_op], win 1), text, 7 u32), text, 2 × u16, 2 masks.
    let eq = nodeBytes("==", cat(nodeBytes("lit", le32(5)), nodeBytes("day")))
    let seq = nodeBytes("seq", cat(le16(1), nodeBytes("no_op")))
    let script = cat(le16(2), nodeBytes("if", cat(eq, seq, nodeBytes("win", u8s(1)))))
    let values = cat2((0..<7).map { le32(UInt32($0)) })
    let elementA = cat(le16(0), script, str16("e"), values, str16("x"), le16(3), le16(4), u8s(5, 6))
    let avail = cat(le16(0), u8s(1), le16(0xFFFF), le16(2),
                    le16(0), str16("artifact"), le16(9), le16(1), le16(0),
                    le16(0), str16("material"), u8s(2), le32(77))
    let scenario = objectScenario(sections: emptySections(extraA: elementA, countA: 1, availability0: avail), records: [])
    let sections = try H4ScenarioSections(scenario: scenario)
    #expect(sections.listA.count == 1)
    let a = sections.listA[0]
    #expect(a.entry.script.version == 2 && a.entry.script.root.name == "if" && a.entry.values == [0, 1, 2, 3, 4, 5, 6])
    #expect(a.word1 == 3 && a.word2 == 4 && a.playerMask == 5 && a.flags == 6 && a.text == "x")
    guard case let .node(cond) = a.entry.script.root.operands[0] else { Issue.record("no condition"); return }
    #expect(cond.name == "==" && cond.operands.count == 2)
    let expected: [H4AvailabilityObject] = [.artifact(id: 9, extra1: 1, extra2: 0), .material(resource: 2, amount: 77)]
    #expect(sections.availability[0].objects == expected)
    #expect(sections.objectListOffset == emptySections(extraA: elementA, countA: 1, availability0: avail).count)
}

@Test func rejectsBadSections() {
    func sections(_ d: Data) -> H4Scenario {
        try! H4Scenario(scenario: scenarioHeader(size: 8, levels: 1) + d + le32(0), containerVersion: 22)
    }
    func elementA(node: Data) -> Data {
        le16(0) + le16(2) + node + str16("") + Data(count: 28) + str16("") + Data(count: 6)
    }
    do {
        _ = try H4ScenarioSections(scenario: sections(emptySections(extraA: elementA(node: nodeBytes("rand")), countA: 1)))
        Issue.record("expected failure")
    } catch { #expect("\(error)".contains("rand")) }
    let badAvail = le16(0) + Data([1]) + le16(0) + le16(1) + le16(0) + str16("hero")
    #expect(throws: (any Error).self) { try H4ScenarioSections(scenario: sections(emptySections(availability0: badAvail))) }
    // availability version != 0, bitset too large, id map value outside 1...2
    #expect(throws: (any Error).self) { try H4ScenarioSections(scenario: sections(emptySections(availability0: le16(1) + Data([0]) + le16(0)))) }
    var big = emptySections(); big.replaceSubrange((big.count - 30)..<(big.count - 28), with: le16(0)); big[big.count - 10] = 0
    #expect(throws: (any Error).self) { try H4ScenarioSections(scenario: sections(big.prefix(big.count - 12) + le16(0) + le16(249) + Data(count: 40))) }
    #expect(throws: (any Error).self) { try H4ScenarioSections(scenario: sections(emptySections().dropLast(12) + le16(0) + le16(1) + le16(3) + Data([9]) + le16(0) + le16(0) + le16(0) + le16(0))) }
    // deeply nested expression must fail cleanly instead of overflowing the stack
    let deep = Data((0..<5000).map { _ in nodeBytes("and") }.joined())
    #expect(throws: (any Error).self) { try H4ScenarioSections(scenario: sections(emptySections(extraA: elementA(node: deep), countA: 1))) }
}

@Test func rejectsUnsupportedScenarioVersions() throws {
    // Version-26 header: no u16 after the version, no version-27 string, no version-29 flag.
    let header = le16(26) + scenarioHeader(size: 8, levels: 1).dropFirst(4).dropLast(3)
    let s = try H4Scenario(scenario: header + emptySections() + le32(0), containerVersion: 22)
    #expect(throws: (any Error).self) { try H4ScenarioSections(scenario: s) }
}

// MARK: - Objects

@Test func decodesEveryReaderFamily() throws {
    let store = try resourceStore(testModels)
    let records = [
        record(x: 3, y: 4, level: 1, model: "deco.Tree", cls: "decorative", payload: le16(0)),
        record(model: "kelp.Bed", cls: "kelp_beds", payload: le16(0)),                     // unregistered class
        record(model: "sanct.Uary", cls: "sanctuary", payload: le16(0)),
        record(model: "gates.Gate", cls: "gateway", payload: le16(0)),
        record(model: "gates.Gate", cls: "gateway", payload: le16(1) + str16("north")),
        record(model: "signs.Sign", cls: "sign", payload: le16(1) + str16("Beware")),
        record(model: "obe.Marker", cls: "obelisk_marker", payload: le16(1) + le16(7)),
        record(model: "out.Post", cls: "outpost", payload: le16(1) + Data([5])),
        record(model: "light.House", cls: "lighthouse", payload: le16(2) + Data([6]) + le16(0)),
        record(model: "art.Sword", cls: "artifact", sub: "sword", payload: le16(0)),
    ]
    let scenario = objectScenario(records: records)
    let body = try H4ScenarioBody(scenario: scenario, resources: store)
    #expect(body.declaredCount == 10 && body.objects.count == 10)
    #expect(body.stop == .complete(endOffset: scenario.body.count))
    #expect(body.objectListOffset == emptySections().count)
    let o = body.objects
    #expect((o[0].x, o[0].y, o[0].level, o[0].modelName, o[0].className) == (3, 4, 1, "deco.Tree", "decorative"))
    #expect(o[1].className == "kelp_beds" && o[2].className == "sanctuary" && o[2].classID == 75)
    #expect(o[3].payload == .gateway(version: 0, name: nil) && o[4].payload == .gateway(version: 1, name: "north"))
    #expect(o[5].payload == .sign(version: 1, message: "Beware"))
    #expect(o[6].payload == .obeliskMarker(version: 1, value: 7) && o[7].payload == .outpost(version: 1, owner: 5))
    #expect(o[8].payload == .ownedScriptable(H4OwnedObject(version: 2, owner: 6, scriptObjects: [])) && o[9].className == "artifact")
    #expect(o[0].triple?.className == "decorative" && o[0].offset == body.objectListOffset + 4)
}

@Test func stopsOnClassesWithoutReader() throws {
    let store = try resourceStore(familyModels)
    let deco = record(model: "deco.Tree", cls: "decorative", payload: le16(0))
    func stop(_ extra: Data) throws -> (Int, H4ObjectListStop, Int) {
        let b = try H4ScenarioBody(scenario: objectScenario(count: 2, records: [deco, extra]), resources: store)
        return (b.objects.count, b.stop, b.objectListOffset + 4 + deco.count)
    }
    // a school of a subclass without a reader stops before its payload, nothing is skipped
    let (n, st, at) = try stop(record(model: "school.Odd", cls: "school", sub: "unknown_school", payload: le16(0)))
    #expect(n == 1 && st == .stopped(recordOffset: at, reason: .unsupportedClass(id: 76, name: "school")))
    #expect(H4ObjectStopReason.unsupportedClass(id: 76, name: "school").description == "reader missing for class 76 school")
    // every one of the 105 classes has a reader, except that school
    #expect(H4ObjectClasses.names.count == 105)
    let named: [(Int, String)] = [(0, "abandoned_mine"), (4, "artifact"), (13, "carryover_hero"), (18, "conservatory"),
        (21, "creature_dwelling"), (32, "garrison"), (44, "mine"), (56, "prison"), (57, "quest_gate"), (58, "quest_guard"),
        (61, "random_creature_dwelling"), (62, "random_conservatory"), (64, "random_monster"), (66, "random_random_monster"),
        (67, "random_shrine"), (69, "random_teacher"), (70, "random_temple"), (72, "random_town"),
        (73, "random_weekly_material_generator"), (76, "school"), (77, "seers_hut"), (82, "shrine"), (95, "town"),
        (102, "weekly_material_generator")]
    for (id, name) in named { #expect(H4ObjectClasses.names[id] == name) }
}

@Test func rejectsInconsistentRecords() throws {
    let store = try resourceStore(testModels)
    func run(_ r: [Data], count: UInt32? = nil) throws -> H4ScenarioBody {
        try H4ScenarioBody(scenario: objectScenario(count: count, records: r), resources: store)
    }
    // file triple differs from the resource's (class, subclass, index)
    #expect(throws: (any Error).self) { try run([record(model: "deco.Tree", cls: "bridge", payload: le16(0))]) }
    #expect(throws: (any Error).self) { try run([record(model: "deco.Tree", cls: "decorative", sub: "x", payload: le16(0))]) }
    #expect(throws: (any Error).self) { try run([record(model: "deco.Tree", cls: "decorative", index: "x", payload: le16(0))]) }
    // case differences are fine (names compared case-insensitively, lookups too)
    _ = try run([record(model: "DECO.tree", cls: "Decorative", payload: le16(0))])
    // model without resource
    #expect(throws: (any Error).self) { try run([record(model: "nope.Missing", cls: "decorative", payload: le16(0))]) }
    // bad payload values
    #expect(throws: (any Error).self) { try run([record(model: "deco.Tree", cls: "decorative", payload: le16(1))]) }
    #expect(throws: (any Error).self) { try run([record(model: "gates.Gate", cls: "gateway", payload: le16(2))]) }
    #expect(throws: (any Error).self) { try run([record(model: "out.Post", cls: "outpost", payload: le16(1) + Data([7]))]) }
    #expect(throws: (any Error).self) { try run([record(model: "light.House", cls: "lighthouse", payload: le16(3))]) }
    // a validity failure names the record it happened in
    do { _ = try run([record(model: "deco.Tree", cls: "decorative", payload: le16(0)),
                      record(model: "gates.Gate", cls: "gateway", payload: le16(2))]); Issue.record("expected failure") }
    catch { #expect("\(error)".contains("object at body offset") && "\(error)".contains("gateway")) }
    // record count larger than the data
    #expect(throws: (any Error).self) { try run([record(model: "deco.Tree", cls: "decorative", payload: le16(0))], count: 2) }
}

@Test func resourceWithoutKnownClassIsRejected() throws {
    let store = try resourceStore(["odd.Thing": advObjectResource(cls: "not_a_class")])
    let s = objectScenario(records: [record(model: "odd.Thing", cls: "not_a_class", payload: le16(0))])
    #expect(throws: (any Error).self) { try H4ScenarioBody(scenario: s, resources: store) }
}

@Test func hostileObjectListsFailFast() throws {
    let store = try resourceStore(testModels)
    let clock = ContinuousClock()
    let elapsed = try clock.measure {
        for count in [UInt32(100_001), 0xFFFF_FFFF, 5_000_000] {
            #expect(throws: (any Error).self) { try H4ScenarioBody(scenario: objectScenario(count: count, records: []), resources: store) }
        }
        // every truncation of a valid body throws or stops cleanly, never traps
        let full = [record(model: "deco.Tree", cls: "decorative", payload: le16(0)),
                    record(model: "signs.Sign", cls: "sign", payload: le16(1) + str16("Beware")),
                    record(model: "light.House", cls: "lighthouse", payload: le16(2) + Data([6]) + le16(0))]
        let whole = scenarioHeader(size: 8, levels: 1) + emptySections() + le32(3) + full.reduce(Data(), +)
        let headerLength = scenarioHeader(size: 8, levels: 1).count
        for cut in headerLength..<whole.count {
            let s = try H4Scenario(scenario: whole.prefix(cut), containerVersion: 22)
            #expect(throws: (any Error).self) { try H4ScenarioBody(scenario: s, resources: store) }
        }
        // a list claiming 100 000 records with data for two
        let big = objectScenario(count: 100_000, records: Array(full.prefix(2)))
        #expect(throws: (any Error).self) { try H4ScenarioBody(scenario: big, resources: store) }
    }
    #expect(elapsed < .seconds(1))
}

// MARK: - Real data

private var realDirs: (data: URL, maps: URL)? {
    guard let d = ProcessInfo.processInfo.environment["H4_DATA_DIR"] else { return nil }
    let data = URL(fileURLWithPath: d)
    let maps = ProcessInfo.processInfo.environment["H4_MAPS_DIR"].map { URL(fileURLWithPath: $0) }
        ?? data.deletingLastPathComponent().appendingPathComponent("maps")
    return (data, maps)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["H4_DATA_DIR"] != nil))
func realMapObjects() throws {
    let dirs = try #require(realDirs)
    let resolver = H4ObjectClassResolver(resources: try H4ResourceStore(dataDirectory: dirs.data))
    func scenario(_ rel: String) throws -> H4Scenario {
        try H4Scenario(fileData: Data(contentsOf: dirs.maps.appendingPathComponent(rel)))
    }
    let king = try H4ScenarioBody(scenario: scenario("A Land without a King.h4c"), resolver: resolver)
    #expect(king.objectListOffset == 192 && king.declaredCount == 3213 && king.objects.count == 3213)
    #expect(king.stop == .complete(endOffset: 233260))
    let bandits = try H4ScenarioBody(scenario: scenario("Bandits of the Rifen Maze.h4c"), resolver: resolver)
    #expect(bandits.objectListOffset == 1039 && bandits.objects.count == 5007 && bandits.stop == .complete(endOffset: 384842))

    // Whole population (recursive): every header, section list and object list decodes, and the
    // object list ends exactly where the terrain starts.
    let paths = FileManager.default.enumerator(atPath: dirs.maps.path)!.compactMap { $0 as? String }.filter { $0.hasSuffix(".h4c") }
    #expect(paths.count == 105)
    var classes = Set<String>(), heroes = 0, named = 0, towns = 0
    for rel in paths {
        let s = try scenario(rel)
        let b = try H4ScenarioBody(scenario: s, resolver: resolver)
        #expect(b.objects.count == b.declaredCount, "\(rel)")
        #expect(b.stop == .complete(endOffset: try H4ScenarioTerrain(scenario: s).start), "\(rel)")
        for o in b.objects {
            classes.insert(o.className)
            if case let .town(t) = o.payload { towns += 1; #expect(t.town.owner <= 6) }
            if case let .army(a) = o.payload, let army = a.army {
                for case let .hero(h) in army.slots {
                    heroes += 1
                    if !h.name.isEmpty { named += 1; #expect(h.name.count <= 40, "name before biography? \(h.name.prefix(50))") }   // biography comes first in the file
                }
            }
        }
    }
    #expect(classes.count > 60 && heroes > 100 && named > 20 && towns > 100)
    // maps whose header carries victory/defeat cinematics (rejected before) now load
    #expect(try paths.filter { try scenario($0).victoryCinematic != nil || scenario($0).defeatCinematic != nil }.count >= 1)
}
