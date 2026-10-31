import Foundation
import Testing
@testable import H4Kit

// Synthetic records for every decoded object family, the script grammar, and hostile inputs.

// MARK: - Builders

func scriptBytes(_ root: Data = nodeBytes("seq", le16(0))) -> Data { le16(2) + root }
func entryBytes(_ script: Data = scriptBytes(), text: String = "") -> Data {
    script + str16(text) + cat2((0..<7).map { le32(UInt32($0)) })
}
func triggerBytes() -> Data { le16(0) + entryBytes() + u8s(1, 2) }
func timedBytes() -> Data { le16(0) + entryBytes() + str16("t") + le16(3) + le16(4) + u8s(5, 6) }
func objectBytes(_ text: String = "o") -> Data { le16(0) + entryBytes() + str16(text) + u8s(7, 1) }
func continuousBytes() -> Data { le16(0) + scriptBytes() + str16("c") + u8s(1, 2, 3) }
/// Event block: `triggers` triggers then three counted lists (n1 timed, n2 objects, n3 continuous) in the given order.
func eventBytes(triggers: Int, order: [Character] = ["t", "o", "c"], timed: Int = 0, objects: Int = 0, continuous: Int = 0) -> Data {
    var d = cat2((0..<triggers).map { _ in triggerBytes() })
    for k in order {
        switch k {
        case "t": d += le16(UInt16(timed)) + cat2((0..<timed).map { _ in timedBytes() })
        case "o": d += le16(UInt16(objects)) + cat2((0..<objects).map { _ in objectBytes() })
        default: d += le16(UInt16(continuous)) + cat2((0..<continuous).map { _ in continuousBytes() })
        }
    }
    return d
}
func artifactBytes(_ id: UInt16, spell: UInt16 = 0) -> Data { le16(id) + ([0x7c, 0xa6].contains(id) ? le16(spell) : Data()) }
func stackBytes(version: UInt16 = 1, creature: Int16 = 5, count: Int16 = 12, artifacts: [Data] = [artifactBytes(3)]) -> Data {
    le16(version) + le16(UInt16(bitPattern: creature)) + le16(UInt16(bitPattern: count))
        + (version >= 1 ? le16(UInt16(artifacts.count)) + cat2(artifacts) : Data())
}
func heroBytes(version: UInt16 = 10) -> Data {
    var d = le16(version) + le16(0xFFFF) + u8s(3, 0)                       // portrait -1, class 3, gender 0
    d += u8s(1) + (version >= 10 ? u8s(1, 2) : le16(1) + le16(2)) + u8s(3, 4)   // field 6a0, four bonuses
    d += str16("bio") + str16("Hero")
    d += u8s(1) + Data((0..<36).map { UInt8(bitPattern: Int8($0 % 5 - 1)) })     // skills
    d += u8s(2) + Data(repeating: 0xAA, count: 24)                             // spells
    for slot in 0..<14 { d += slot == 2 ? u8s(1) + artifactBytes(0x7c, spell: 9) : u8s(0) }
    d += le16(1) + artifactBytes(4)                                            // backpack
    d += eventBytes(triggers: 3, timed: 1)
    return d + (version >= 9 ? u8s(9) : Data())
}
func armyBytes(_ slots: [Data?] = [nil, nil, nil, nil, nil, nil, nil]) -> Data {
    le16(0) + cat2(slots.map { $0.map { $0 } ?? u8s(0xFF) })
}
func richArmy() -> Data {
    armyBytes([u8s(0) + stackBytes(), nil, u8s(1) + heroBytes(), u8s(0) + stackBytes(version: 0), nil, nil, nil])
}
func spellSetBytes(_ v: UInt8 = 2) -> Data { u8s(v) + Data(repeating: 0x55, count: v == 0 ? 23 : 24) }
func placementBytes(_ kind: String, _ extra: Data = Data()) -> Data { le16(0) + str16(kind) + extra }
func questCoreBytes() -> Data {
    str16("a") + str16("b") + str16("c") + str16("d") + scriptBytes(nodeBytes("win", u8s(1)))
        + le16(1) + nodeBytes("true")
}

let familyModels: [String: Data] = testModels.merging([
    "mine.Gold": advObjectResource(cls: "mine"), "garr.Ison": advObjectResource(cls: "garrison"),
    "aband.Mine": advObjectResource(cls: "abandoned_mine"), "dwell.Ing": advObjectResource(cls: "creature_dwelling"),
    "rdw.Elling": advObjectResource(cls: "random_creature_dwelling"),
    "weekly.Gen": advObjectResource(cls: "weekly_material_generator"),
    "cons.Erv": advObjectResource(cls: "conservatory"), "rcons.Erv": advObjectResource(cls: "random_conservatory"),
    "qgate.A": advObjectResource(cls: "quest_gate"), "qguard.A": advObjectResource(cls: "quest_guard"),
    "seer.A": advObjectResource(cls: "seers_hut"),
    "school.U": advObjectResource(cls: "school", sub: "magic_university"),
    "school.W": advObjectResource(cls: "school", sub: "beastmasters_hut"),
    "school.Odd": advObjectResource(cls: "school", sub: "unknown_school"),
    "shrine.A": advObjectResource(cls: "shrine"), "rshrine.A": advObjectResource(cls: "random_shrine"),
    "rteach.A": advObjectResource(cls: "random_teacher"), "rtemple.A": advObjectResource(cls: "random_temple"),
    "parch.A": advObjectResource(cls: "artifact", sub: "parchment"),
    "rmon.A": advObjectResource(cls: "random_monster"), "rrmon.A": advObjectResource(cls: "random_random_monster"),
    "carry.A": advObjectResource(cls: "carryover_hero"), "prison.A": advObjectResource(cls: "prison"),
    "rtown.A": advObjectResource(cls: "random_town"),
]) { a, _ in a }

/// A town of the given owner/name, abstract version 8, nothing optional set.
func abstractTownBytes(version: UInt16 = 8, owner: UInt8 = 2, garrison: Bool = false, customBuildings: Bool = false) -> Data {
    var d = u8s(owner) + str16("Castleton")
    d += garrison ? u8s(1) + richArmy() : u8s(0)
    d += customBuildings ? u8s(1) + Data([1, 2, 3, 4, 5, 6]) + Data([7, 8, 9, 10, 11, 12]) : u8s(0, 1)
    d += eventBytes(triggers: 4, timed: 1, objects: 1, continuous: 1)
    if version >= 7 { d += u8s(1) + u8s(0) + Data(count: 5) + u8s(0) + Data(count: 5) }
    if version >= 8 { d += u8s(4) }
    return d
}

func body(_ records: [Data], count: UInt32? = nil) throws -> H4ScenarioBody {
    try H4ScenarioBody(scenario: objectScenario(count: count, records: records), resources: resourceStore(familyModels))
}

// MARK: - Script grammar

@Test func scriptGrammarTableSizes() {
    #expect(H4ScriptGrammar.actions.count == 54 - 0 && H4ScriptGrammar.numbers.count == 21 && H4ScriptGrammar.booleans.count == 24)
}

@Test func decodesScriptNodesOfEveryKind() throws {
    let resources = cat2((0..<7).map { le32(UInt32(bitPattern: Int32(-$0))) })
    let nodes: [Data] = [
        nodeBytes("text", str16("hi") + le16(2) + nodeBytes("no_op") + nodeBytes("rem_this")),
        nodeBytes("give_material", u8s(8) + resources),
        nodeBytes("give_artifact", u8s(3) + le16(2) + artifactBytes(0xa6, spell: 7) + artifactBytes(10)),
        nodeBytes("combat", u8s(2) + richArmy() + nodeBytes("win", u8s(0)) + nodeBytes("lose", u8s(1))),
        nodeBytes("if", nodeBytes("has_artifact", u8s(1, 8) + artifactBytes(5)) + nodeBytes("no_op")
                  + nodeBytes("set_num", str16("n") + nodeBytes("+", nodeBytes("rand", le32(1) + le32(6)) + nodeBytes("neg", nodeBytes("lit", le32(0xFFFF_FFFF)))))),
        nodeBytes("ask", str16("q") + nodeBytes("inc_exp", u8s(9) + le32(100)) + nodeBytes("give_skill", u8s(0, 35, 4))),
        nodeBytes("set_bool", str16("b") + nodeBytes("and", nodeBytes("<=", nodeBytes("day") + nodeBytes("creatures", u8s(0) + le16(73)))
                                                      + nodeBytes("not", nodeBytes("is_dead", str16("Bob"))))),
    ]
    let script = le16(2) + nodeBytes("seq", le16(UInt16(nodes.count)) + cat2(nodes))
    var r = ByteReader(script)
    let parsed = try H4Script.read(&r)
    #expect(r.remaining == 0 && parsed.version == 2 && parsed.root.kind == .action && parsed.root.name == "seq")
    guard case let .nodes(list) = parsed.root.operands[0] else { Issue.record("seq"); return }
    #expect(list.map(\.name) == ["text", "give_material", "give_artifact", "combat", "if", "ask", "set_bool"])
    #expect(list[0].operands == [.text("hi"), .nodes([nodeless("no_op"), nodeless("rem_this")])])
    #expect(list[1].operands == [.byte(8), .resources([0, -1, -2, -3, -4, -5, -6])])
    #expect(list[2].operands == [.byte(3), .artifacts([H4ArtifactRef(id: 0xa6, spell: 7), H4ArtifactRef(id: 10, spell: nil)])])
    guard case let .army(army) = list[3].operands[1] else { Issue.record("army"); return }
    #expect(army.slots.count == 7 && army.slots[1] == .empty)
    if case let .hero(h) = army.slots[2] { #expect(h.name == "Hero" && h.biography == "bio") } else { Issue.record("hero") }
    guard case let .node(cond) = list[4].operands[0] else { Issue.record("cond"); return }
    #expect(cond.kind == .boolean && cond.operands[2] == .artifact(H4ArtifactRef(id: 5, spell: nil)))
    guard case let .node(setNum) = list[4].operands[2], case let .node(sum) = setNum.operands[1] else { Issue.record("set_num"); return }
    #expect(sum.kind == .numeric && sum.name == "+")
    guard case let .node(neg) = sum.operands[1], case let .node(lit) = neg.operands[0] else { Issue.record("neg"); return }
    #expect(lit.operands == [.int(-1)])
}

func nodeless(_ name: String) -> H4ScriptNode { H4ScriptNode(kind: .action, name: name, operands: []) }

@Test func scriptGrammarEnforcesTheGameChecks() {
    func fails(_ node: Data, version: UInt16 = 2) -> Bool {
        var r = ByteReader(le16(version) + node)
        return (try? H4Script.read(&r)) == nil
    }
    #expect(!fails(nodeBytes("build", u8s(42))) && fails(nodeBytes("build", u8s(43))))
    #expect(fails(nodeBytes("change_owner", u8s(7))) && fails(nodeBytes("inc_morale", u8s(4, 0))))
    #expect(!fails(nodeBytes("win", u8s(8))) && fails(nodeBytes("win", u8s(9))) && fails(nodeBytes("win", u8s(8)), version: 1))
    #expect(fails(nodeBytes("give_creature", u8s(0) + le16(74) + le16(1))) && fails(nodeBytes("give_spell", u8s(0) + le16(188))))
    #expect(fails(nodeBytes("give_skill", u8s(0, 36, 0))) && fails(nodeBytes("give_skill", u8s(10, 0, 0))))
    #expect(fails(nodeBytes("give_artifact", u8s(0) + le16(1) + le16(0xf9))) && fails(nodeBytes("give_artifact", u8s(0) + le16(1) + le16(0x7c) + le16(0xbd))))
    #expect(fails(nodeBytes("if", nodeBytes("is_dead", str16("")) + nodeBytes("no_op") + nodeBytes("no_op"))))
    #expect(fails(nodeBytes("combat", u8s(3) + armyBytes() + nodeBytes("no_op") + nodeBytes("no_op"))))
    #expect(fails(nodeBytes("combat", u8s(0) + armyBytes([u8s(2)] + Array(repeating: nil, count: 6)) + nodeBytes("no_op") + nodeBytes("no_op"))))
    // names are per kind: boolean "and" is no action, "!=" does not exist, operators are not actions
    #expect(fails(nodeBytes("and")) && fails(nodeBytes("!=")) && fails(nodeBytes("+")) && fails(nodeBytes("")))
    #expect(fails(nodeBytes("if", nodeBytes("day") + nodeBytes("no_op") + nodeBytes("no_op"))))   // numeric where boolean expected
}

@Test func deepScriptNestingFailsCleanly() {
    let deepIf = Data((0..<3000).map { _ in nodeBytes("if", nodeBytes("true") + nodeBytes("no_op")) }.joined())
    var r = ByteReader(le16(2) + deepIf)
    #expect(throws: (any Error).self) { try H4Script.read(&r) }
    // combat -> army -> hero -> events -> script -> combat ...
    var inner = nodeBytes("no_op")
    for _ in 0..<200 {
        let hero = heroBytes().replacingScript(with: inner)
        inner = nodeBytes("combat", u8s(0) + armyBytes([u8s(1) + hero] + Array(repeating: nil, count: 6)) + nodeBytes("no_op") + nodeBytes("no_op"))
    }
    var r2 = ByteReader(le16(2) + inner)
    #expect(throws: (any Error).self) { try H4Script.read(&r2) }
}

extension Data {
    /// Replaces the script of the first hero trigger (the first `seq` root) with `node`.
    func replacingScript(with node: Data) -> Data {
        let seq = scriptBytes()
        let at = (0..<(count - seq.count)).first { Data(self[$0..<($0 + seq.count)]) == seq }!
        return prefix(at) + le16(2) + node + dropFirst(at + seq.count)
    }
}

// MARK: - Object families

@Test func decodesAnonymousArmies() throws {
    func armyRecord(_ payload: Data) -> Data { le32(5) + le32(UInt32(bitPattern: -6)) + le32(1) + u8s(1) + payload }
    let v9 = le16(9) + u8s(3) + richArmy() + u8s(1, 7, 8) + eventBytes(triggers: 3) + u8s(5, 2, 1)
    let b = try body([armyRecord(v9), armyRecord(le16(0)), armyRecord(le16(2) + u8s(6) + u8s(1) + armyBytes([nil, nil]).prefix(2) + u8s(0) + stackBytes())])
    #expect(b.objects.count == 3 && b.stop == .complete(endOffset: b.stop.offset))
    let o = b.objects
    #expect(o[0].classID == H4ScenarioObject.armyClassID && o[0].className == "army" && o[0].triple == nil && o[0].modelName == "")
    #expect((o[0].x, o[0].y, o[0].level) == (5, -6, 1))
    guard case let .army(a) = o[0].payload else { Issue.record("army"); return }
    #expect(a.version == 9 && a.owner == 3 && a.behaviour == [7, 8] && a.ai == 5 && a.byte8 == 2 && a.flag9 == 1)
    guard let army = a.army, case let .stack(stack) = army.slots[0], case let .hero(hero) = army.slots[2] else { Issue.record("slots"); return }
    #expect(stack == H4CreatureStack(version: 1, creature: 5, count: 12, artifacts: [H4ArtifactRef(id: 3, spell: nil)]))
    #expect(hero.version == 10 && hero.portrait == -1 && hero.heroClass == 3 && hero.statBonuses == [1, 2, 3, 4] && hero.name == "Hero")
    #expect(hero.equipment.count == 14 && hero.equipment[2] == H4ArtifactRef(id: 0x7c, spell: 9) && hero.backpack.count == 1)
    #expect(hero.skills?.count == 36 && hero.spells?.bytes.count == 24 && hero.events.timed.count == 1 && hero.flag == 9)
    #expect(hero.events.triggers.count == 3 && hero.events.timed[0].word1 == 3 && hero.events.triggers[0].playerMask == 1)
    guard case let .army(zero) = o[1].payload else { return }
    #expect(zero.version == 0 && zero.army == nil)
    guard case let .army(old) = o[2].payload else { Issue.record("old"); return }
    #expect(old.version == 2 && old.owner == 6 && old.army?.slots.count == 7)
}

@Test func decodesOwnedAndGarrisonObjects() throws {
    let b = try body([
        record(model: "mine.Gold", cls: "mine", payload: le16(2) + u8s(1, 1) + eventBytes(triggers: 4, order: ["c", "t", "o"], timed: 1, objects: 2, continuous: 1) + u8s(1) + richArmy()),
        record(model: "garr.Ison", cls: "garrison", payload: le16(2) + u8s(6) + eventBytes(triggers: 4, order: ["c", "t", "o"]) + u8s(0)),
        record(model: "garr.Ison", cls: "garrison", payload: le16(0)),
        record(model: "garr.Ison", cls: "garrison", payload: le16(1) + u8s(3)),
        record(model: "aband.Mine", cls: "abandoned_mine", payload: le16(1) + eventBytes(triggers: 4, order: ["c", "t", "o"]) + u8s(1) + armyBytes()),
        record(model: "aband.Mine", cls: "abandoned_mine", payload: le16(0) + u8s(0)),
        record(model: "dwell.Ing", cls: "creature_dwelling", payload: le16(2) + u8s(4) + le16(1) + objectBytes()),
        record(model: "weekly.Gen", cls: "weekly_material_generator", payload: le16(1) + u8s(2)),
        record(model: "rdw.Elling", cls: "random_creature_dwelling", payload: le16(3) + u8s(1) + le16(0) + placementBytes("player", u8s(3))),
        record(model: "rdw.Elling", cls: "random_creature_dwelling", payload: le16(2) + u8s(5) + placementBytes("town", str16("Home"))),
        record(model: "rdw.Elling", cls: "random_creature_dwelling", payload: le16(0)),
        record(model: "cons.Erv", cls: "conservatory", payload: le16(1) + spellSetBytes(1) + spellSetBytes(2)),
        record(model: "rcons.Erv", cls: "random_conservatory", payload: le16(2) + spellSetBytes(0) + spellSetBytes(2) + placementBytes("none")),
        record(model: "rcons.Erv", cls: "random_conservatory", payload: le16(1) + placementBytes("none")),
    ])
    #expect(b.objects.count == 14 && b.stop == .complete(endOffset: b.stop.offset))
    let o = b.objects.map(\.payload)
    guard case let .garrison(mine) = o[0] else { Issue.record("mine"); return }
    #expect(mine.owner == 1 && mine.flag == 1 && mine.events.triggers.count == 4 && mine.events.timed.count == 1)
    #expect(mine.events.scriptObjects.count == 2 && mine.events.continuous.count == 1 && mine.army?.slots.count == 7)
    guard case let .garrison(neutral) = o[1], case let .garrison(v0) = o[2], case let .garrison(v1) = o[3] else { return }
    #expect(neutral.owner == 6 && neutral.flag == nil && neutral.army == nil && v0.owner == 6 && v1.owner == 3 && v1.flag == nil)
    guard case let .abandonedMine(am) = o[4], case let .abandonedMine(am0) = o[5] else { Issue.record("aband"); return }
    #expect(am.events.triggers.count == 4 && am.army != nil && am0.army == nil && am0.events == .empty)
    #expect(o[6] == .ownedScriptable(H4OwnedObject(version: 2, owner: 4, scriptObjects: [H4ScriptObject(
        entry: try entry(), text: "o", playerMask: 7, flags: 1)])))
    #expect(o[7] == .ownedScriptable(H4OwnedObject(version: 1, owner: 2, scriptObjects: [])))
    guard case let .randomDwelling(d3) = o[8], case let .randomDwelling(d2) = o[9], case let .randomDwelling(d0) = o[10] else { return }
    #expect(d3.owner == 1 && d3.placement == .player(3) && d2.owner == 5 && d2.placement == .town("Home") && d0.owner == 6 && d0.placement == nil)
    guard case let .conservatory(c1) = o[11], case let .conservatory(c2) = o[12], case let .conservatory(c3) = o[13] else { return }
    #expect(c1.spellSets.count == 2 && c1.spellSets[0].bytes.count == 24 && c2.spellSets[0].bytes.count == 23 && c2.placement == H4PlacementSpec.none)
    #expect(c3.spellSets.isEmpty && c3.placement == H4PlacementSpec.none)
}

func entry() throws -> H4ScriptEntry {
    var r = ByteReader(entryBytes())
    return try H4ScriptEntry.read(&r)
}

@Test func decodesQuestAndSiteObjects() throws {
    let spell = UInt32(77)
    let b = try body([
        record(model: "qgate.A", cls: "quest_gate", payload: le16(1) + questCoreBytes()),
        record(model: "qgate.A", cls: "quest_gate", payload: le16(0)),
        record(model: "qguard.A", cls: "quest_guard", payload: le16(2) + questCoreBytes() + str16("g") + scriptBytes(nodeBytes("lose", u8s(0)))),
        record(model: "qguard.A", cls: "quest_guard", payload: le16(0)),
        record(model: "seer.A", cls: "seers_hut", payload: le16(2) + questCoreBytes() + str16("s") + scriptBytes() + str16("s2")),
        record(model: "seer.A", cls: "seers_hut", payload: le16(1) + questCoreBytes() + str16("s") + str16("s2") + scriptBytes()),
        record(model: "school.U", cls: "school", sub: "magic_university", payload: le16(1) + u8s(0) + Data(count: 5) + u8s(0) + Data([1, 2, 3, 4, 5])),
        record(model: "school.W", cls: "school", sub: "beastmasters_hut", payload: le16(0)),
        record(model: "shrine.A", cls: "shrine", payload: le16(2) + spellSetBytes(2)),
        record(model: "shrine.A", cls: "shrine", payload: le16(1) + Data(count: 23)),
        record(model: "shrine.A", cls: "shrine", payload: le16(0)),
        record(model: "rshrine.A", cls: "random_shrine", payload: le16(3) + spellSetBytes(0) + placementBytes("town", str16("T"))),
        record(model: "rteach.A", cls: "random_teacher", payload: le16(1) + le16(0x1f) + placementBytes("none")),
        record(model: "rteach.A", cls: "random_teacher", payload: le16(0)),
        record(model: "rtemple.A", cls: "random_temple", payload: le16(1) + placementBytes("player", u8s(2))),
        record(model: "parch.A", cls: "artifact", sub: "parchment", payload: le16(1) + le32(spell)),
        record(model: "art.Scroll", cls: "artifact", sub: "Scroll", payload: le16(0)),
    ])
    #expect(b.objects.count == 17 && b.stop == .complete(endOffset: b.stop.offset))
    let o = b.objects.map(\.payload)
    guard case let .quest(gate) = o[0], case let .quest(gate0) = o[1] else { return }
    #expect(gate.kind == .gate && gate.core?.texts == ["a", "b", "c", "d"] && gate.core?.script.root.name == "win" && gate.core?.condition.root.name == "true")
    #expect(gate0.core == nil)
    guard case let .quest(guardian) = o[2], case let .quest(guard0) = o[3] else { return }
    #expect(guardian.text == "g" && guardian.script?.root.name == "lose" && guard0.core == nil)
    guard case let .quest(hut2) = o[4], case let .quest(hut1) = o[5] else { return }
    #expect(hut2.text == "s" && hut2.text2 == "s2" && hut2.script?.root.name == "seq" && hut1.text2 == "s2" && hut1.script?.root.name == "seq")
    guard case let .school(school) = o[6], case let .school(school0) = o[7] else { return }
    #expect(school.skillSets.count == 2 && school.skillSets[1].bytes == Data([1, 2, 3, 4, 5]) && school.skillSets[0].bitCount == 36 && school0.skillSets.isEmpty)
    guard case let .shrine(s2) = o[8], case let .shrine(s1) = o[9], case let .shrine(s0) = o[10], case let .shrine(rs) = o[11] else { return }
    #expect(s2.spells?.version == 2 && s1.spells?.version == 0 && s1.spells?.bytes.count == 23 && s0.spells == nil && rs.placement == .town("T"))
    #expect(o[12] == .randomTeacher(H4RandomTeacher(version: 1, allowedMask: 0x1f, placement: H4PlacementSpec.none)))
    #expect(o[13] == .randomTeacher(H4RandomTeacher(version: 0, allowedMask: 0x1ff, placement: nil)))
    #expect(o[14] == .randomTemple(version: 1, placement: .player(2)) && o[15] == .spellArtifact(version: 1, spell: 77) && o[16] == .spellArtifact(version: 0, spell: nil))
}

@Test func decodesMonstersHeroesAndTowns() throws {
    let b = try body([
        record(model: "rmon.A", cls: "random_monster", payload: le16(4) + u8s(1, 1, 3) + eventBytes(triggers: 3) + placementBytes("none") + le32(2) + le32(9)),
        record(model: "rrmon.A", cls: "random_random_monster", payload: le16(4) + u8s(0) + eventBytes(triggers: 3) + placementBytes("player", u8s(1)) + le32(0) + le32(0)),
        record(model: "rmon.A", cls: "random_monster", payload: le16(0)),
        record(model: "carry.A", cls: "carryover_hero", payload: le16(2) + u8s(2) + str16("Tarnum") + u8s(1, 4, 5) + eventBytes(triggers: 3)),
        record(model: "carry.A", cls: "carryover_hero", payload: le16(0)),
        record(model: "prison.A", cls: "prison", payload: le16(1) + heroBytes()),
        record(model: "prison.A", cls: "prison", payload: le16(1) + heroBytes(version: 8)),
        record(model: "prison.A", cls: "prison", payload: le16(0)),
        record(model: "town.Castle", cls: "town", sub: "castle", payload: le16(4) + spellSetBytes(2) + spellSetBytes(2) + le16(8) + abstractTownBytes(garrison: true, customBuildings: true)),
        record(model: "rtown.A", cls: "random_town", payload: le16(7) + placementBytes("player", u8s(4)) + le16(8) + abstractTownBytes(owner: 6)),
        record(model: "rtown.A", cls: "random_town", payload: le16(6) + abstractTownBytes(version: 6)),
    ])
    #expect(b.objects.count == 11 && b.stop == .complete(endOffset: b.stop.offset))
    let o = b.objects.map(\.payload)
    guard case let .randomMonster(m) = o[0], case let .randomMonster(m2) = o[1], case let .randomMonster(m0) = o[2] else { return }
    #expect(m.levels == [1, 3] && m.minSize == 2 && m.maxSize == 9 && m.events?.triggers.count == 3 && m.placement == H4PlacementSpec.none)
    #expect(m2.levels == nil && m2.minSize == 0 && m2.placement == .player(1) && m0.placement == nil && m0.events == nil)
    guard case let .carryoverHero(c) = o[3], case let .carryoverHero(c0) = o[4] else { return }
    #expect(c.owner == 2 && c.name == "Tarnum" && c.values == [4, 5] && c.events?.triggers.count == 3 && c0.owner == nil)
    guard case let .prison(p10) = o[5], case let .prison(p8) = o[6], case let .prison(p0) = o[7] else { return }
    #expect(p10.hero?.name == "Hero" && p8.hero?.version == 8 && p8.hero?.statBonuses == [1, 2, 3, 4] && p8.hero?.flag == nil && p0.hero == nil)
    guard case let .town(t) = o[8], case let .randomTown(rt) = o[9], case let .randomTown(rt6) = o[10] else { return }
    #expect(t.version == 4 && t.bitsets.count == 2 && t.town.version == 8 && t.town.owner == 2 && t.town.name == "Castleton")
    #expect(t.town.garrison?.slots.count == 7 && t.town.buildings?.map(\.bytes) == [Data([1, 2, 3, 4, 5, 6]), Data([7, 8, 9, 10, 11, 12])])
    #expect(t.town.events.triggers.count == 4 && t.town.events.timed.count == 1 && t.town.events.continuous.count == 1)
    #expect(t.town.skillSets?.count == 2 && t.town.flag == 4 && t.town.buildingFlag == nil)
    #expect(rt.placement == .player(4) && rt.town.owner == 6 && rt.town.buildingFlag == true && rt.town.buildings == nil)
    #expect(rt6.placement == nil && rt6.town.version == 6 && rt6.town.skillSets == nil && rt6.town.flag == nil)
}

@Test func rejectsInvalidFamilyRecords() throws {
    func bad(_ r: Data, _ why: String) {
        #expect(throws: (any Error).self, Comment(rawValue: why)) { try body([r]) }
    }
    bad(record(model: "town.Castle", cls: "town", sub: "castle", payload: le16(3)), "town version 3 passes <6 to the base reader")
    bad(record(model: "town.Castle", cls: "town", sub: "castle", payload: le16(4) + spellSetBytes(3)), "bit set version")
    bad(record(model: "town.Castle", cls: "town", sub: "castle", payload: le16(4) + spellSetBytes() + spellSetBytes() + le16(9)), "abstract town version")
    bad(record(model: "town.Castle", cls: "town", sub: "castle", payload: le16(4) + spellSetBytes() + spellSetBytes() + le16(8) + abstractTownBytes(owner: 7)), "owner 7")
    bad(record(model: "rtown.A", cls: "random_town", payload: le16(5) + abstractTownBytes(version: 6)), "random town version 5 -> base reader rejects")
    bad(record(model: "rtown.A", cls: "random_town", payload: le16(7) + placementBytes("moon") + le16(8) + abstractTownBytes()), "placement kind")
    bad(record(model: "rtown.A", cls: "random_town", payload: le16(7) + le16(1) + str16("none") + le16(8) + abstractTownBytes()), "placement version")
    bad(record(model: "rmon.A", cls: "random_monster", payload: le16(4) + u8s(0) + eventBytes(triggers: 3) + placementBytes("none") + le32(5) + le32(2)), "max < min")
    bad(record(model: "rmon.A", cls: "random_monster", payload: le16(4) + u8s(0) + eventBytes(triggers: 3) + placementBytes("none") + le32(0) + le32(3)), "zero/positive mix")
    bad(record(model: "rmon.A", cls: "random_monster", payload: le16(5)), "version")
    bad(record(model: "prison.A", cls: "prison", payload: le16(1) + heroBytes(version: 7)), "hero version")
    bad(record(model: "carry.A", cls: "carryover_hero", payload: le16(1) + u8s(7) + str16("x")), "owner")
    bad(record(model: "mine.Gold", cls: "mine", payload: le16(1) + u8s(7)), "mine owner")
    bad(record(model: "mine.Gold", cls: "mine", payload: le16(3)), "mine version")
    bad(record(model: "qgate.A", cls: "quest_gate", payload: le16(2)), "gate version")
    bad(record(model: "seer.A", cls: "seers_hut", payload: le16(1) + str16("a") + str16("b") + str16("c") + str16("d") + scriptBytes() + le16(3) + nodeBytes("true")), "expression version")
    bad(record(model: "school.U", cls: "school", sub: "magic_university", payload: le16(1) + u8s(1) + Data(count: 5)), "36-bit set header")
    bad(record(model: "shrine.A", cls: "shrine", payload: le16(3)), "shrine version")
    bad(record(model: "dwell.Ing", cls: "creature_dwelling", payload: le16(1) + u8s(7)), "owner")
    bad(record(model: "dwell.Ing", cls: "creature_dwelling", payload: le16(3)), "owned version")
    bad(le32(0) + le32(0) + le32(0) + u8s(1) + le16(10), "army version")
    bad(le32(0) + le32(0) + le32(0) + u8s(1) + le16(2) + u8s(7), "army owner")
    bad(le32(0) + le32(0) + le32(0) + u8s(1) + le16(3) + u8s(1) + le16(0) + u8s(9), "slot kind")
    bad(le32(0) + le32(0) + le32(0) + u8s(1) + le16(3) + u8s(1) + le16(0) + u8s(0) + stackBytes(creature: 74), "creature 74")
    bad(le32(0) + le32(0) + le32(0) + u8s(1) + le16(3) + u8s(1) + le16(0) + u8s(0) + stackBytes(version: 2), "stack version")
    bad(le32(0) + le32(0) + le32(0) + u8s(1) + le16(7) + u8s(1) + armyBytes() + u8s(1, 0, 0, 0) + eventBytes(triggers: 3) + u8s(6), "army ai 6")
}

// MARK: - Hostile input

@Test func everyTruncationOfRichRecordsFailsCleanly() throws {
    let records = [
        le32(1) + le32(2) + le32(3) + u8s(1) + le16(9) + u8s(3) + richArmy() + u8s(1, 7, 8) + eventBytes(triggers: 3) + u8s(5, 2, 1),
        record(model: "mine.Gold", cls: "mine", payload: le16(2) + u8s(1, 1) + eventBytes(triggers: 4, order: ["c", "t", "o"], timed: 1, objects: 1, continuous: 1) + u8s(1) + richArmy()),
        record(model: "town.Castle", cls: "town", sub: "castle", payload: le16(4) + spellSetBytes() + spellSetBytes() + le16(8) + abstractTownBytes(garrison: true, customBuildings: true)),
        record(model: "seer.A", cls: "seers_hut", payload: le16(2) + questCoreBytes() + str16("s") + scriptBytes() + str16("s2")),
        record(model: "prison.A", cls: "prison", payload: le16(1) + heroBytes()),
    ]
    let store = try resourceStore(familyModels)
    let clock = ContinuousClock()
    let elapsed = clock.measure {
        for rec in records {
            let whole = scenarioHeader(size: 8, levels: 1) + emptySections() + le32(1) + rec
            let headerLength = scenarioHeader(size: 8, levels: 1).count + emptySections().count + 4
            for cut in headerLength..<whole.count {
                guard let s = try? H4Scenario(scenario: whole.prefix(cut), containerVersion: 22) else { continue }
                #expect(throws: (any Error).self) { try H4ScenarioBody(scenario: s, resources: store) }
            }
        }
    }
    #expect(elapsed < .seconds(5))
}

@Test func hostileCountsAndGarbageFailFast() throws {
    let clock = ContinuousClock()
    let elapsed = try clock.measure {
        // counted lists claiming 65 535 elements with no data behind them
        for payload in [le16(2) + u8s(1, 1) + Data(count: 4) + le16(0xFFFF), le16(4) + spellSetBytes() + spellSetBytes() + le16(0xFFFF)] {
            #expect(throws: (any Error).self) { try body([record(model: "mine.Gold", cls: "mine", payload: payload)]) }
        }
        #expect(throws: (any Error).self) { try body([record(model: "dwell.Ing", cls: "creature_dwelling", payload: le16(2) + u8s(1) + le16(0xFFFF))]) }
        // seeded pseudo-random garbage after a valid prefix never traps
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt8 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return UInt8(truncatingIfNeeded: seed >> 33) }
        let names: [(String, String, String)] = [("mine.Gold", "mine", ""), ("town.Castle", "town", "castle"), ("rtown.A", "random_town", ""),
                                                 ("seer.A", "seers_hut", ""), ("prison.A", "prison", ""), ("rmon.A", "random_monster", "")]
        for round in 0..<300 {
            let (m, c, s) = names[round % names.count]
            let junk = Data((0..<200).map { _ in next() })
            _ = try? body([record(model: m, cls: c, sub: s, payload: le16(UInt16(round % 5)) + junk)])
            _ = try? body([le32(0) + le32(0) + le32(0) + u8s(1) + le16(UInt16(round % 11)) + junk])
        }
    }
    #expect(elapsed < .seconds(5))
}
