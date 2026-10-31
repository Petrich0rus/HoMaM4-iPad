import Foundation

// Adventure-map object list (loader 0x4ced20): framing and dispatch to the per-class readers.
//
//     u32 count
//     count × record:  i32 x, i32 y, i32 level, u8 flag
//         flag == 0:   str16 model name, classification triple, class payload
//         flag != 0:   anonymous army (t_army, reader 0x523a30)
//     triple (version >= 14, compared by the game against the object's own, 0x4cf190):
//         u16 0, 3 × (u16 id, str16 name)            class, subclass, index
//
// The class of a record is not stored in the file: the game instantiates it from the model name
// (0x7c7ca0) through the model's `adv_object.<model>.h4d` resource, whose classification gives
// the class name. Ids in resources and files differ between files, so only names are used.
// Objects have no length prefix: a class whose reader is unknown stops the walk, bytes are never skipped.
// Every one of the 105 classes now has a reader (the payload types are in H4ScenarioObjectData.swift
// and H4ScenarioArmies.swift); only a `school` of an unknown subclass would stop the walk.

/// The 105 object classes, in the game's enum order (table at 0x463630; names from the
/// `adv_object` classification, indices anchored by that table and the factory registry 0xac08e0).
public enum H4ObjectClasses {
    public static let names: [String] = [
        "abandoned_mine", "abbey", "academy", "arena", "artifact", "artifact_pile", "blacksmith", "blattner_stone",
        "border_gate", "border_guard", "bridge", "buoy", "campfire", "carryover_hero", "cartographer", "chain",
        "clover_field", "coliseum", "conservatory", "corpse", "creature_bank", "creature_dwelling", "decorative",
        "deletion_marker", "dolphin_school", "event_trigger", "exhausted_mine", "eye_of_the_magi", "faerie_ring",
        "ferry", "flotsam", "fountain", "garrison", "gateway", "hut_of_the_magi", "idol_of_fortune", "kelp_beds",
        "keymaster_tent", "lighthouse", "magic_gem", "mana_recharger", "material_pile", "medicine_wagon",
        "mercenary_camp", "mine", "movement_booster", "nothing", "obelisk", "obelisk_marker", "ocean_bottle",
        "outpost", "oyster", "pandoras_box", "path_arrow", "pathfinder", "port", "prison", "quest_gate",
        "quest_guard", "rainbow", "random_artifact", "random_creature_dwelling", "random_conservatory",
        "random_material_pile", "random_monster", "random_potion", "random_random_monster", "random_shrine",
        "random_staff", "random_teacher", "random_temple", "random_tome", "random_town",
        "random_weekly_material_generator", "sacred_grove", "sanctuary", "school", "seers_hut", "selection_ring",
        "ship", "shipwreck_survivor", "shipyard", "shrine", "sign", "sphinx", "stagecoach", "subterranean_gate",
        "system_object", "tavern", "teacher", "teleporter_entrance", "teleporter_exit", "temple", "unknown93",
        "tower", "town", "trading_post", "training_grounds", "treasure", "tree_of_knowledge", "vein",
        "victory_flag", "weekly_material_generator", "windmill", "whirlpool",
    ]
    static let ids: [String: Int] = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })

    static let abandonedMine = 0, carryoverHero = 13, conservatory = 18, creatureDwelling = 21, garrison = 32
    static let mine = 44, prison = 56, questGate = 57, questGuard = 58
    static let artifact = 4
    static let randomCreatureDwelling = 61, randomConservatory = 62, randomMonster = 64, randomRandomMonster = 66
    static let randomShrine = 67, randomTeacher = 69, randomTemple = 70, randomTown = 72
    static let randomWeeklyMaterialGenerator = 73, school = 76, seersHut = 77, shrine = 82, town = 95
    static let weeklyMaterialGenerator = 102

    /// Reader 0x4fa760 (`u16 version == 0`): classes registered with it, plus the classes without a
    /// registered factory, which get the plain stationary object (default factory 0xac1118).
    static let versionOnly: Set<Int> = [
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 16, 17, 19, 20, 22, 24, 26, 27, 28, 30, 31, 34, 35, 36, 37,
        39, 40, 41, 42, 43, 45, 46, 47, 51, 53, 54, 55, 59, 60, 63, 65, 68, 71, 74, 75, 78, 79, 80, 84, 85, 87, 88,
        89, 92, 93, 94, 96, 97, 98, 99, 100, 101,
    ]
    /// Reader 0x44a750: u16 version (0 or 1), version 1 adds a str16 name.
    static let gateway: Set<Int> = [23, 25, 29, 33, 52, 86, 90, 91, 104]
    /// Reader 0x46ddb0: u16 version (0 or 1), version 1 adds a str16 message.
    static let sign: Set<Int> = [49, 83]
    static let obeliskMarker = 48    // reader 0x7c6a80
    static let outpost = 50          // reader 0x8a1260
    /// Owned base (readers 0x478a10, 0x43c9c0, 0x8ccd70): lighthouse, shipyard, windmill, creature dwelling,
    /// weekly material generators.
    static let ownedScriptable: Set<Int> = [21, 38, 73, 81, 102, 103]
}

/// Payload of a decoded record.
public enum H4ObjectPayload: Sendable, Equatable {
    /// `u16 0`.
    case versionOnly
    /// Gateway family and event objects: version 0 or 1, plus a name for version 1.
    case gateway(version: UInt16, name: String?)
    /// Sign and ocean bottle: version 0 or 1, plus a message for version 1.
    case sign(version: UInt16, message: String?)
    /// Obelisk marker: version 0 or 1, version 1 adds a u16.
    case obeliskMarker(version: UInt16, value: UInt16?)
    /// Outpost: version 0 or 1, version 1 adds the owner (< 7).
    case outpost(version: UInt16, owner: UInt8?)
    /// Lighthouse, shipyard, windmill, creature dwelling, weekly (random) material generators.
    case ownedScriptable(H4OwnedObject)
    case randomDwelling(H4RandomDwelling)
    /// Mine and garrison.
    case garrison(H4GarrisonObject)
    case abandonedMine(H4AbandonedMine)
    /// Conservatory and random conservatory.
    case conservatory(H4Conservatory)
    case quest(H4QuestObject)
    case school(H4School)
    /// Shrine and random shrine.
    case shrine(H4Shrine)
    case randomTeacher(H4RandomTeacher)
    /// Random temple: version 0 or 1, version 1 adds a placement.
    case randomTemple(version: UInt16, placement: H4PlacementSpec?)
    /// Artifact of subclass parchment or scroll (reader 0x430e10): version 0 or 1, version 1 adds the spell id.
    case spellArtifact(version: UInt16, spell: UInt32?)
    /// Random monster (also random random monster).
    case randomMonster(H4RandomMonster)
    case carryoverHero(H4CarryoverHero)
    case prison(H4Prison)
    case town(H4Town)
    case randomTown(H4RandomTown)
    /// Anonymous army record (`flag != 0`): no model, no classification.
    case army(H4ArmyRecord)
}

public struct H4ClassificationTriple: Sendable, Equatable {
    public let classID: UInt16, className: String
    public let subclassID: UInt16, subclassName: String
    public let indexID: UInt16, indexName: String
}

/// One decoded object record.
public struct H4ScenarioObject: Sendable {
    /// Class id of the anonymous army records.
    public static let armyClassID = -1

    /// Offset of the record (its x) in `H4Scenario.body`.
    public let offset: Int
    public let x: Int32, y: Int32, level: Int32
    /// Empty for anonymous armies.
    public let modelName: String
    /// The triple stored in the file (equal by name to the resource's); nil for anonymous armies.
    public let triple: H4ClassificationTriple?
    /// Index in `H4ObjectClasses.names`, or `armyClassID`.
    public let classID: Int
    public var className: String { classID == Self.armyClassID ? "army" : H4ObjectClasses.names[classID] }
    public let payload: H4ObjectPayload
}

/// Why the walk stopped before the end of the list.
public enum H4ObjectStopReason: Sendable, Equatable, CustomStringConvertible {
    /// The class has no reader (or its subclass is not one a reader exists for).
    case unsupportedClass(id: Int, name: String)

    public var description: String {
        switch self {
        case let .unsupportedClass(id, name): return "reader missing for class \(id) \(name)"
        }
    }
}

public enum H4ObjectListStop: Sendable, Equatable {
    /// Every record decoded; the offset (in `H4Scenario.body`) is where the list ends.
    case complete(endOffset: Int)
    /// The record starting at `recordOffset` cannot be decoded.
    case stopped(recordOffset: Int, reason: H4ObjectStopReason)

    /// Body offset where decoding ended.
    public var offset: Int {
        switch self {
        case let .complete(end): return end
        case let .stopped(at, _): return at
        }
    }
}

/// Resolves model names to classification triples through `adv_object.<model>.h4d`, with a cache.
/// Share one resolver across scenarios: most models recur.
public final class H4ObjectClassResolver: @unchecked Sendable {
    public struct Resolved: Sendable { public let classID: Int; public let subclassName: String; public let indexName: String }

    private let resources: H4ResourceStore
    private let lock = NSLock()
    private var cache: [String: Resolved] = [:]

    public init(resources: H4ResourceStore) { self.resources = resources }

    public func resolve(model: String) throws -> Resolved {
        let key = model.lowercased()
        lock.lock(); let hit = cache[key]; lock.unlock()
        if let hit { return hit }
        let resourceName = "adv_object.\(model).h4d"
        let triple = try Self.classification(of: resources.data(for: resourceName), name: resourceName)
        guard let id = H4ObjectClasses.ids[triple[0].name.lowercased()] else {
            throw H4Error.malformed("model '\(model)' has unknown object class '\(triple[0].name)'")
        }
        let resolved = Resolved(classID: id, subclassName: triple[1].name, indexName: triple[2].name)
        lock.lock(); cache[key] = resolved; lock.unlock()
        return resolved
    }

    /// Reads only the classification of an `adv_object` resource (layout of `H4AdventureObject`,
    /// reader 0x44d860), skipping the sprite.
    static func classification(of data: Data, name: String) throws -> [(id: UInt16, name: String)] {
        var r = ByteReader(data)
        let version = try r.u16()
        guard (2...6).contains(version) else { throw H4Error.malformed("\(name): adventure object version \(version) has no classification") }
        _ = try r.u8()
        let edge = version >= 3 ? try r.u16() : 0
        guard edge <= 1 else { throw H4Error.malformed("\(name): edge flag \(edge)") }
        let w = Int(try r.u16()), h = Int(try r.u16())
        guard w <= 64, h <= 64 else { throw H4Error.malformed("\(name): \(w)×\(h) tiles") }
        func bits(_ n: Int) throws { _ = try r.bytes((n + 7) / 8) }
        try bits(w * h)
        if edge < 1 { try bits(w * h) } else { try bits((h + 1) * w); try bits((w + 1) * h) }
        if version > 5 {
            try bits(2 * (h + 1) * w); try bits(2 * (w + 1) * h); _ = try r.bytes((w + 1) * (h + 1))
        }
        guard try r.u16() == 0 else { throw H4Error.malformed("\(name): classification version") }
        var out: [(id: UInt16, name: String)] = []
        for _ in 0..<3 { out.append((try r.u16(), try r.string16())) }
        return out
    }
}

/// The scenario body up to and including the decodable prefix of the object list.
public struct H4ScenarioBody: Sendable {
    /// Largest object count accepted (the game's own maps stay far below).
    public static let maxObjectCount = 100_000

    public let sections: H4ScenarioSections
    /// Body offset of the u32 object count (same as `sections.objectListOffset`).
    public var objectListOffset: Int { sections.objectListOffset }
    public let declaredCount: Int
    /// Records decoded before the walk stopped, in file order.
    public let objects: [H4ScenarioObject]
    public let stop: H4ObjectListStop

    public init(scenario: H4Scenario, resources: H4ResourceStore) throws {
        try self.init(scenario: scenario, resolver: H4ObjectClassResolver(resources: resources))
    }

    public init(scenario: H4Scenario, resolver: H4ObjectClassResolver) throws {
        try self.init(scenario: scenario, sections: H4ScenarioSections(scenario: scenario), resolver: resolver)
    }

    /// For callers that already parsed (or want to report separately) the sections.
    public init(scenario: H4Scenario, sections: H4ScenarioSections, resolver: H4ObjectClassResolver) throws {
        self.sections = sections
        var r = ByteReader(scenario.body, offset: sections.objectListOffset)
        let count = Int(try r.u32())
        guard count <= Self.maxObjectCount else { throw H4Error.malformed("object count \(count)") }
        declaredCount = count
        (objects, stop) = try Self.walk(&r, count: count, resolver: resolver)
    }

    private static func walk(_ r: inout ByteReader, count: Int,
                             resolver: H4ObjectClassResolver) throws -> ([H4ScenarioObject], H4ObjectListStop) {
        func fail(_ what: String, at start: Int) -> H4Error { .malformed("object at body offset \(start): \(what)") }
        var records: [H4ScenarioObject] = []
        records.reserveCapacity(min(count, r.remaining / 20))
        for _ in 0..<count {
            let start = r.offset
            let x = try r.i32(), y = try r.i32(), level = try r.i32()
            if try r.u8() != 0 {                                                // 0x523a30
                let army = try readPayload(&r, start: start) { H4ObjectPayload.army(try H4ArmyRecord.read(&$0)) }
                records.append(H4ScenarioObject(offset: start, x: x, y: y, level: level, modelName: "", triple: nil,
                                                classID: H4ScenarioObject.armyClassID, payload: army))
                continue
            }
            let model = try r.string16()
            guard try r.u16() == 0 else { throw fail("classification version", at: start) }
            let triple = H4ClassificationTriple(
                classID: try r.u16(), className: try r.string16(),
                subclassID: try r.u16(), subclassName: try r.string16(),
                indexID: try r.u16(), indexName: try r.string16())
            let resolved = try resolver.resolve(model: model)
            let id = resolved.classID
            // 0x4cf190: the file's triple must equal the created object's, by name.
            guard triple.className.lowercased() == H4ObjectClasses.names[id],
                  triple.subclassName.lowercased() == resolved.subclassName.lowercased(),
                  triple.indexName.lowercased() == resolved.indexName.lowercased() else {
                throw fail("classification \(triple.className)/\(triple.subclassName)/\(triple.indexName) of '\(model)' differs from its resource", at: start)
            }
            let payload = try readPayload(&r, start: start) {
                try readClassPayload(&$0, classID: id, subclass: resolved.subclassName.lowercased())
            }
            guard let payload else {
                return (records, .stopped(recordOffset: start, reason: .unsupportedClass(id: id, name: H4ObjectClasses.names[id])))
            }
            records.append(H4ScenarioObject(offset: start, x: x, y: y, level: level, modelName: model,
                                            triple: triple, classID: id, payload: payload))
        }
        return (records, .complete(endOffset: r.offset))
    }

    /// Runs a reader, adding the record offset to validity errors (truncation errors pass through).
    private static func readPayload<T>(_ r: inout ByteReader, start: Int, _ body: (inout ByteReader) throws -> T) throws -> T {
        do { return try body(&r) }
        catch let H4Error.malformed(what) where !what.hasPrefix("object at body offset") {
            throw H4Error.malformed("object at body offset \(start): \(what)")
        }
    }

    /// The reader of a class (nil when none exists); `subclass` is lower-cased.
    private static func readClassPayload(_ r: inout ByteReader, classID id: Int, subclass sub: String) throws -> H4ObjectPayload? {
        typealias C = H4ObjectClasses
        func version(_ what: String, max: UInt16) throws -> UInt16 {
            let v = try r.u16()
            try r.require(v <= max, "\(what) version \(v)")
            return v
        }
        if id == C.artifact, sub == "parchment" || sub == "scroll" {              // 0x430e10
            let v = try version("spell artifact", max: 1)
            return .spellArtifact(version: v, spell: v == 1 ? try r.u32() : nil)
        }
        if C.versionOnly.contains(id) {                                           // 0x4fa760
            try r.require(try r.u16() == 0, "version of \(C.names[id])")
            return .versionOnly
        }
        if C.gateway.contains(id) || C.sign.contains(id) {                        // 0x44a750, 0x46ddb0
            let v = try version(C.names[id], max: 1)
            let text = v == 1 ? try r.string16() : nil
            return C.gateway.contains(id) ? .gateway(version: v, name: text) : .sign(version: v, message: text)
        }
        if C.ownedScriptable.contains(id) { return .ownedScriptable(try .read(&r)) }
        switch id {
        case C.obeliskMarker:                                                     // 0x7c6a80
            let v = try version("obelisk marker", max: 1)
            return .obeliskMarker(version: v, value: v == 1 ? try r.u16() : nil)
        case C.outpost:                                                           // 0x8a1260
            let v = try version("outpost", max: 1)
            var owner: UInt8?
            if v == 1 {
                owner = try r.u8()
                try r.require(owner! < 7, "outpost owner \(owner!)")
            }
            return .outpost(version: v, owner: owner)
        case C.mine, C.garrison: return .garrison(try .read(&r))
        case C.abandonedMine: return .abandonedMine(try .read(&r))
        case C.randomCreatureDwelling: return .randomDwelling(try .read(&r))
        case C.conservatory: return .conservatory(try .read(&r, random: false))
        case C.randomConservatory: return .conservatory(try .read(&r, random: true))
        case C.questGate: return .quest(try .read(&r, kind: .gate))
        case C.questGuard: return .quest(try .read(&r, kind: .guardian))
        case C.seersHut: return .quest(try .read(&r, kind: .seersHut))
        case C.school: return H4School.subclasses.contains(sub) ? .school(try .read(&r)) : nil
        case C.shrine: return .shrine(try .read(&r, random: false))
        case C.randomShrine: return .shrine(try .read(&r, random: true))
        case C.randomTeacher: return .randomTeacher(try .read(&r))
        case C.randomTemple:                                                      // 0x473aa0
            let v = try version("random temple", max: 1)
            return .randomTemple(version: v, placement: v >= 1 ? try .read(&r) : nil)
        case C.randomMonster, C.randomRandomMonster: return .randomMonster(try .read(&r))
        case C.carryoverHero: return .carryoverHero(try .read(&r))
        case C.prison: return .prison(try .read(&r))
        case C.town: return .town(try .read(&r))
        case C.randomTown: return .randomTown(try .read(&r))
        default: return nil
        }
    }
}
