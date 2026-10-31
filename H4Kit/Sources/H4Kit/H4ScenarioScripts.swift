import Foundation

// Scripts of the scenario body: the expression-node grammar and the event records built on it.
//
// Decoded from heroes4.exe (99 node classes: 54 actions, 21 numeric expressions, 24 boolean
// expressions). A node is a str16 class name followed by the payload of that class; the three
// kinds have separate name tables, so the same name ("var") may exist in two of them.
//
//     script        FUN_00827ef0   u16 version (2 in every shipped map) + action node
//     expression    FUN_004112a0   u16 version + boolean node
//     entry         FUN_00705e20   script, str16, 7 x u32
//     events        FUN_007d2fd0 / 7d3290 / 7d3530 / 7d37f0, see below
//
// Payload letters of the grammar tables below: see `H4ScriptGrammar.Field`.

public enum H4ScriptNodeKind: Sendable, Equatable { case action, numeric, boolean }

/// One operand of a script node, in the order the bytes appear in the file.
public enum H4ScriptOperand: Sendable, Equatable {
    case byte(UInt8)
    case word(UInt16)
    case int(Int32)
    case text(String)
    case node(H4ScriptNode)
    /// A counted list of actions (`seq`, the tail of `text`).
    case nodes([H4ScriptNode])
    case artifact(H4ArtifactRef)
    case artifacts([H4ArtifactRef])
    /// Seven resource amounts (gold, wood, ore, ...).
    case resources([Int32])
    /// Army of a `combat` node.
    case army(H4Army)
}

/// A node of a script tree: class name plus the operands its payload holds.
public struct H4ScriptNode: Sendable, Equatable {
    public let kind: H4ScriptNodeKind
    public let name: String
    public let operands: [H4ScriptOperand]

    /// Reads one node of `kind` (the version is the script's, which gates a few payloads).
    static func read(_ r: inout ByteReader, kind: H4ScriptNodeKind, version v: UInt16) throws -> H4ScriptNode {
        try r.enter(); defer { r.leave() }
        let name = try r.string16()
        guard let fields = H4ScriptGrammar.fields(kind, name) else {
            throw H4Error.malformed("unknown \(kind) script node '\(name)' at body offset \(r.offset)")
        }
        var ops: [H4ScriptOperand] = []
        ops.reserveCapacity(fields.count)
        for f in fields {
            switch f {
            case let .limited(limit, what):
                let b = try r.u8()
                try r.require(Int(b) < limit, "\(name): \(what) \(b)")
                ops.append(.byte(b))
            case .byte: ops.append(.byte(try r.u8()))
            case .word: ops.append(.word(try r.u16()))
            case .int: ops.append(.int(try r.i32()))
            case .text: ops.append(.text(try r.string16()))
            case .nonEmptyText:
                let s = try r.string16()
                try r.require(!s.isEmpty, "\(name): empty name")
                ops.append(.text(s))
            case .player:
                let b = try r.u8()
                try r.require(Int(b) < (v >= 2 ? 9 : 8), "\(name): player \(b)")
                ops.append(.byte(b))
            case .hero:
                let b = try r.u8()
                try r.require(b < 10, "\(name): hero selector \(b)")
                ops.append(.byte(b))
            case .action: ops.append(.node(try read(&r, kind: .action, version: v)))
            case .number: ops.append(.node(try read(&r, kind: .numeric, version: v)))
            case .boolean: ops.append(.node(try read(&r, kind: .boolean, version: v)))
            case .sequence: ops.append(.nodes(try readSequence(&r, version: v)))
            case .textSequence: ops.append(.nodes(v >= 1 ? try readSequence(&r, version: v) : []))
            case .artifacts: ops.append(.artifacts(try H4ArtifactRef.readList(&r)))
            case .resources: ops.append(.resources(try (0..<7).map { _ in try r.i32() }))
            case .army: ops.append(.army(try H4Army.read(&r)))
            case .creature:
                let c = try r.u16()
                try r.require(Int(c) < H4CreatureStack.creatureCount, "\(name): creature \(c)")
                ops.append(.word(c))
            case .spell:
                let s = try r.u16()
                try r.require(s < 188, "\(name): spell \(s)")
                ops.append(.word(s))
            case .hasArtifact:                       // reader 0x82c660
                let flag = try r.u8()
                ops.append(.byte(flag))
                let who = try r.u8()
                try r.require(Int(who) < (flag != 0 ? (v >= 2 ? 9 : 8) : 4), "\(name): selector \(who)")
                ops.append(.byte(who))
                ops.append(.artifact(try H4ArtifactRef.read(&r)))
            }
        }
        return H4ScriptNode(kind: kind, name: name, operands: ops)
    }

    private static func readSequence(_ r: inout ByteReader, version v: UInt16) throws -> [H4ScriptNode] {
        var out: [H4ScriptNode] = []
        for _ in 0..<(try r.u16()) { out.append(try read(&r, kind: .action, version: v)) }
        return out
    }
}

/// The exe-decoded grammar: payload per node name, for each kind.
enum H4ScriptGrammar {
    enum Field {
        /// u8 below a limit (the label names it in errors).
        case limited(Int, String)
        case byte, word, int, text, nonEmptyText
        /// Player selector: u8 < 9 (script version ≥ 2) or < 8.
        case player
        /// Hero selector: u8 < 10.
        case hero
        case action, number, boolean
        case sequence, textSequence
        case artifacts, resources, army, creature, spell, hasArtifact
    }

    static func fields(_ kind: H4ScriptNodeKind, _ name: String) -> [Field]? {
        switch kind {
        case .action: return actions[name]
        case .numeric: return numbers[name]
        case .boolean: return booleans[name]
        }
    }

    private static func table(_ build: (_ add: ([String], [Field]) -> Void) -> Void) -> [String: [Field]] {
        var t: [String: [Field]] = [:]
        build { names, fields in for n in names { t[n] = fields } }
        return t
    }

    /// 54 action classes (names FUN_0081bb00, readers in the comments).
    static let actions: [String: [Field]] = table { add in
        add(["build"], [.limited(43, "building")])                                             // 0x8239e0
        add(["change_owner"], [.limited(7, "owner")])                                          // 0x823bd0
        add(["clear_lc_text", "clear_l_msg", "clear_vc_text", "clear_v_msg"], [.player])       // 0x830140
        add(["combat"], [.limited(3, "combat selector"), .army, .action, .action])             // 0x824140
        add(["if"], [.boolean, .action, .action])                                              // 0x8248d0
        add(["dec_mana", "inc_mana"], [.hero, .word])                                          // 0x81d7b0
        add(["dec_damage", "dec_max_hp", "dec_max_mana", "dec_speed",
             "inc_damage", "inc_max_hp", "inc_max_mana", "inc_speed"], [.hero, .word, .byte])  // 0x81dac0
        add(["dec_luck", "dec_morale", "inc_luck", "inc_morale"], [.limited(4, "selector"), .byte])   // 0x81ed00
        add(["dec_pop", "inc_pop"], [.limited(9, "selector"), .word])                          // 0x81f720
        add(["detonate", "gosub"], [.text])                                                    // 0x826690
        add(["disable_vc", "enable_vc"], [.player])                                            // 0x830140
        add(["text"], [.text, .textSequence])                                                  // 0x826990
        add(["give_artifact", "rem_artifact"], [.limited(4, "selector"), .artifacts])          // 0x821840
        add(["give_creature", "take_creature"], [.limited(3, "selector"), .creature, .word])   // 0x824ed0
        add(["give_material", "take_material"], [.player, .resources])                         // 0x82fdf0 / 0x82fd20
        add(["give_skill"], [.hero, .limited(36, "skill"), .limited(5, "level")])              // 0x82af60
        add(["give_spell"], [.hero, .spell])                                                   // 0x82bda0
        add(["inc_move"], [.limited(3, "selector"), .byte])                                    // 0x82d330
        add(["inc_exp"], [.hero, .int])                                                        // 0x82eae0
        add(["inc_level"], [.hero, .byte])                                                     // 0x82bd00
        add(["inc_skill"], [.hero, .byte, .limited(36, "skill")])                              // 0x82b230
        add(["no_op", "rem_event", "rem_this"], [])                                            // 0x410c50
        add(["lose", "win"], [.player])                                                        // 0x830140
        add(["ask"], [.text, .action, .action])                                                // 0x832280
        add(["seq"], [.sequence])                                                              // 0x833be0
        add(["set_bool"], [.text, .boolean])                                                   // 0x835cf0
        add(["set_num"], [.text, .number])                                                     // 0x835910
        add(["set_lc_text", "set_l_msg", "set_vc_text", "set_v_msg"], [.player, .text])        // 0x834760
    }

    /// 21 numeric classes (names FUN_00828000).
    static let numbers: [String: [Field]] = table { add in
        add(["creatures"], [.limited(3, "selector"), .creature])                               // 0x825e50
        add(["day", "dow", "month", "week", "wom"], [])                                        // 0x7efef0
        add(["+", "-", "*", "/", "%"], [.number, .number])                                     // 0x820410
        add(["exp_level"], [.hero])                                                            // 0x82cf80
        add(["mastery"], [.hero, .limited(36, "skill")])                                       // 0x82cc00
        add(["lit"], [.int])                                                                   // 0x830650
        add(["materials"], [.player, .limited(7, "resource")])                                 // 0x831250
        add(["neg"], [.number])                                                                // 0x81ff40
        add(["player"], [.player])                                                             // 0x830140
        add(["rand"], [.int, .int])                                                            // 0x832780
        add(["total_creatures", "total_heroes"], [.limited(3, "selector")])                    // 0x825b20
        add(["var"], [.text])                                                                  // 0x837540
    }

    /// 24 boolean classes (names FUN_008286b0).
    static let booleans: [String: [Field]] = table { add in
        add(["and", "or"], [.boolean, .boolean])                                               // 0x82f570
        add(["not"], [.boolean])                                                               // 0x82f0a0
        add(["has_alignment"], [.limited(3, "selector"), .limited(6, "alignment")])            // 0x821080
        add(["has_hero"], [.limited(3, "selector"), .text])                                    // 0x821280
        add(["give_skill?"], [.hero, .limited(36, "skill"), .limited(5, "level")])             // 0x82af60 (the game's name for has-skill)
        add(["==", ">", ">=", "<", "<="], [.number, .number])                                  // 0x832e90
        add(["false", "true"], [])                                                             // 0x7efef0
        add(["has_artifact"], [.hasArtifact])                                                  // 0x82c660
        add(["is_dead", "is_imprisoned"], [.nonEmptyText])                                     // 0x836470
        add(["is_alignment"], [.player, .limited(6, "alignment")])                             // 0x830fd0
        add(["is_color"], [.player, .limited(7, "colour")])                                    // 0x831250
        add(["is_computer", "is_eliminated", "is_human"], [.player])                           // 0x830140
        add(["owns_hero", "owns_town"], [.player, .text])                                      // 0x834760
        add(["var"], [.text])                                                                  // 0x837540
    }
}

/// Script (reader 0x827ef0): u16 version (2 in shipped maps) + action node.
public struct H4Script: Sendable, Equatable {
    public let version: UInt16
    public let root: H4ScriptNode
    static func read(_ r: inout ByteReader) throws -> H4Script {
        let v = try r.u16()
        return H4Script(version: v, root: try .read(&r, kind: .action, version: v))
    }
}

/// Boolean expression (reader 0x4112a0): u16 version (0…2) + boolean node.
public struct H4Expression: Sendable, Equatable {
    public let version: UInt16
    public let root: H4ScriptNode
    static func read(_ r: inout ByteReader) throws -> H4Expression {
        let v = try r.u16()
        try r.require(v <= 2, "expression version \(v)")
        return H4Expression(version: v, root: try .read(&r, kind: .boolean, version: v))
    }
}

/// Common record prefix (reader 0x705e20): script, string, seven u32 (resource-like values).
public struct H4ScriptEntry: Sendable, Equatable {
    public let script: H4Script
    public let text: String
    public let values: [UInt32]
    static func read(_ r: inout ByteReader) throws -> H4ScriptEntry {
        let script = try H4Script.read(&r)
        let text = try r.string16()
        return H4ScriptEntry(script: script, text: text, values: try (0..<7).map { _ in try r.u32() })
    }
}

// MARK: - Event records
//
// Every record starts with `u16 0`. Masks: a player mask (7 bits) and a 2-bit flag mask.

/// Built-in trigger (reader 0x7d2fd0): entry, player mask, flag mask.
public struct H4TriggerEvent: Sendable, Equatable {
    public let entry: H4ScriptEntry
    public let playerMask: UInt8, flags: UInt8
    static func read(_ r: inout ByteReader) throws -> H4TriggerEvent {
        try r.require(try r.u16() == 0, "trigger event version")
        return H4TriggerEvent(entry: try .read(&r), playerMask: try r.u8(), flags: try r.u8())
    }
}

/// Timed event (reader 0x7d3290; also scenario list A): entry, string, two u16, masks.
public struct H4TimedEvent: Sendable, Equatable {
    public let entry: H4ScriptEntry
    public let text: String
    public let word1: UInt16, word2: UInt16
    public let playerMask: UInt8, flags: UInt8
    static func read(_ r: inout ByteReader) throws -> H4TimedEvent {
        try r.require(try r.u16() == 0, "timed event version")
        let entry = try H4ScriptEntry.read(&r)
        let text = try r.string16()
        return H4TimedEvent(entry: entry, text: text, word1: try r.u16(), word2: try r.u16(),
                            playerMask: try r.u8(), flags: try r.u8())
    }
}

/// Script object, "triggerable event" (reader 0x7d3530): entry, string, masks.
public struct H4ScriptObject: Sendable, Equatable {
    public let entry: H4ScriptEntry
    public let text: String
    public let playerMask: UInt8, flags: UInt8
    static func read(_ r: inout ByteReader) throws -> H4ScriptObject {
        try r.require(try r.u16() == 0, "script object version")
        let entry = try H4ScriptEntry.read(&r)
        return H4ScriptObject(entry: entry, text: try r.string16(), playerMask: try r.u8(), flags: try r.u8())
    }
}

/// Continuous event (reader 0x7d37f0): script, string, a byte (+0x24), masks.
public struct H4ContinuousEvent: Sendable, Equatable {
    public let script: H4Script
    public let text: String
    public let flag: UInt8
    public let playerMask: UInt8, flags: UInt8
    static func read(_ r: inout ByteReader) throws -> H4ContinuousEvent {
        try r.require(try r.u16() == 0, "continuous event version")
        let script = try H4Script.read(&r)
        let text = try r.string16()
        return H4ContinuousEvent(script: script, text: text, flag: try r.u8(), playerMask: try r.u8(), flags: try r.u8())
    }
}

/// The event block carried by heroes, armies, towns, mines and garrisons: a few built-in triggers
/// and up to three counted lists. The order of the lists in the file depends on the owner
/// (`lists` of `read`).
public struct H4EventSet: Sendable, Equatable {
    enum List { case timed, scriptObjects, continuous }

    public let triggers: [H4TriggerEvent]
    public let timed: [H4TimedEvent]
    public let scriptObjects: [H4ScriptObject]
    public let continuous: [H4ContinuousEvent]

    public static let empty = H4EventSet(triggers: [], timed: [], scriptObjects: [], continuous: [])

    static func readList<T>(_ r: inout ByteReader, _ element: (inout ByteReader) throws -> T) throws -> [T] {
        var out: [T] = []
        for _ in 0..<(try r.u16()) { out.append(try element(&r)) }
        return out
    }

    /// `triggers` built-in trigger records, then the listed counted lists in the given order.
    static func read(_ r: inout ByteReader, triggers: Int, lists: [List]) throws -> H4EventSet {
        let t = try (0..<triggers).map { _ in try H4TriggerEvent.read(&r) }
        var timed: [H4TimedEvent] = [], objects: [H4ScriptObject] = [], continuous: [H4ContinuousEvent] = []
        for l in lists {
            switch l {
            case .timed: timed = try readList(&r, H4TimedEvent.read)
            case .scriptObjects: objects = try readList(&r, H4ScriptObject.read)
            case .continuous: continuous = try readList(&r, H4ContinuousEvent.read)
            }
        }
        return H4EventSet(triggers: t, timed: timed, scriptObjects: objects, continuous: continuous)
    }
}

/// Placement rule (reader 0x75cae0): u16 0, str16 kind: "none", "player" (+ u8 player) or "town" (+ str16 name).
public enum H4PlacementSpec: Sendable, Equatable {
    case none
    case player(UInt8)
    case town(String)

    static func read(_ r: inout ByteReader) throws -> H4PlacementSpec {
        try r.require(try r.u16() == 0, "placement version")
        let kind = try r.string16()
        switch kind {
        case "none": return .none
        case "player": return .player(try r.u8())
        case "town": return .town(try r.string16())
        default: throw H4Error.malformed("placement kind '\(kind)' at body offset \(r.offset)")
        }
    }
}
