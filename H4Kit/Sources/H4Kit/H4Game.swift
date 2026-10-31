import Foundation

// Slice 7a — state of a started game (static map + dynamic layer to come in later slices).

/// Difficulty of a new game (game+0x64c): 0 easy, 1 normal, 2 hard, 3 expert, 4 impossible.
public typealias H4Difficulty = Int

public struct H4GamePlayer: Sendable, Equatable {
    public let colour: Int
    public let human: Bool
    /// Faction 0...5 (life, order, death, chaos, nature, might); lowest allowed alignment [I].
    public let faction: Int
}

/// Concrete choices made for one random placeholder (or windmill). Keys of the reference JSON are the property names;
/// only the properties that apply to the class are set.
public struct H4ResolvedObject: Sendable, Equatable {
    /// Concrete adv_object / adv_actor model name; nil when nothing is placed.
    public var model: String?
    public var faction: Int?, tier: Int?, r: Int?
    public var creature: Int?, level: Int?, count: Int?
    public var stacks: [H4ArmyStack]?
    public var budget: Int?
    public var special: Bool?
    public var removed: Bool?
    public var artifact: Int?
    public var material: Int?, amount: Int?
    public var gold: Bool?, produces: Int?
    public var school: Int?
    /// The key "spell" is present (always null: spell choice is a documented gap).
    public var hasNullSpell = false
    public var teacher: Int?
}

public struct H4ArmyStack: Sendable, Equatable {
    public var creature: Int
    public var count: Int
}

/// An object of the started game that was affected by the game start (resolved placeholder or windmill).
public struct H4GameObject: Sendable, Equatable {
    /// Index in the scenario object list.
    public let index: Int
    public let x: Int, y: Int, level: Int
    /// The ORIGINAL placeholder class and its subclass name ("" if none).
    public let className: String
    public let subclass: String
    /// Owner 0...6 (6 neutral); nil when the class has none.
    public let owner: Int?
    public let resolved: H4ResolvedObject
}

/// State of a game after the game start.
public struct H4Game: Sendable {
    public static let expansion = 2
    public let seed: UInt32
    public let difficulty: H4Difficulty
    public let players: [H4GamePlayer]
    /// Objects with a resolver, in scenario file order.
    public let objects: [H4GameObject]
    /// Current day, 1-based.
    public var day = 1
}
