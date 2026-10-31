import Foundation

// Typed payloads of the adventure-map object classes (heroes4.exe, GOG 1.3).
//
// Every reader starts right after the classification triple. `version` below is the object's own
// u16 version, never the scenario version (no reader depends on the latter for versions 27/29).
// Owners are 0…5 for players and 6 for neutral. Counts are u16, so every list is bounded by the
// data that follows; recursion (scripts, armies, heroes) is capped by `ByteReader.enter()`.

/// Owned object base (reader 0x7d7270): `u8 owner` when version ≥ 1 (< 7, else neutral), script objects when version ≥ 2.
/// Used by lighthouse, shipyard, windmill (0x478a10), creature dwelling (0x43c9c0) and the
/// weekly material generators (0x8ccd70); the version is 0…2.
public struct H4OwnedObject: Sendable, Equatable {
    public let version: UInt16
    public let owner: UInt8
    public let scriptObjects: [H4ScriptObject]

    /// Reads the owner part with an explicit owner-version (see `H4RandomDwelling`).
    static func readOwnedBase(_ r: inout ByteReader, ownerVersion v: UInt16) throws -> (owner: UInt8, objects: [H4ScriptObject]) {
        var owner: UInt8 = 6
        if v >= 1 {
            owner = try r.u8()
            try r.require(owner < 7, "owner \(owner)")
        }
        return (owner, v >= 2 ? try H4EventSet.readList(&r, H4ScriptObject.read) : [])
    }

    static func read(_ r: inout ByteReader) throws -> H4OwnedObject {
        let v = try r.u16()
        try r.require(v <= 2, "owned object version \(v)")
        let base = try readOwnedBase(&r, ownerVersion: v)
        return H4OwnedObject(version: v, owner: base.owner, scriptObjects: base.objects)
    }
}

/// Random creature dwelling (class 61, reader 0x43f450), version 0…3.
public struct H4RandomDwelling: Sendable, Equatable {
    public let version: UInt16
    public let owner: UInt8
    public let scriptObjects: [H4ScriptObject]
    /// Version ≥ 2; otherwise the game's default.
    public let placement: H4PlacementSpec?

    static func read(_ r: inout ByteReader) throws -> H4RandomDwelling {
        let v = try r.u16()
        try r.require(v <= 3, "random dwelling version \(v)")
        let base = try H4OwnedObject.readOwnedBase(&r, ownerVersion: v == 0 ? 0 : (v >= 3 ? 2 : 1))
        return H4RandomDwelling(version: v, owner: base.owner, scriptObjects: base.objects,
                                placement: v >= 2 ? try H4PlacementSpec.read(&r) : nil)
    }
}

/// Mine (class 44) and garrison (class 32), reader 0x7d3f60 -> 0x7d3fb0, version 0…2.
public struct H4GarrisonObject: Sendable, Equatable {
    public let version: UInt16
    public let owner: UInt8
    /// Version ≥ 2 and not neutral (+0xdc, 1 by default).
    public let flag: UInt8?
    /// Version ≥ 2: four triggers, then the lists continuous, timed, script objects.
    public let events: H4EventSet
    /// Version ≥ 2 with the army byte set; otherwise the game's default (empty) army.
    public let army: H4Army?

    static func read(_ r: inout ByteReader) throws -> H4GarrisonObject {
        let v = try r.u16()
        try r.require(v <= 2, "garrison version \(v)")
        var owner: UInt8 = 6
        if v >= 1 {
            owner = try r.u8()
            try r.require(owner <= 6, "garrison owner \(owner)")
        }
        let flag = v >= 2 && owner != 6 ? try r.u8() : nil
        guard v >= 2 else { return H4GarrisonObject(version: v, owner: owner, flag: flag, events: .empty, army: nil) }
        let events = try H4EventSet.read(&r, triggers: 4, lists: [.continuous, .timed, .scriptObjects])
        return H4GarrisonObject(version: v, owner: owner, flag: flag, events: events,
                                army: try r.u8() != 0 ? try H4Army.read(&r) : nil)
    }
}

/// Abandoned mine (class 0, reader 0x4263e0), version 0…1; no owner.
public struct H4AbandonedMine: Sendable, Equatable {
    public let version: UInt16
    public let events: H4EventSet
    public let army: H4Army?

    static func read(_ r: inout ByteReader) throws -> H4AbandonedMine {
        let v = try r.u16()
        try r.require(v <= 1, "abandoned mine version \(v)")
        // Layout: version-1 events (4 triggers; lists continuous, timed, script objects), then the army byte.
        let events = v >= 1 ? try H4EventSet.read(&r, triggers: 4, lists: [.continuous, .timed, .scriptObjects]) : .empty
        return H4AbandonedMine(version: v, events: events, army: try r.u8() != 0 ? try H4Army.read(&r) : nil)
    }
}

/// Conservatory (class 18, reader 0x437560, version 0…1) and random conservatory (class 62, reader
/// 0x437ea0, version 0…2): spell sets (two when explicit) and, for the random one, a placement.
public struct H4Conservatory: Sendable, Equatable {
    public let version: UInt16
    public let spellSets: [H4VersionedBitset]
    public let placement: H4PlacementSpec?

    static func read(_ r: inout ByteReader, random: Bool) throws -> H4Conservatory {
        let v = try r.u16()
        try r.require(v <= (random ? 2 : 1), "conservatory version \(v)")
        let explicit = v == (random ? 2 : 1)
        let sets = explicit ? [try H4VersionedBitset.read(&r), try H4VersionedBitset.read(&r)] : []
        return H4Conservatory(version: v, spellSets: sets, placement: random && v >= 1 ? try H4PlacementSpec.read(&r) : nil)
    }
}

/// Quest record shared by gates, guards and seer's huts (reader 0x7ed980): four strings, the quest
/// script (+0x48) and its completion condition (+0x4c).
public struct H4QuestCore: Sendable, Equatable {
    /// In file order (fields +0x84, +0x70, +0x60, +0x50).
    public let texts: [String]
    public let script: H4Script
    public let condition: H4Expression

    static func read(_ r: inout ByteReader) throws -> H4QuestCore {
        H4QuestCore(texts: try (0..<4).map { _ in try r.string16() }, script: try .read(&r), condition: try .read(&r))
    }
}

/// Quest gate (class 57, reader 0x7eec70), quest guard (class 58, 0x7ef7e0) and seer's hut (class 77, 0x7efac0).
public struct H4QuestObject: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case gate, guardian, seersHut }
    public let kind: Kind
    public let version: UInt16
    /// Absent for version 0 (and for a gate of version 0).
    public let core: H4QuestCore?
    /// Guard and seer's hut: string at +0x98.
    public let text: String?
    /// Guard (version ≥ 2) and seer's hut: script at +0xa8.
    public let script: H4Script?
    /// Seer's hut: string at +0xac.
    public let text2: String?

    static func read(_ r: inout ByteReader, kind: Kind) throws -> H4QuestObject {
        let v = try r.u16()
        let maxVersion: UInt16 = kind == .gate ? 1 : 2
        try r.require(v <= maxVersion, "quest object version \(v)")
        func make(core: H4QuestCore? = nil, text: String? = nil, script: H4Script? = nil, text2: String? = nil) -> H4QuestObject {
            H4QuestObject(kind: kind, version: v, core: core, text: text, script: script, text2: text2)
        }
        switch kind {
        case .gate:
            return make(core: v >= 1 ? try .read(&r) : nil)
        case .guardian:
            guard v >= 1 else { return make() }
            let core = try H4QuestCore.read(&r), text = try r.string16()
            return make(core: core, text: text, script: v >= 2 ? try .read(&r) : nil)
        case .seersHut:
            guard v >= 1 else { return make() }
            let core = try H4QuestCore.read(&r), text = try r.string16()
            if v >= 2 {
                let script = try H4Script.read(&r)
                return make(core: core, text: text, script: script, text2: try r.string16())
            }
            let text2 = try r.string16()
            return make(core: core, text: text, script: try .read(&r), text2: text2)
        }
    }
}

/// Schools and universities (class 76, eight subclasses, readers 0x766cd0 / 0x81a1c0 / 0x8cb860 / 0x58c080):
/// version 0 uses the subclass defaults, version 1 two 36-bit skill sets.
public struct H4School: Sendable, Equatable {
    public let version: UInt16
    public let skillSets: [H4Bitset]
    static let subclasses: Set<String> = ["magic_university", "war_college", "school_of_magic", "school_of_war",
                                           "library", "war_institute", "witchs_hut", "beastmasters_hut"]
    static func read(_ r: inout ByteReader) throws -> H4School {
        let v = try r.u16()
        try r.require(v <= 1, "school version \(v)")
        return H4School(version: v, skillSets: v == 1 ? [try .read36(&r), try .read36(&r)] : [])
    }
}

/// Shrine (class 82, reader 0x46c4a0, version 0…2) and random shrine (class 67, 0x46cfd0, version 0…3).
public struct H4Shrine: Sendable, Equatable {
    public let version: UInt16
    /// Version 1: the old 184-spell set; version ≥ 2: a versioned set; version 0: all spells (nil).
    public let spells: H4VersionedBitset?
    /// Random shrine, version ≥ 3.
    public let placement: H4PlacementSpec?

    static func read(_ r: inout ByteReader, random: Bool) throws -> H4Shrine {
        let v = try r.u16()
        try r.require(v <= (random ? 3 : 2), "shrine version \(v)")
        var spells: H4VersionedBitset?
        if v >= 2 { spells = try .read(&r) }
        else if v == 1 { spells = H4VersionedBitset(version: 0, bytes: Data(try r.bytes(0x17))) }
        return H4Shrine(version: v, spells: spells, placement: random && v >= 3 ? try H4PlacementSpec.read(&r) : nil)
    }
}

/// Random teacher (class 69, reader 0x42e4b0), version 0…1: a 9-bit mask of allowed teachers (all when version 0).
public struct H4RandomTeacher: Sendable, Equatable {
    public let version: UInt16
    public let allowedMask: UInt16
    public let placement: H4PlacementSpec?
    static func read(_ r: inout ByteReader) throws -> H4RandomTeacher {
        let v = try r.u16()
        try r.require(v <= 1, "random teacher version \(v)")
        guard v == 1 else { return H4RandomTeacher(version: v, allowedMask: 0x1ff, placement: nil) }
        return H4RandomTeacher(version: v, allowedMask: try r.u16(), placement: try .read(&r))
    }
}

/// Random monster (classes 64 and 66, reader 0x7f3710), version 0…4.
public struct H4RandomMonster: Sendable, Equatable {
    public let version: UInt16
    /// Version ≥ 3 when set: two signed bytes (+0xac − 1, +0xb0).
    public let levels: [Int8]?
    /// Version ≥ 2.
    public let events: H4EventSet?
    /// Version ≥ 1.
    public let placement: H4PlacementSpec?
    /// Version ≥ 4: stack size range, 0 ≤ min ≤ max, both zero or both positive.
    public let minSize: Int32?
    public let maxSize: Int32?

    static func read(_ r: inout ByteReader) throws -> H4RandomMonster {
        let v = try r.u16()
        try r.require(v <= 4, "random monster version \(v)")
        var levels: [Int8]?
        if v >= 3, try r.u8() != 0 { levels = [try r.i8(), try r.i8()] }
        let events = v >= 2 ? try H4EventSet.read(&r, triggers: 3, lists: [.timed, .scriptObjects, .continuous]) : nil
        let placement = v >= 1 ? try H4PlacementSpec.read(&r) : nil
        var lo: Int32?, hi: Int32?
        if v >= 4 {
            let a = try r.i32(), b = try r.i32()
            try r.require(a >= 0 && b >= a && (a > 0) == (b > 0), "random monster size range \(a)…\(b)")
            lo = a; hi = b
        }
        return H4RandomMonster(version: v, levels: levels, events: events, placement: placement, minSize: lo, maxSize: hi)
    }
}

/// Carry-over hero (class 13, reader 0x5bf4a0), version 0…2.
public struct H4CarryoverHero: Sendable, Equatable {
    public let version: UInt16
    /// Version ≥ 1.
    public let owner: UInt8?
    public let name: String?
    /// Version ≥ 2 when set: two signed bytes (+0x80 − 1, +0x7c).
    public let values: [Int8]?
    public let events: H4EventSet?

    static func read(_ r: inout ByteReader) throws -> H4CarryoverHero {
        let v = try r.u16()
        try r.require(v <= 2, "carry-over hero version \(v)")
        var owner: UInt8?, name: String?
        if v >= 1 {
            owner = try r.u8()
            try r.require(owner! < 7, "carry-over hero owner \(owner!)")
            name = try r.string16()
        }
        var values: [Int8]?
        var events: H4EventSet?
        if v >= 2 {
            if try r.u8() != 0 { values = [try r.i8(), try r.i8()] }
            events = try H4EventSet.read(&r, triggers: 3, lists: [.timed, .scriptObjects, .continuous])
        }
        return H4CarryoverHero(version: v, owner: owner, name: name, values: values, events: events)
    }
}

/// Prison (class 56, reader 0x467f20), version 0…1: version 1 holds the prisoner.
public struct H4Prison: Sendable, Equatable {
    public let version: UInt16
    public let hero: H4Hero?
    static func read(_ r: inout ByteReader) throws -> H4Prison {
        let v = try r.u16()
        try r.require(v <= 1, "prison version \(v)")
        return H4Prison(version: v, hero: v == 1 ? try .read(&r) : nil)
    }
}

/// Shared tail of the town readers (reader 0x417900 -> 0x417990, version 6…8; 8 in the files).
public struct H4AbstractTown: Sendable, Equatable {
    public let version: UInt16
    /// 0…5 player, 6 neutral.
    public let owner: UInt8
    public let name: String
    public let garrison: H4Army?
    /// Reader 0x417c10: when customised, two 43-bit sets (+0xa4 and +0xcc, presumably the buildings
    /// built and allowed); otherwise a flag byte (bit 3 of +0xa4).
    public let buildings: [H4Bitset]?
    public let buildingFlag: Bool?
    /// Four triggers, then the lists timed, triggerable (script objects), continuous.
    public let events: H4EventSet
    /// Version ≥ 7 when set: two 36-bit sets.
    public let skillSets: [H4Bitset]?
    /// Version ≥ 8 (+0xa0).
    public let flag: UInt8?

    /// Reads the u16 version and the body.
    static func readVersioned(_ r: inout ByteReader) throws -> H4AbstractTown {
        try read(&r, version: try r.u16())
    }

    static func read(_ r: inout ByteReader, version v: UInt16) throws -> H4AbstractTown {
        try r.require((6...8).contains(v), "town version \(v)")
        let owner = try r.u8()
        try r.require(owner < 7, "town owner \(owner)")
        let name = try r.string16()
        let garrison = try r.u8() != 0 ? try H4Army.read(&r) : nil
        var buildings: [H4Bitset]?, buildingFlag: Bool?
        if try r.u8() != 0 {
            buildings = [H4Bitset(bitCount: 43, bytes: Data(try r.bytes(6))), H4Bitset(bitCount: 43, bytes: Data(try r.bytes(6)))]
        } else {
            buildingFlag = try r.u8() != 0
        }
        let events = try H4EventSet.read(&r, triggers: 4, lists: [.timed, .scriptObjects, .continuous])
        var skillSets: [H4Bitset]?
        if v >= 7, try r.u8() != 0 { skillSets = [try .read36(&r), try .read36(&r)] }
        return H4AbstractTown(version: v, owner: owner, name: name, garrison: garrison, buildings: buildings,
                              buildingFlag: buildingFlag, events: events, skillSets: skillSets,
                              flag: v >= 8 ? try r.u8() : nil)
    }
}

/// Town (class 95, reader 0x89a710): only version 4 loads. Two versioned bit sets, then the town.
public struct H4Town: Sendable, Equatable {
    public let version: UInt16
    public let bitsets: [H4VersionedBitset]
    public let town: H4AbstractTown

    static func read(_ r: inout ByteReader) throws -> H4Town {
        let v = try r.u16()
        try r.require(v == 4, "town version \(v)")
        return H4Town(version: v, bitsets: [try .read(&r), try .read(&r)], town: try .readVersioned(&r))
    }
}

/// Random town (class 72, reader 0x7f52b0): version 7 adds a placement rule; version 6 is the bare town.
public struct H4RandomTown: Sendable, Equatable {
    public let version: UInt16
    public let placement: H4PlacementSpec?
    public let town: H4AbstractTown

    static func read(_ r: inout ByteReader) throws -> H4RandomTown {
        let v = try r.u16()
        try r.require(v <= 7, "random town version \(v)")
        if v == 7 {
            let placement = try H4PlacementSpec.read(&r)
            return H4RandomTown(version: v, placement: placement, town: try .readVersioned(&r))
        }
        return H4RandomTown(version: v, placement: nil, town: try .read(&r, version: v))
    }
}
