import Foundation

// Slice 8a — economy of a started game: starting resources, daily income, creature growth, the Order treasury, weekly
// generators, taxpayers and the computer-player bonus.
//
// Rules R1 and R3 of the frozen reference `session2_ref.py`. Tags: [D] decoded from heroes4.exe (GOG 1.3, addresses = VA),
// [I] inferred / pinned by the reference. The numeric tables below exist only in the executable (not in the Data tables),
// so they are embedded with their address; creature growth and costs are read at runtime from `table.creatures`.

public enum H4Economy {
    /// [D] exe 0x98e9e8, 10 rows x 7 dwords (gold, wood, ore, crystal, sulfur, mercury, gems): row 5 * isComputerTeam + difficulty
    /// (rows of 28 bytes: 0x98e9e8, 0x98ea04, ...).
    public static let startResources: [[Int]] = [
        [20000, 20, 20, 10, 10, 10, 10], [15000, 15, 15, 7, 7, 7, 7], [10000, 10, 10, 5, 5, 5, 5],
        [5000, 10, 10, 5, 5, 5, 5], [0, 10, 10, 5, 5, 5, 5],
        [0, 10, 10, 5, 5, 5, 5], [5000, 10, 10, 5, 5, 5, 5], [10000, 10, 10, 5, 5, 5, 5],
        [15000, 15, 15, 7, 7, 7, 7], [20000, 20, 20, 10, 10, 10, 10],
    ]
    /// [D] exe 0x98cbb8 (read by 0x79c7a0): daily production of a mine per resource.
    public static let mineIncome = [1000, 2, 2, 1, 1, 1, 1]
    /// [D] exe 0x997ff0: pot of a weekly generator per resource.
    public static let generatorPot = [1000, 10, 10, 5, 5, 5, 5]
    /// [D] exe 0x979acc (float32 per difficulty): income multiplier of the computer players.
    public static let computerMultiplier: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0]
    /// [D] exe 0x979b60 (double): the fractional part of the computer bonus is spread over this many days.
    public static let computerSpread = 7.0
    /// [D] exe 0xacffe8 (init 0x88d410): treasury rate per day, 1.1 ** (1 / 7) - 1 (pinned double).
    public static let treasuryRate = 0.013708856295468141
    /// [D] exe 0x63e2c0: the taxpayer creature (peasant), one gold per creature and day.
    public static let peasant = 47
    /// Units of one creature in a dwelling stock [D 0x898310].
    public static let stockPerCreature = 700
    /// Days of a weekly cycle.
    public static let weekDays = 7

    /// R1: starting stock of a player; `computerTeam` = its team has no human player.
    public static func startingResources(computerTeam: Bool, difficulty: Int) -> [Int] {
        startResources[(computerTeam ? 5 : 0) + difficulty]
    }

    /// R3: gold per day of an owned town [D 0x89a0bc]: city hall 1000, else town hall 750, else 500; +3000 with the grail.
    public static func townGold(mask: Int) -> Int {
        let base = mask >> 2 & 1 != 0 ? 1000 : mask >> 1 & 1 != 0 ? 750 : 500
        return base + (mask >> 11 & 1 != 0 ? 3000 : 0)
    }

    /// R3: percentage added to the weekly growth of a town [D 0x898310]. `otherMightGrail`: the owner has ANOTHER might town with
    /// the grail built [I for vcall(5)]; the hero-skill term is 0 [I].
    public static func growthBonus(mask: Int, faction: Int, otherMightGrail: Bool) -> Int {
        var b = 0
        if mask >> 40 & 1 != 0 { b += 50 }
        if mask >> 11 & 1 != 0 && faction == 5 { b += 100 } else if otherMightGrail { b += 25 }
        return b
    }

    /// R3 pass A: stock units a dwelling gains in one day, `((100 + bonus) * growth * 700 // 100) // 7`.
    public static func dailyGrowth(bonus: Int, weeklyGrowth: Int) -> Int {
        ((100 + bonus) * weeklyGrowth * stockPerCreature / 100) / weekDays
    }

    /// R2: stock of a dwelling present at the start (one week of growth).
    public static func initialStock(weeklyGrowth: Int) -> Int { weeklyGrowth * stockPerCreature }

    /// R4: stock of a dwelling built in game, `((growth + 1) * 700) // 2`.
    public static func builtStock(weeklyGrowth: Int) -> Int { (weeklyGrowth + 1) * stockPerCreature / 2 }

    /// R3 pass A: pending treasury in 1/256 gold, `trunc((gold * 256 + carry) * RATE + 0.5)`.
    public static func treasuryPending(gold: Int, carry: Int) -> Int {
        Int((Double(gold * 256 + carry) * treasuryRate + 0.5).rounded(.towardZero))
    }

    /// R3 pass B: adds the pending treasury to the 8.8 carry and returns the whole gold to pay [D 0x7e3e70].
    public static func payTreasury(carry: inout Int, pending: Int) -> Int {
        var c = carry + pending
        var gold = 0
        if c >= 256 { gold = c >> 8; c &= 255 }
        carry = c
        return gold
    }

    /// R3 computer bonus: the change of resource `k` for a daily income `income`, multiplier `m` and day counter `d`
    /// (days elapsed after the advance), before clamping to the stock.
    public static func computerBonus(income: Int, multiplier m: Double, resource k: Int, day d: Int) -> Int {
        let x = Double(income) * (m - 1.0)
        var q = Int(x.rounded(.towardZero))
        let t = Int((x * computerSpread - Double(q) * computerSpread + 0.5).rounded(.towardZero))
        if (d - k + 6) % weekDays < t { q += 1 }
        return q
    }
}

/// A mine of the scenario (R3 pass B).
struct H4MineState: Equatable {
    var owner: Int
    /// 0 gold, 1 wood, 2 ore, 3 crystal, 4 sulfur, 5 mercury, 6 gems.
    var type: Int
    static let subclassTypes: [String: Int] = ["gold_mine": 0, "sawmill": 1, "ore_pit": 2, "crystal_mine": 3, "sulfur_mine": 4,
                                               "alchemists_lab": 5, "gem_mine": 6]
}

/// A weekly material generator (R3 pass B): pays its pot on the first day it is owned, then every 7 days.
struct H4GeneratorState: Equatable {
    var owner: Int
    var type: Int
    var counter = 0
    var potType: Int
    var pot: Int
    /// [I] water_wheel 0 ... leprechaun 6.
    static let subclassTypes: [String: Int] = ["water_wheel": 0, "woodcutters_cottage": 1, "miners_guild": 2, "crystal_garden": 3,
                                               "imp_pit": 4, "apprentices_lab": 5, "leprechaun": 6]

    /// One day of pass B; returns the (resource, amount) paid to the owner, if any. `owned`: the owner is a player of the game.
    mutating func tick(owned: Bool) -> (resource: Int, amount: Int)? {
        if counter > 0 { counter -= 1 }
        guard counter == 0, owned else { return nil }
        let paid = (potType, pot)
        potType = type
        pot = H4Economy.generatorPot[type]
        counter = H4Economy.weekDays
        return paid
    }
}
