import CryptoKit
import Foundation
import ImageIO
import Testing
@testable import H4Kit

// Slice 7c: started-game rendering. Synthetic resources exercise the rules G0–G9 (sprite names, flag points, draw keys,
// hidden classes); data-gated tests reproduce the frozen reference crops (`render_game_ref.py`).
//   H4_DATA_DIR, H4_MAPS_DIR           game folders (as the other data-gated tests)
//   H4_RENDER7C_REF_DIR (optional)     folder with the reference `<crop>.png` and `<crop>.draw.json` (draw-list equality)

private typealias Slot = H4GameRender.ActorSlot
private func kw(_ i: Int) -> String { H4GameIdentifiers.creatureKeywords[i] }

// MARK: - Fixtures

private func solid(_ name: String, _ l: Int32, _ t: Int32, _ r: Int32, _ b: Int32, alpha: UInt8 = 15) -> LayerFixture {
    let w = Int(r - l), h = Int(b - t)
    var f = LayerFixture()
    f.name = name; f.rect = (l, t, r, b)
    f.spans = (0..<h).map { (0, UInt16(w), UInt32($0 * w)) }
    f.indices = [UInt8](repeating: 1, count: w * h)
    f.alphaNibbles = [UInt8](repeating: alpha, count: w * h)
    return f
}

private func objectBytes(imageKind: UInt8 = 0, drawLayer: UInt8 = 1, flag: (Int, Int)? = nil, layers: [LayerFixture],
                         depths: [Int16] = []) -> Data {
    func bits(_ n: Int) -> Data { Data(repeating: 0, count: (n + 7) / 8) }
    var d = le16(6) + Data([10]) + le16(1) + le16(1) + le16(1) + bits(1) + bits(2) + bits(2)
    d += bits(4) + bits(4) + Data(repeating: 0, count: 4)
    d += le16(0) + le16(80) + str16("t") + le16(0) + str16("") + le16(0) + str16("")
    d += Data([drawLayer]) + (flag.map { Data([1]) + i32le($0.0) + i32le($0.1) } ?? Data([0]))
    d += Data([imageKind]) + le16(2) + le16(1) + le16(3) + le16(2) + le16(0xFFFF) + le16(0xFFFF)
    d += group(layers) + i32le(0) + i32le(0)
    if imageKind == 0 { d += le32(UInt32(depths.count)) + depths.reduce(Data()) { $0 + le16(UInt16(bitPattern: $1)) } }
    return d
}

private func sequenceBytes(origin: (Int, Int), layers: [LayerFixture]) -> Data {
    le16(2) + le16(2) + group(layers) + i32le(origin.0) + i32le(origin.1)
}

private func actorBytes(sequence: String, tail: (Int, Int, Int, Int)) -> Data {
    var d = le16(3) + Data([1]) + le16(1) + le16(32) + le16(1) + le16(1)
    d += str16("wait") + Data([10])
    for _ in 0..<8 { d += str16(sequence) }
    return d + i32le(tail.0) + i32le(tail.1) + i32le(tail.2) + i32le(tail.3)
}

private func flagBytes() -> Data {
    group([solid("frame 001", 0, 0, 3, 2)]) + le16(2) + le16(125) + le32(1) + le32(0) + Data([0, 0]) + i32le(0) + i32le(13)
}

/// Resources: object models Flagged (flag point (-5, 7), signed), Ground (draw layer 2, flag (1, 2)), Plain (no flag);
/// actors griffin (tail (3, -4)), ships.might, hero.chaos_magic_female; seven flags.
private func resources() -> [String: Data] {
    var r: [String: Data] = [:]
    r["adv_object.Flagged.h4d"] = objectBytes(flag: (-5, 7), layers: [solid("shadow 001", 0, 0, 4, 2), solid("frame 001", -20, 0, 40, 4)],
                                              depths: [-3, -2])
    r["adv_object.Ground.h4d"] = objectBytes(drawLayer: 2, flag: (1, 2), layers: [solid("frame 001", 0, 0, 4, 4)], depths: [-1])
    r["adv_object.Plain.h4d"] = objectBytes(layers: [solid("frame 001", 0, 0, 4, 4)], depths: [-1])
    for (actor, seq) in [("griffin", "griffin.wait.se"), ("ships.might", "ships.might.wait.se"), ("hero.chaos_magic_female", "hero.cmf.wait.se")] {
        r["adv_actor.\(actor).h4d"] = actorBytes(sequence: seq, tail: (3, -4, 0, 0))
        r["actor_sequence.\(seq).h4d"] = sequenceBytes(origin: (-10, -20), layers: [solid("shadow 001", 0, 0, 6, 3), solid("frame 001", 0, 0, 20, 30)])
    }
    for c in ["Red", "Blue", "Green", "Orange", "Purple", "Teal", "Gray"] { r["animation.Flags.\(c).h4d"] = flagBytes() }
    return r
}

private func tables() throws -> H4GameTables {
    let creatures = H4DataTable(columns: ["Keyword", "Level", "Alignment", "Experience"],
                                rows: H4GameIdentifiers.creatureKeywords.map { [$0, "1", "life", "10"] })
    let artifacts = H4DataTable(columns: ["Keyword", "Slot", "Level", "Allowed By Default"],
                                rows: H4GameIdentifiers.artifactKeywords.map { [$0, "Torso", "Minor", ""] })
    return try H4GameTables(creatures: creatures, artifacts: artifacts)
}

private func renderer(_ res: [String: Data]) throws -> H4GameRender {
    let lower = Dictionary(res.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
    let models = H4ObjectModelLibrary { name in
        guard let d = lower[name.lowercased()] else { throw H4Error.notFound(name: name) }
        return d
    }
    return H4GameRender(tables: try tables(), models: models,
                        loader: { name in
                            guard let d = lower[name.lowercased()] else { throw H4Error.notFound(name: name) }
                            return d
                        },
                        exists: { lower[$0.lowercased()] != nil })
}

private func classID(_ name: String) -> Int { H4ObjectClasses.names.firstIndex(of: name)! }

private func object(_ cls: String, _ x: Int, _ y: Int, model: String = "", level: Int = 0) -> H4ScenarioObject {
    H4ScenarioObject(offset: 0, x: Int32(x), y: Int32(y), level: Int32(level), modelName: model, triple: nil,
                     classID: classID(cls), payload: .versionOnly)
}

private func army(_ x: Int, _ y: Int, owner: Int, boat: Int? = nil, slots: [H4ArmySlot] = []) -> H4ScenarioObject {
    let padded = slots + Array(repeating: .empty, count: 7 - slots.count)
    let rec = H4ArmyRecord(version: 9, owner: UInt8(owner), army: H4Army(slots: padded), behaviour: nil, events: nil,
                           ai: boat.map { Int8($0) }, byte8: nil, flag9: nil)
    return H4ScenarioObject(offset: 0, x: Int32(x), y: Int32(y), level: 0, modelName: "", triple: nil,
                            classID: H4ScenarioObject.armyClassID, payload: .army(rec))
}

private func stack(_ creature: Int) -> H4ArmySlot { .stack(H4CreatureStack(version: 1, creature: Int16(creature), count: 5, artifacts: [])) }

private func game(_ objects: [H4GameObject] = []) -> H4Game { H4Game(seed: 1, difficulty: 2, players: [], objects: objects) }

private let region = H4MapTerrainRender.Region(row: 0, column: 0, rows: 8, columns: 8)
private let griffin = H4GameIdentifiers.creatureKeywords.firstIndex(of: "griffin")!

private func summary(_ l: H4ObjectDrawList) -> [String] { l.items.map { "\($0.kind.rawValue) \($0.model) \($0.x),\($0.y) \($0.layerIndex) \($0.column.map(String.init) ?? "-")" } }

// MARK: - G3 sprite names

@Test func actorNameBoatHeroCreatureEmpty() {
    func name(boat: Int = -1, _ slots: [Slot]) -> String? {
        H4GameRender.actorName(boat: boat, slots: slots, level: { [3: 5, 4: 5, 7: 2][$0] ?? 1 }, keyword: kw, heroExists: { _ in true })
    }
    // boat wins over hero and creatures; an empty boat is still drawn
    #expect(name(boat: 5, [.hero(heroClass: 3, gender: 1), .creature(3)]) == "ships.might")
    #expect(name(boat: 0, []) == "ships.life" && name(boat: 3, [.empty]) == "ships.chaos")
    // hero beats creatures (even a later slot and a higher level creature)
    #expect(name([.creature(3), .hero(heroClass: 0, gender: 0)]) == "hero.life_might_female")
    // first hero slot; class -> faction c/8; magic set; gender 1 male
    #expect(name([.hero(heroClass: 9, gender: 1)]) == "hero.order_magic_male")
    #expect(name([.hero(heroClass: 16, gender: 1)]) == "hero.death_magic_male")
    #expect(name([.hero(heroClass: 47, gender: 0)]) == "hero.might_magic_female")
    #expect(name([.hero(heroClass: 8, gender: -1)]) == "hero.order_might_female")
    #expect(name([.hero(heroClass: 24, gender: 1), .hero(heroClass: 0, gender: 1)]) == "hero.chaos_might_male")   // first hero slot
    #expect(name([.hero(heroClass: -1, gender: 1)]) == "hero.chaos_magic_female")
    // a missing magic sprite falls back to might
    #expect(H4GameRender.actorName(boat: -1, slots: [.hero(heroClass: 9, gender: 1)], level: { _ in 1 }, keyword: kw,
                                   heroExists: { !$0.contains("magic") }) == "hero.order_might_male")
    // creature: highest level, ties -> lowest slot
    #expect(name([.creature(1), .creature(3), .creature(4)]) == kw(3))
    #expect(name([.empty, .creature(7), .creature(1), .creature(2)]) == kw(7))
    #expect(name([.creature(7), .creature(1)]) == kw(7))
    #expect(name([.creature(1), .creature(2)]) == kw(1))               // equal levels
    // empty non-boat army: not drawn
    #expect(name([]) == nil && name([.empty, .empty]) == nil)
}

// MARK: - G6 colours, G7 key order

@Test func flagColoursAndSortKeyOrder() {
    #expect((0...5).map { H4GameRender.flagColour(owner: $0) } == ["Red", "Blue", "Green", "Orange", "Purple", "Teal"])
    #expect(H4GameRender.flagColour(owner: 6) == "Gray" && H4GameRender.flagColour(owner: nil) == "Gray")
    typealias K = H4GameRender.SortKey
    #expect(K(-1, 5, 2) < K(-1, 5, 2, 1))                                // shorter prefix first
    #expect(K(-1, 5, 2, 1) < K(-1, 5, 3))
    #expect(K(-1, 9, 9) < K(0, 0, 0, 0, 0))
    #expect(K(0, 4, 5, 2, 7) < K(0, 4.5, 0, 0, 0))                        // flag key right after the strips of key 4
    #expect(K(0, 4.5, 5, 2, 0) < K(0, 5, 0, 0, 0))
    #expect(!(K(0, 4, 5, 2, 7) < K(0, 4, 5, 2, 7)))
}

// MARK: - G1/G2/G6/G7 object items

@Test func objectFlagPointSignedAndColour() throws {
    let r = try renderer(resources())
    func list(owner: Int?, model: String = "Flagged") throws -> H4ObjectDrawList {
        // owner through an ownedScriptable-free path: random class resolved to the model with the owner of the record
        let o = object("random_artifact", 3, 4)
        let g = H4GameObject(index: 0, x: 3, y: 4, level: 0, className: "random_artifact", subclass: "", owner: owner,
                             resolved: H4ResolvedObject(model: model))
        return try r.drawList(objects: [o], game: game([g]), level: 0, region: region)
    }
    // anchor of (3, 4) in an 8x8 region: (32(4-3)+32*8, 16*7) = (288, 112); flag top-left = anchor + point - (0, 13)
    let flags = try list(owner: 2).items.filter { $0.kind == .flag }
    #expect(flags.count == 1 && flags[0].model == "Green" && flags[0].layerIndex == 0 && flags[0].column == nil)
    #expect(flags[0].left == 288 - 5 && flags[0].top == 112 + 7 - 13)       // dx = -5 is signed
    #expect(try list(owner: 6).items.filter { $0.kind == .flag }.map(\.model) == ["Gray"])
    #expect(try list(owner: nil).items.filter { $0.kind == .flag }.map(\.model) == ["Gray"])
    #expect(try list(owner: 0, model: "Plain").items.filter { $0.kind == .flag }.isEmpty)       // no flag point, no flag
    #expect(try list(owner: 1, model: "Missing").items.isEmpty)                                   // model unknown: skipped
}

@Test func objectFlagDrawKeys() throws {
    let r = try renderer(resources())
    func g(_ i: Int, _ x: Int, _ y: Int, _ model: String, _ owner: Int) -> (H4ScenarioObject, H4GameObject) {
        (object("random_artifact", x, y), H4GameObject(index: i, x: x, y: y, level: 0, className: "random_artifact", subclass: "",
                                                          owner: owner, resolved: H4ResolvedObject(model: model)))
    }
    // Flagged at (3,4): strips of columns -1…1 (frame -20…40 + origin 0), keys 0, 7 - d - 1 with d = depths[col - first]
    // (first = floor(-20/32) = -1): col -1 -> d -3 -> key 9, col 0 -> d -2 -> key 8; col 1 -> no depth entry (-1) -> key 7.
    let (o1, g1) = g(0, 3, 4, "Flagged", 0)
    let l1 = try r.drawList(objects: [o1], game: game([g1]), level: 0, region: region)
    #expect(summary(l1) == ["shadow Flagged 3,4 0 -", "body Flagged 3,4 1 1", "body Flagged 3,4 1 0", "body Flagged 3,4 1 -1",
                            "flag Red 3,4 0 -"])
    #expect(l1.objectCount == 1 && l1.armyCount == 0)
    // Ground object: flag after the body layers of the same cell, before the next cell's ground layers
    let (o3, g3) = g(0, 2, 3, "Ground", 1)          // listed first, but drawn after (2, 2)
    let (o2, g2) = g(1, 2, 2, "Ground", 4)
    let l2 = try r.drawList(objects: [o3, o2], game: game([g2, g3]), level: 0, region: region)
    // the sort key of a ground flag is (-1, x+y, x, 1) -> strips of (2,2): sum 4; (2,3): sum 5
    #expect(summary(l2) == ["body Ground 2,2 0 -", "flag Purple 2,2 0 -", "body Ground 2,3 0 -", "flag Blue 2,3 0 -"])
}

// MARK: - Armies

@Test func armySpritesFlagsAndCulling() throws {
    let r = try renderer(resources())
    let objects = [
        army(3, 4, owner: 1, slots: [stack(griffin)]),            // flag Blue
        army(2, 2, owner: 6, slots: [stack(griffin)]),            // neutral: no flag
        army(1, 1, owner: 0, slots: []),                          // empty, not a boat: not drawn
        army(5, 5, owner: 6, boat: 5),                            // empty boat: ships.might
        army(1, 2, owner: 3, slots: [.hero(H4Hero(version: 10, portrait: -1, heroClass: -1, gender: 1, field6A0: nil, statBonuses: [],
                                                biography: "", name: "", skills: nil, spells: nil, equipment: [], backpack: [],
                                                events: .empty, flag: nil))]),
    ]
    let l = try r.drawList(objects: objects, game: game(), level: 0, region: region)
    #expect(l.objectCount == 0 && l.armyCount == 4)
    let names = Set(l.items.map(\.model))
    #expect(names == ["adv_actor.griffin", "adv_actor.ships.might", "adv_actor.hero.chaos_magic_female", "Blue", "Orange"])
    // shadows first in item order, then body strips with key (0, x+y, x+y, x, col), the army flag at x+y+0.5
    let s = summary(l)
    #expect(s.prefix(4) == ["shadow adv_actor.griffin 3,4 0 -", "shadow adv_actor.griffin 2,2 0 -",
                            "shadow adv_actor.ships.might 5,5 0 -", "shadow adv_actor.hero.chaos_magic_female 1,2 0 -"])
    let bodies = s.dropFirst(4)
    #expect(bodies.first == "body adv_actor.hero.chaos_magic_female 1,2 1 -1")            // sum 3, column -1 (x from -10)
    // flag of the army at (3,4): anchor (288, 112) + tail (3, -4) - (0, 13)
    let blue = try #require(l.items.first { $0.model == "Blue" })
    #expect(blue.left == 288 + 3 && blue.top == 112 - 4 - 13 && blue.x == 3 && blue.y == 4)
    let blueAt = try #require(bodies.firstIndex(of: "flag Blue 3,4 0 -"))
    // after the last strip of sum 7 and before anything of sum 8 (ships at (5,5) has sum 10)
    #expect(bodies[bodies.index(before: blueAt)].hasPrefix("body adv_actor.griffin 3,4"))
    // outside the region the sprite box does not intersect the canvas: dropped (G5)
    let far = try r.drawList(objects: [army(60, 60, owner: 1, slots: [stack(griffin)])], game: game(), level: 0, region: region)
    #expect(far.items.isEmpty && far.armyCount == 0)
}

@Test func randomMonstersBecomeNeutralArmies() throws {
    let r = try renderer(resources())
    let objs = [object("random_monster", 3, 4), object("random_monster", 2, 2), object("random_random_monster", 4, 4),
                object("random_monster", 5, 5)]
    func rec(_ i: Int, _ model: String?, creature: Int?, removed: Bool? = nil) -> H4GameObject {
        H4GameObject(index: i, x: 0, y: 0, level: 0, className: "random_monster", subclass: "", owner: 6,
                     resolved: H4ResolvedObject(model: model, creature: creature, removed: removed))
    }
    let g = game([rec(0, "adv_actor.griffin", creature: griffin), rec(1, "adv_actor.griffin", creature: griffin, removed: true),
                  rec(2, nil, creature: nil)])                      // index 3 has no record
    let l = try r.drawList(objects: objs, game: g, level: 0, region: region)
    #expect(l.armyCount == 1 && Set(l.items.map(\.model)) == ["adv_actor.griffin"])      // only index 0; neutral: no flag
    #expect(!l.items.contains { $0.kind == .flag })
}

@Test func editorClassesAreHidden() throws {
    let r = try renderer(resources())
    let objs = ["deletion_marker", "event_trigger", "obelisk_marker"].map { object($0, 3, 4, model: "Plain") }
        + [object("decorative", 3, 4, model: "Plain")]
    let l = try r.drawList(objects: objs, game: game(), level: 0, region: region)
    #expect(l.objectCount == 1)
    #expect(summary(l).allSatisfy { $0.contains("Plain") } && l.items.count == 1)       // the decorative object's one body strip
    let hiddenOnly = try r.drawList(objects: Array(objs.prefix(3)), game: game(), level: 0, region: region)
    #expect(hiddenOnly.items.isEmpty && hiddenOnly.objectCount == 0)
    // an unresolved placeholder and a resolved one without model are never drawn
    let ph = try r.drawList(objects: [object("random_artifact", 3, 4, model: "Plain")], game: game(), level: 0, region: region)
    #expect(ph.items.isEmpty)
}

@Test func missingResourcesAreCounted() throws {
    var res = resources()
    res.removeValue(forKey: "adv_actor.griffin.h4d")
    res["adv_actor.ships.might.h4d"] = actorBytes(sequence: "nope", tail: (0, 0, 0, 0))
    res.removeValue(forKey: "animation.Flags.Blue.h4d")
    let r = try renderer(res)
    let l = try r.drawList(objects: [army(3, 4, owner: 6, slots: [stack(griffin)]), army(5, 5, owner: 6, boat: 5),
                                     army(2, 2, owner: 1, slots: [.hero(H4Hero(version: 10, portrait: -1, heroClass: -1, gender: 1, field6A0: nil,
                                          statBonuses: [], biography: "", name: "", skills: nil, spells: nil, equipment: [], backpack: [],
                                          events: .empty, flag: nil))])],
                           game: game(), level: 0, region: region)
    #expect(l.armyCount == 0)
    #expect(r.missingActors == ["griffin"] && r.missingSequences == ["nope"] && r.missingFlags == ["Blue"])
}

// MARK: - Real data (reference crops)

private let env = ProcessInfo.processInfo.environment
private let hasData = env["H4_DATA_DIR"] != nil && env["H4_MAPS_DIR"] != nil

private func sha256(_ bytes: [UInt8]) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }

private func rgba(ofPNG url: URL) throws -> (w: Int, h: Int, px: [UInt8]) {
    let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
    let w = img.width, h = img.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = try #require(CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (w, h, px)
}

/// The five crops of the acceptance test (R1): RGBA SHA-256 of the frozen reference output, and (with
/// H4_RENDER7C_REF_DIR) pixel and draw-list equality against the reference files. No game pixels are stored.
@Test(.enabled(if: hasData))
func gameCropsMatchFrozenReference() throws {
    let data = URL(fileURLWithPath: env["H4_DATA_DIR"]!), maps = URL(fileURLWithPath: env["H4_MAPS_DIR"]!)
    let store = try H4ResourceStore(dataDirectory: data)
    let compositor = try H4TerrainCompositor(store: store)
    let models = H4ObjectModelLibrary(store: store)
    let gameTables = try H4GameTables(store: store)
    let render = H4GameRender(store: store, tables: gameTables, models: models)
    let resolver = H4ObjectClassResolver(resources: store)
    let crops: [(String, String, Int, Int, Int, String, Int)] = [
        ("king0", "A Land without a King", 0, 30, 55, "136fc3a45157f67c920d95b73a11c68dc18008925d323c2140a306a9c2241545", 2551),
        ("zanfas0", "Zanfas's Challenge", 0, 108, 28, "bfdb7275b572f2645d9a404dc5c17242f3738783a0a1e1ef3a7956058cea4be8", 1488),
        ("dungeon1", "Dungeon Crawl", 1, 40, 55, "7fdc0a26cc0e5e4387caa82823d86d131ad09fc5f4e813093f7ae0b2a5927a59", 1142),
        ("boat0", "Ancestral Home", 0, 10, 20, "95ccc192420bf2067f43cab98f0d52189bd3933dfccd55e15da56977b0ac12e1", 1348),
        ("dungeon2", "Dungeon Crawl", 1, 14, 62, "f1301b4a2b58f9e196a4fd2157ed898c3c5008c0c309ae1b24c171db0e75396a", 1180),
    ]
    for (name, map, level, r0, c0, digest, count) in crops {
        let scenario = try H4Scenario(fileData: Data(contentsOf: maps.appendingPathComponent(map + ".h4c")))
        let body = try H4ScenarioBody(scenario: scenario, resolver: resolver)
        guard case .complete = body.stop else { throw H4Error.malformed("object list incomplete") }
        let started = try H4GameStart.start(scenario: scenario, store: store, tables: gameTables, seed: 12345, difficulty: 2)
        let reg = H4MapTerrainRender.Region(row: r0, column: c0, rows: 32, columns: 32)
        let list = try render.drawList(objects: body.objects, game: started, level: level, region: reg)
        let image = try compositor.render(terrain: try H4ScenarioTerrain(scenario: scenario), level: level, region: reg, objects: list)
        #expect(sha256(image.pixels) == digest, "\(name) pixels")
        #expect(list.items.count == count, "\(name) draw items")
        if let dir = env["H4_RENDER7C_REF_DIR"] {
            let ref = try rgba(ofPNG: URL(fileURLWithPath: dir + "/\(name).png"))
            #expect(ref.w == image.width && ref.h == image.height)
            #expect(ref.px == image.pixels, "\(name) pixels vs reference PNG")
            let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: dir + "/\(name).draw.json")))
            let actual = try JSONSerialization.jsonObject(with: list.json())
            #expect((expected as? NSArray)?.isEqual(to: actual as? [Any] ?? []) == true, "\(name) draw list")
        }
        #expect(render.missingActors.isEmpty && render.missingSequences.isEmpty && render.missingFlags.isEmpty)
        #expect(models.missingModels.isEmpty && compositor.missingTextures.isEmpty && compositor.missingMasks.isEmpty)
    }
}
