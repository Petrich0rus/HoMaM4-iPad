import Foundation

// Artifacts, creature stacks, armies and heroes of the scenario body (heroes4.exe).
//
// Every reader below is shared by the object list (garrisons, mines, towns, random monsters,
// prisons), by the anonymous army records, and by the script `combat` node:
//
//     artifact        FUN_00664640   u16 id (<= 0xf8); ids 0x7c and 0xa6 (scroll, parchment) add u16 spell (<= 0xbc)
//     artifact list   FUN_00653760   u16 n, n x artifact
//     creature stack  FUN_0063e0f0   u16 version (0…1), i16 creature (-1 or < 74), i16 count (0 = game default),
//                                    version 1: artifact list
//     army            FUN_00640d00   u16 version 0, 7 x slot; slot (FUN_00640b50): i8 kind,
//                                    -1 empty, 0 creature stack, 1 hero, anything else fails
//     hero            FUN_0072f4e0   see `H4Hero`

/// One artifact; scrolls and parchments carry a spell id.
public struct H4ArtifactRef: Sendable, Equatable {
    public let id: UInt16
    public let spell: UInt16?

    static let scrollIDs: Set<UInt16> = [0x7c, 0xa6]
    static let maxID: UInt16 = 0xf8
    static let maxSpell: UInt16 = 0xbc

    static func read(_ r: inout ByteReader) throws -> H4ArtifactRef {
        let id = try r.u16()
        try r.require(id <= maxID, "artifact id \(id)")
        guard scrollIDs.contains(id) else { return H4ArtifactRef(id: id, spell: nil) }
        let spell = try r.u16()
        try r.require(spell <= maxSpell, "artifact spell \(spell)")
        return H4ArtifactRef(id: id, spell: spell)
    }

    static func readList(_ r: inout ByteReader) throws -> [H4ArtifactRef] {
        var out: [H4ArtifactRef] = []
        for _ in 0..<(try r.u16()) { out.append(try read(&r)) }
        return out
    }
}

/// A bit set stored as `u8 version` + 23 bytes (version 0, 184 ids) or 24 bytes (version 1 and 2, 188 ids):
/// spell sets (reader 0x865be0 -> 0x865990) and the two sets of a town (the same reader).
public struct H4VersionedBitset: Sendable, Equatable {
    public let version: UInt8
    public let bytes: Data

    static func read(_ r: inout ByteReader) throws -> H4VersionedBitset {
        let v = try r.u8()
        try r.require(v <= 2, "bit set version \(v)")
        return H4VersionedBitset(version: v, bytes: Data(try r.bytes(v == 0 ? 0x17 : 0x18)))
    }
}

/// Reader 0x857ec0: `u8 0` + 5 bytes, a 36-bit set (skills).
extension H4Bitset {
    static func read36(_ r: inout ByteReader) throws -> H4Bitset {
        try r.require(try r.u8() == 0, "36-bit set header")
        return H4Bitset(bitCount: 36, bytes: Data(try r.bytes(5)))
    }
}

public struct H4CreatureStack: Sendable, Equatable {
    public let version: UInt16
    /// Creature id, -1 when none.
    public let creature: Int16
    /// 0 means the game derives a default count from the creature.
    public let count: Int16
    public let artifacts: [H4ArtifactRef]

    static let creatureCount = 74

    static func read(_ r: inout ByteReader) throws -> H4CreatureStack {
        let v = try r.u16()
        try r.require(v <= 1, "creature stack version \(v)")
        let creature = try r.i16()
        try r.require(creature == -1 || (0..<Int16(creatureCount)).contains(creature), "creature \(creature)")
        let count = try r.i16()
        return H4CreatureStack(version: v, creature: creature, count: count,
                               artifacts: v >= 1 ? try H4ArtifactRef.readList(&r) : [])
    }
}

public enum H4ArmySlot: Sendable, Equatable {
    case empty
    case stack(H4CreatureStack)
    case hero(H4Hero)

    static func read(_ r: inout ByteReader) throws -> H4ArmySlot {
        try r.enter(); defer { r.leave() }
        let kind = try r.i8()
        switch kind {
        case -1: return .empty
        case 0: return .stack(try .read(&r))
        case 1: return .hero(try .read(&r))
        default: throw H4Error.malformed("army slot kind \(kind) at body offset \(r.offset)")
        }
    }
}

/// Seven slots (reader 0x640d00).
public struct H4Army: Sendable, Equatable {
    public let slots: [H4ArmySlot]
    public static let slotCount = 7

    static func read(_ r: inout ByteReader) throws -> H4Army {
        try r.require(try r.u16() == 0, "army version")
        return H4Army(slots: try (0..<slotCount).map { _ in try H4ArmySlot.read(&r) })
    }
    /// Reader 0x640e90 (anonymous army record version < 3): one slot, the six others empty.
    static func readSingleSlot(_ r: inout ByteReader) throws -> H4Army {
        try r.require(try r.u16() == 0, "army version")
        return H4Army(slots: [try H4ArmySlot.read(&r)] + Array(repeating: .empty, count: slotCount - 1))
    }
}

/// A hero record (t_hero reader 0x72f4e0, versions 8…10 in the files). Used by army slots and prisons.
public struct H4Hero: Sendable, Equatable {
    public let version: UInt16
    /// Portrait / biography id (-1 = default).
    public let portrait: Int16
    /// Hero class, -1 or < 48.
    public let heroClass: Int8
    /// -1, 0 or 1.
    public let gender: Int8
    /// Version ≥ 5, stored at +0x6a0.
    public let field6A0: Int8?
    /// Version ≥ 5: four bonuses added to the primary statistics (u8, or u16 before version 10).
    public let statBonuses: [UInt16]
    public let biography: String
    public let name: String
    /// Version ≥ 3, when customised: 36 skill levels (-1 or 0…4).
    public let skills: [Int8]?
    /// Version ≥ 4: spells known.
    public let spells: H4VersionedBitset?
    /// Version ≥ 2: 14 equipment slots.
    public let equipment: [H4ArtifactRef?]
    /// Version ≥ 1.
    public let backpack: [H4ArtifactRef]
    public let events: H4EventSet
    /// Version ≥ 9 (+0xa4).
    public let flag: UInt8?

    static let heroClassCount = 48

    static func read(_ r: inout ByteReader) throws -> H4Hero {
        try r.enter(); defer { r.leave() }
        let v = try r.u16()
        try r.require((8...10).contains(v), "hero version \(v)")
        let portrait = try r.i16()
        try r.require(portrait >= -1, "hero portrait \(portrait)")
        let heroClass = try r.i8()
        try r.require(heroClass == -1 || (0..<Int8(heroClassCount)).contains(heroClass), "hero class \(heroClass)")
        let gender = try r.i8()
        try r.require((-1...1).contains(gender), "hero gender \(gender)")
        var field6A0: Int8?
        var bonuses: [UInt16] = []
        if v >= 5 {
            field6A0 = try r.i8()
            if v >= 10 { bonuses = [UInt16(try r.u8()), UInt16(try r.u8())] } else { bonuses = [try r.u16(), try r.u16()] }
            bonuses += [UInt16(try r.u8()), UInt16(try r.u8())]
        }
        let biography = try r.string16(), name = try r.string16()
        var skills: [Int8]?
        if v >= 3, try r.u8() != 0 {
            skills = try (0..<36).map { _ in
                let k = try r.i8()
                try r.require((-1..<5).contains(k), "hero skill level \(k)")
                return k
            }
        }
        let spells = v >= 4 ? try H4VersionedBitset.read(&r) : nil
        var equipment: [H4ArtifactRef?] = []
        if v >= 2 {
            for _ in 0..<14 { equipment.append(try r.u8() != 0 ? try H4ArtifactRef.read(&r) : nil) }
        }
        let backpack = v >= 1 ? try H4ArtifactRef.readList(&r) : []
        let events = try H4EventSet.read(&r, triggers: 3, lists: [.timed, .scriptObjects, .continuous])
        let flag = v >= 9 ? try r.u8() : nil
        return H4Hero(version: v, portrait: portrait, heroClass: heroClass, gender: gender, field6A0: field6A0,
                      statBonuses: bonuses, biography: biography, name: name, skills: skills, spells: spells,
                      equipment: equipment, backpack: backpack, events: events, flag: flag)
    }
}

/// Anonymous army record (object list `flag != 0`, t_army reader 0x523a30), versions 0…9 (9 in the files).
public struct H4ArmyRecord: Sendable, Equatable {
    public let version: UInt16
    /// Version ≥ 2; 6 = neutral.
    public let owner: UInt8
    /// Absent for version 0.
    public let army: H4Army?
    /// Version ≥ 4: two behaviour bytes (when the version-5 flag is set).
    public let behaviour: [UInt8]?
    /// Version ≥ 6.
    public let events: H4EventSet?
    /// Version ≥ 7: -1…5 (+0xbc).
    public let ai: Int8?
    /// Version ≥ 8 (+0xb4).
    public let byte8: UInt8?
    /// Version ≥ 9 (+0xb0).
    public let flag9: UInt8?

    static func read(_ r: inout ByteReader) throws -> H4ArmyRecord {
        let v = try r.u16()
        try r.require(v <= 9, "army record version \(v)")
        guard v != 0 else {
            return H4ArmyRecord(version: 0, owner: 6, army: nil, behaviour: nil, events: nil, ai: nil, byte8: nil, flag9: nil)
        }
        var owner: UInt8 = 6
        if v >= 2 {
            owner = try r.u8()
            try r.require(owner < 7, "army owner \(owner)")
        }
        let army: H4Army
        if v >= 3 { army = try .read(&r) }
        else if try r.u8() != 0 { army = try .readSingleSlot(&r) }
        else { army = try .read(&r) }
        var behaviour: [UInt8]?
        if v >= 4 {
            let present = v >= 5 ? try r.u8() != 0 : true
            if present { behaviour = [try r.u8(), try r.u8()] }
        }
        let events = v >= 6 ? try H4EventSet.read(&r, triggers: 3, lists: [.timed, .scriptObjects, .continuous]) : nil
        var ai: Int8?
        if v >= 7 {
            ai = try r.i8()
            try r.require((-1..<6).contains(ai!), "army ai \(ai!)")
        }
        return H4ArmyRecord(version: v, owner: owner, army: army, behaviour: behaviour, events: events, ai: ai,
                            byte8: v >= 8 ? try r.u8() : nil, flag9: v >= 9 ? try r.u8() : nil)
    }
}
