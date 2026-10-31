import Foundation

// Sections of the scenario body that precede the object list (loader 0x4d12d0, scenario
// versions 27 and 29 only; every version gate below the shipped versions is folded away).
//
// Layout, in file order (reader address in heroes4.exe in brackets):
//
//     list A, list B, list C, list D       u16 count + elements      [0x4cfa90 0x4cfcf0 0x4cff50 0x4d0200]
//     12 availability blocks                                         [0x7c6340]
//     player block                         one entry per header player [0x4d0530]
//     optional bitset (232 bits)           u8 flag + bitset           [0x4d0750]
//     optional blob                        u8 flag + u16 length       [0x4d0920]
//     optional 36-bit set                  u8 flag + u8 0 + 5 bytes   [0x4f0ec0 / 0x857ec0]
//     optional bitset (<= 188 bits)        u8 flag + u16 bits + bytes [0x4d0c10]
//     (0x4d1080 reads nothing for versions >= 24)
//     2 bitsets (<= 248 bits)                                         [0x5515c0 x2]
//     3 id/value maps                                                 [0x5480b0 0x85e790 0x85e790]
//     object list                          u32 count, then records
//
// The script grammar and the event records are in H4ScenarioScripts.swift (decoded from the exe).

/// List B element (0x726d70): entry + string.
public struct H4ScriptElementB: Sendable, Equatable { public let entry: H4ScriptEntry; public let text: String }
/// List C element (0x726de0): script + string.
public struct H4ScriptElementC: Sendable, Equatable { public let script: H4Script; public let text: String }
/// List D element (0x726f90): version 0 or 1; version 1 adds two u8 masks.
public struct H4ScriptElementD: Sendable, Equatable {
    public let version: UInt16
    public let entry: H4ScriptEntry
    public let masks: (UInt8, UInt8)?
    public let text: String
    public static func == (a: Self, b: Self) -> Bool {
        a.version == b.version && a.entry == b.entry && a.text == b.text && a.masks?.0 == b.masks?.0 && a.masks?.1 == b.masks?.1
    }
}

/// Entry of an availability block (polymorphic object, reader 0x7c7130).
/// INFERRED FROM DATA: the "artifact" (6 bytes) and "material" (5 bytes) payloads were deduced from the
/// shipped maps, not read from the exe; any other type name is rejected.
public enum H4AvailabilityObject: Sendable, Equatable {
    /// "artifact": u16 id, then two u16 (1 and 0 in the shipped maps).
    case artifact(id: UInt16, extra1: UInt16, extra2: UInt16)
    /// "material": u8 resource, u32 amount.
    case material(resource: UInt8, amount: UInt32)
}

/// One of the 12 availability blocks (reader 0x7c6340): u16 version 0, u8 flag, u16 value
/// (0xFFFF in the shipped maps); a set flag adds an explicit object list, otherwise the game
/// falls back to its default table (0x9858e4).
public struct H4AvailabilityBlock: Sendable, Equatable {
    public let value: UInt16
    public let hasExplicitList: Bool
    public let objects: [H4AvailabilityObject]
}

/// Player block entry (reader 0x4d0530), one per header player: u8 colour, u8 flag,
/// [u16 when flag], u8 (version >= 23).
public struct H4PlayerSetting: Sendable, Equatable {
    public let colour: UInt8
    public let flag: UInt8
    public let value: UInt16?
    public let extra: UInt8
}

/// A bit string: `bitCount` bits packed LSB-first into `bytes` (ceil(bitCount / 8) bytes).
public struct H4Bitset: Sendable, Equatable {
    public let bitCount: Int
    public let bytes: Data
}

public struct H4IdValue: Sendable, Equatable { public let id: UInt16, value: UInt8 }

/// Everything between the scenario header and the object list.
public struct H4ScenarioSections: Sendable {
    /// List A are timed events (reader 0x726af0).
    public let listA: [H4TimedEvent]
    public let listB: [H4ScriptElementB]
    public let listC: [H4ScriptElementC]
    public let listD: [H4ScriptElementD]
    public let availability: [H4AvailabilityBlock]
    public let playerSettings: [H4PlayerSetting]
    /// 0x4d0750: bitset of at most 248 bits (232 shipped), when present.
    public let bitset248: H4Bitset?
    /// 0x4d0920: raw blob, when present.
    public let blob: Data?
    /// 0x4f0ec0: five raw bytes of a 36-bit set, when present.
    public let set36: Data?
    /// 0x4d0c10: bitset of at most 188 bits, when present.
    public let bitset188: H4Bitset?
    /// 0x5515c0 twice: two bitsets of at most 248 bits.
    public let bitsets: [H4Bitset]
    /// 0x5480b0 (ids < 248), 0x85e790 twice (ids < 188); values are 1 or 2.
    public let idMaps: [[H4IdValue]]
    /// Offset in `H4Scenario.body` of the object list's u32 count.
    public let objectListOffset: Int

    public init(scenario: H4Scenario) throws {
        guard scenario.version == 27 || scenario.version == 29 else {
            throw H4Error.malformed("body sections of scenario version \(scenario.version) are not supported")
        }
        var r = ByteReader(scenario.body)
        func check(_ ok: Bool, _ what: @autoclosure () -> String) throws {
            guard ok else { throw H4Error.malformed("\(what()) at body offset \(r.offset)") }
        }
        func bitset(_ maxBits: Int, leadingZero: Bool) throws -> H4Bitset {
            if leadingZero { try check(try r.u16() == 0, "bitset header") }
            let n = Int(try r.u16())
            try check(n <= maxBits, "bitset of \(n) bits")
            return H4Bitset(bitCount: n, bytes: try r.bytes((n + 7) / 8))
        }

        let a = try H4EventSet.readList(&r, H4TimedEvent.read)
        var b: [H4ScriptElementB] = []
        for _ in 0..<(try r.u16()) {
            try check(try r.u16() == 0, "list B element version")
            b.append(.init(entry: try H4ScriptEntry.read(&r), text: try r.string16()))
        }
        var c: [H4ScriptElementC] = []
        for _ in 0..<(try r.u16()) {
            try check(try r.u16() == 0, "list C element version")
            c.append(.init(script: try H4Script.read(&r), text: try r.string16()))
        }
        var d: [H4ScriptElementD] = []
        for _ in 0..<(try r.u16()) {
            let v = try r.u16()
            try check(v <= 1, "list D element version \(v)")
            let entry = try H4ScriptEntry.read(&r)
            var masks: (UInt8, UInt8)?
            if v == 1 { let m1 = try r.u8(); masks = (m1, try r.u8()) }
            d.append(.init(version: v, entry: entry, masks: masks, text: try r.string16()))
        }
        listA = a; listB = b; listC = c; listD = d

        var blocks: [H4AvailabilityBlock] = []
        for _ in 0..<12 {
            try check(try r.u16() == 0, "availability block version")
            let flag = try r.u8()
            let value = try r.u16()
            var objects: [H4AvailabilityObject] = []
            if flag != 0 {
                for _ in 0..<(try r.u16()) {
                    try check(try r.u16() == 0, "availability object version")
                    let type = try r.string16()
                    switch type {
                    case "artifact": objects.append(.artifact(id: try r.u16(), extra1: try r.u16(), extra2: try r.u16()))
                    case "material": objects.append(.material(resource: try r.u8(), amount: try r.u32()))
                    default: throw H4Error.malformed("unknown availability object '\(type)' at body offset \(r.offset)")
                    }
                }
            }
            blocks.append(.init(value: value, hasExplicitList: flag != 0, objects: objects))
        }
        availability = blocks

        var players: [H4PlayerSetting] = []
        for _ in scenario.players {
            let colour = try r.u8()
            let flag = try r.u8()
            var value: UInt16?
            if flag != 0 { value = try r.u16() }
            players.append(.init(colour: colour, flag: flag, value: value, extra: try r.u8()))
        }
        playerSettings = players

        if try r.u8() != 0 { bitset248 = try bitset(248, leadingZero: true) } else { bitset248 = nil }
        if try r.u8() != 0 { blob = try r.bytes(Int(try r.u16())) } else { blob = nil }
        if try r.u8() != 0 {
            try check(try r.u8() == 0, "36-bit set header")
            set36 = try r.bytes(5)
        } else { set36 = nil }
        if try r.u8() != 0 { bitset188 = try bitset(188, leadingZero: false) } else { bitset188 = nil }
        bitsets = [try bitset(248, leadingZero: true), try bitset(248, leadingZero: true)]

        var maps: [[H4IdValue]] = []
        for limit in [248, 188, 188] {
            try check(try r.u16() == 0, "id map version")
            var m: [H4IdValue] = []
            for _ in 0..<(try r.u16()) {
                let id = try r.u16()
                try check(Int(id) < limit, "id map id \(id)")
                let v = try r.u8()
                try check(v == 1 || v == 2, "id map value \(v)")
                m.append(.init(id: id, value: v))
            }
            maps.append(m)
        }
        idMaps = maps
        objectListOffset = r.offset
    }
}
