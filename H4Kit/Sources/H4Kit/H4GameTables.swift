import Foundation

// Slice 7a — runtime tables of the game start.
//
// Statistics (level, alignment, experience, expansion; artifact slot/level/availability) are read at runtime from the
// game's own `table.creatures` / `table.Artifacts` resources. Only name-only IDENTIFIER tables that exist solely in
// heroes4.exe are embedded below (no stats, texts or pixels). Tags: [D] decoded from the exe (addresses are VAs),
// [I] inferred.

/// Identifier tables embedded from heroes4.exe (GOG 1.3).
public enum H4GameIdentifiers {
    /// [D] creature id -> keyword: exe enum keyword table (0x985400+), alphabetical enum; keyword lower-cased.
    public static let creatureKeywords: [String] = [
        "air elemental", "archangel", "ballista",
        "bandit", "behemoth", "beholder",
        "black dragon", "bone dragon", "centaur",
        "cerberus", "champion", "crossbowman",
        "crusader", "cyclops", "venom spawn",
        "archdevil", "dragon golem", "dwarf",
        "earth elemental", "efreet", "elf",
        "faerie dragon", "fire elemental", "gargoyle",
        "genie", "ghost", "berserker",
        "gold golem", "griffin", "halfling",
        "harpy", "hydra", "ice demon",
        "imp", "leprechaun", "mage",
        "mantis", "medusa", "mermaid",
        "minotaur", "monk", "mummy",
        "naga", "nightmare", "nomad",
        "ogre mage", "orc", "peasant",
        "phoenix", "pikeman", "pirate",
        "satyr", "sea monster", "skeleton",
        "squire", "sprite", "thunderbird",
        "titan", "troglodyte", "troll",
        "unicorn", "vampire", "water elemental",
        "white tiger", "wolf", "zombie",
        "waspwort", "goblin knight", "evil sorceress",
        "gargantuan", "dark champion", "catapult",
        "frenzied gnasher", "mega dragon",
    ]

    /// [D] creature id -> dwelling adv_object model name (table 0x9740d0, prefixed "creature generators."); "" = none.
    public static let dwellingModels: [String] = [
        "creature generators.Altar of Air", "creature generators.Altar of Light",
        "creature generators.Ballista Works", "creature generators.Den of Thieves",
        "creature generators.Behemoth Crag", "creature generators.PillarOfEyes",
        "creature generators.Dragon Cave", "creature generators.Dragon Graveyard",
        "creature generators.Centaur Stables", "creature generators.Kennels",
        "creature generators.Knight's Chapter", "creature generators.Archery Range",
        "creature generators.Barracks", "creature generators.Cyclops Cave",
        "creature generators.Spawning Pit", "creature generators.Temple of the Damned",
        "creature generators.Dragon Factory", "creature generators.Dwarven Mines",
        "creature generators.Altar of Earth", "creature generators.Lava Tube",
        "creature generators.Homestead", "creature generators.Magic Forest",
        "creature generators.Altar of Fire", "creature generators.Parapet",
        "creature generators.Altar of Wishes", "creature generators.Barrow Mound",
        "creature generators.Berserker Dwelling", "creature generators.Golem Factory",
        "creature generators.Griffin Cliffs", "creature generators.Halfling Burrow",
        "creature generators.Harpy Nest", "creature generators.Hydra Pond",
        "creature generators.Ice Cave", "creature generators.Torture Chamber",
        "creature generators.Faerie Mound", "creature generators.Mage Tower",
        "creature generators.Mantis Nest", "creature generators.Statuary Garden",
        "", "creature generators.Minotaur's Maze",
        "creature generators.Monestary", "creature generators.Cursed Pyramid",
        "creature generators.Golden Pavilion", "creature generators.Black Wood",
        "creature generators.Nomad Tents", "creature generators.Ogre Fort",
        "creature generators.Orc Camp", "creature generators.Hovel",
        "creature generators.Funeral Pyre", "creature generators.Guardhouse",
        "creature generators.Pirates Cove", "creature generators.Enchanted Grove",
        "", "creature generators.Cemetery",
        "creature generators.Squire's Guild", "creature generators.Fae Trees",
        "creature generators.Cliff Nest", "creature generators.Cloud Castle",
        "creature generators.Troglodyte Warren", "creature generators.Troll Cave",
        "creature generators.Unicorn Glade", "creature generators.Mansion",
        "creature generators.Altar of Water", "creature generators.Tiger Den",
        "creature generators.Wolf Den", "creature generators.Crypt",
        "creature generators.hot_house", "creature generators.Goblin_Armory",
        "creature generators.Ward_Sorcery", "creature generators.Gargantuan_Dell",
        "creature generators.Dark_Knights_Sanctum", "creature generators.Siege_Workshop",
        "creature generators.Beast_Pen", "",
    ]

    /// artifact id (0...247) -> keyword of table.Artifacts. Ids 0-... with a model: [D] from the model-name tables of FUN_0042f930;
    /// the other 51 ids: [I] keyword/id pair table 0x97bd34 (id = listed id - 1).
    public static let artifactKeywords: [String] = [
        "adamantine_armor", "adamantine_shield", "amulet_of_fear",
        "amulet_of_the_undertaker", "ankh_of_life", "apprentices_handbook",
        "archmages_spellbook", "armor_of_chaos", "armor_of_darkness",
        "armor_of_light", "armor_of_order", "arms_of_legion",
        "arrow_of_slaying", "arrow_of_stunning", "axe",
        "axe_of_legends", "badge_of_courage", "bag_of_gold",
        "binding", "binding_liquid", "blank_shield",
        "barbarian_throwing_club", "book_of_enchantment", "boots_of_levitation",
        "boots_of_speed", "bow_of_the_white_stag", "brazier_of_sulfur",
        "breastplate_of_regeneration", "brimstone_breastplate", "caduceus",
        "cap_of_knowledge", "cape_of_protection", "cart_of_lumber",
        "cart_of_ore", "centaurs_spear", "chain",
        "chainmail", "chapter_four", "chapter_one",
        "chapter_three", "chapter_two", "circlet_of_wisdom",
        "cloak_of_confusion", "cloud_of_despair", "compass",
        "cowl_of_resistance", "crest_of_valor", "crossbow",
        "crown", "crown_of_dragon_teeth", "crown_of_the_mind",
        "crystal_of_light", "crystal_of_memory", "cube_of_crystals",
        "dark_ruby", "davids_sling", "demon_slayer",
        "demonary", "dragon_scale_armor", "dragon_scale_shield",
        "druids_chain", "dwarven_hammer", "dwarven_shield",
        "ebony_key", "elven_chainmail", "emerald_longbow",
        "equestrians_gloves", "fire_snake", "fireproof_boots",
        "fizbin_of_misfortune", "flaming_arrow", "flaming_sword",
        "flask_of_mercury", "four_leaf_clover", "gamblers_deck",
        "giant_slayer", "gias_gems", "golden_plate_mail",
        "greater_ring_of_vulnerability", "greatsword", "gryphonhearts_plate_mail",
        "guildmasters_compendium", "halberd_of_speed", "hawkins_bow_of_speed",
        "head_of_legion", "helm_of_command", "helm_of_power",
        "helm_of_vision", "hideous_mask", "holy_crown",
        "holy_water", "horseshoe", "infant_dragon_wings",
        "ivory_key", "journeymans_notebook", "kreegan_fire",
        "leather_armor", "left_elephant_tusk", "left_onyx",
        "legs_of_legion", "leprechauns_ring", "lesser_ring_of_vulnerability",
        "lions_shield_of_courage", "logbook_of_the_master_sailor", "longbow",
        "longsword", "mages_robe", "mages_staff",
        "magic_amplifier", "mahogany_key", "mantle_of_spell_turning",
        "marantheas_mug", "masters_journal", "medal_of_honor",
        "mind_shield", "minotaurs_battleax", "mirror_of_spell_turning",
        "monks_mace", "mullichs_helm_of_leadership", "necklace_of_charm",
        "neeners_invulnerable_cloak", "ogs_sandals", "wizards_ring",
        "breeze_the_falcon", "parchment", "parchment",
        "plate_mail", "poison_arrow", "poison_ring",
        "potion_of_cold", "potion_of_endurance", "potion_of_fire_resistance",
        "potion_of_healing", "potion_of_health", "potion_of_luck",
        "potion_of_mana", "potion_of_mirth", "potion_of_precognition",
        "potion_of_quickness", "potion_of_resistance", "potion_of_restoration",
        "potion_of_speed", "potion_of_strength", "purse_of_gold",
        "purse_of_pennypinching", "breeze_the_falcon", "deadwood_staff",
        "rhino_horn", "right_elephant_tusk", "right_onyx",
        "ring_of_elementals", "ring_of_health", "ring_of_permanency",
        "ring_of_protection", "ring_of_regeneration", "ring_of_speed",
        "ring_of_strength", "rising_sun", "robe_of_the_guardian",
        "rod_of_chaos", "ruby", "sack_of_gold",
        "sandalwood_key", "sandwalker_sandals", "sapphire",
        "scale_mail_of_strength", "scroll", "seamans_hat",
        "setting", "shackles_of_war", "shield",
        "shield_of_chaos", "shield_of_darkness", "shield_of_light",
        "shield_of_order", "shield_of_resistance", "snipers_crossbow",
        "snowshoes", "soul_stealer", "spiders_silk_arrow",
        "staads_scarab_of_summoning", "staff_of_death", "staff_of_enchantment",
        "staff_of_power", "staff_of_summoning", "staff_of_the_witch_king",
        "statesmans_medal", "statue_of_legion", "steadfast_shield",
        "supreme_crown_of_the_magi", "surefooted_boots", "swamp_boots",
        "sword_of_swiftness", "sword_of_the_gods", "tavins_sling",
        "telescope", "throwing_spear", "thunder_hammer",
        "tome_of_chaos", "tome_of_death", "tome_of_life",
        "tome_of_nature", "tome_of_order", "torso_of_legion",
        "tynans_dagger_of_despair", "unnatural_armor", "unnatural_shield",
        "valders_bow_of_sloth", "vampiric_amulet", "vial_of_acid",
        "vial_of_blinding_smoke", "vial_of_choking_gas", "vial_of_poison",
        "vial_of_sulfur", "victory_banner", "wand_of_animate_dead",
        "wand_of_bless", "wand_of_curse", "wand_of_fire",
        "wand_of_fireball", "wand_of_haste", "wand_of_healing",
        "wand_of_ice", "wand_of_illusion", "wand_of_weakness",
        "warding_robe", "warlords_ring", "winged_sandals",
        "wizards_ring", "true_gryphonheart_blade", "false_gryphonheart_blade",
        "grail", "cloak_of_darkness", "ring_of_light",
        "tiger_armor", "tiger_helm", "frost_hammer",
        "harmonic_chainmail", "necklace_of_muses", "aiffes_mandolin",
        "necklace_of_balance", "flame_of_chaos", "ice_scales",
        "archmages_hat", "staff_of_disruption", "wayfaring_boots",
        "ring_of_flares", "angelfeather_cloak",
    ]

    /// [D] artifact id -> adv_object model name (without "adv_object."/".h4d"): name tables of FUN_0042f930 (197 entries).
    public static let artifactModels: [Int: String] = [
        0: "artifacts.armor.adamantine armor",
        1: "artifacts.shields.adamantine shield",
        2: "artifacts.amulets.amulet of fear",
        3: "artifacts.amulets.amulet of the undertaker",
        4: "artifacts.amulets.anhk of life",
        5: "artifacts.tomes-books-manuals.apprentices handbook",
        6: "artifacts.tomes-books-manuals.archmages codex",
        7: "artifacts.armor.armor of chaos",
        8: "artifacts.armor.armor of death",
        9: "artifacts.armor.armor of light",
        10: "artifacts.armor.armor of order",
        11: "artifacts.miscellaneous.arms of legion",
        12: "artifacts.miscellaneous.arrow of slaying",
        13: "artifacts.miscellaneous.arrow of stunning",
        14: "artifacts.weapons.axe",
        15: "artifacts.weapons.axe of legends",
        16: "artifacts.miscellaneous.badge of courage",
        17: "artifacts.miscellaneous.bag of gold",
        19: "artifacts.potions.vial of binding liquid",
        21: "artifacts.weapons.barbarian throwing club",
        23: "artifacts.boots.boots of levitation",
        24: "artifacts.boots.boots of travel",
        26: "artifacts.miscellaneous.brazier of sulfur",
        27: "artifacts.armor.breastplate of regeneration",
        28: "artifacts.armor.brimstone breastplate",
        29: "artifacts.staves.caduceus",
        30: "artifacts.helms.cap of knowledge",
        31: "artifacts.cloaks.cape of protection",
        32: "artifacts.miscellaneous.cart of lumber",
        33: "artifacts.miscellaneous.cart of ore",
        34: "artifacts.weapons.centaur's spear",
        36: "artifacts.armor.chain mail",
        41: "artifacts.helms.circlet of wisdom",
        42: "artifacts.cloaks.cloak of distraction",
        43: "artifacts.potions.vial of cloud of despair",
        44: "artifacts.miscellaneous.sextant",
        45: "artifacts.cloaks.cowl of resistance",
        46: "artifacts.miscellaneous.crest of valor",
        47: "artifacts.bows.crossbow",
        50: "artifacts.helms.crown of the mind",
        51: "artifacts.miscellaneous.viewing crystal",
        52: "artifacts.miscellaneous.crystal of memory",
        53: "artifacts.miscellaneous.crystal_figurine",
        55: "artifacts.bows.davids sling",
        56: "artifacts.weapons.demon_slayer",
        57: "artifacts.tomes-books-manuals.demonary",
        58: "artifacts.armor.dragonscale armor",
        59: "artifacts.shields.dragonScale shield",
        60: "artifacts.amulets.Druids chain",
        61: "artifacts.weapons.dwarven hammer",
        62: "artifacts.shields.dwarven shield",
        64: "artifacts.armor.elven chainmail",
        65: "artifacts.bows.emerald_longbow",
        66: "artifacts.item.Equestrian gloves",
        68: "artifacts.boots.FireProofBoots",
        69: "artifacts.amulets.collar of misfortune",
        70: "artifacts.miscellaneous.flaming arrow",
        71: "artifacts.weapons.flaming sword",
        72: "artifacts.miscellaneous.flask of mercury",
        73: "artifacts.miscellaneous.four leaf clover",
        74: "artifacts.miscellaneous.gamblers deck",
        75: "artifacts.weapons.giant_slayer",
        76: "artifacts.miscellaneous.gem casket",
        77: "artifacts.armor.golden platemail",
        78: "artifacts.rings.ring_greater_negation",
        79: "artifacts.weapons.greatsword",
        80: "artifacts.armor.gryphonhearts platemail",
        81: "artifacts.tomes-books-manuals.guildmasters compendium",
        82: "artifacts.weapons.halberd swiftwatch",
        83: "artifacts.bows.bow of the elf king",
        84: "artifacts.miscellaneous.head of legion",
        85: "artifacts.helms.helm of command",
        86: "artifacts.helms.helm of power",
        87: "artifacts.helms.helm of vision",
        88: "artifacts.helms.hideous mask",
        90: "artifacts.potions.holy water",
        91: "artifacts.miscellaneous.horseshoe",
        94: "artifacts.tomes-books-manuals.journeymens notebook",
        95: "artifacts.potions.vial of kreegan fire",
        96: "artifacts.armor.leather",
        99: "artifacts.miscellaneous.legs of legion",
        100: "artifacts.rings.leprechauns ring",
        101: "artifacts.rings.lesser ring of vulnerability",
        102: "artifacts.shields.lions shield of courage",
        103: "artifacts.tomes-books-manuals.logbook of the master sailor",
        104: "artifacts.bows.longbow",
        105: "artifacts.weapons.longsword",
        106: "artifacts.cloaks.mages robes",
        107: "artifacts.staves.mage staff",
        108: "artifacts.helms.magic amplifier",
        110: "artifacts.cloaks.mantle of spell turning",
        111: "artifacts.miscellaneous.marantheas mug of mirth",
        112: "artifacts.tomes-books-manuals.master's spellbook",
        113: "artifacts.amulets.medal of honor",
        114: "artifacts.helms.mind shield",
        115: "artifacts.weapons.bull rune axe",
        116: "artifacts.amulets.mirror revenge",
        117: "artifacts.weapons.crusaders mace",
        118: "artifacts.helms.leadership",
        119: "artifacts.amulets.neckless of charm",
        120: "artifacts.cloaks.neeners",
        121: "artifacts.boots.Surefooted_boots",
        123: "artifacts.miscellaneous.breeze_falcon",
        124: "artifacts.tomes-books-manuals.parchment",
        126: "artifacts.armor.plate mail",
        127: "artifacts.miscellaneous.poison arrow",
        128: "artifacts.rings.poison ring",
        129: "artifacts.potions.potion of cold",
        130: "artifacts.potions.potion of endurance",
        131: "artifacts.potions.potion of fire resistance",
        132: "artifacts.potions.potion of healing",
        133: "artifacts.potions.potion of health",
        134: "artifacts.potions.potion of luck",
        135: "artifacts.potions.potion of mana",
        136: "artifacts.potions.potion of mirth",
        137: "artifacts.potions.potion of precognition",
        138: "artifacts.potions.potion of quickness",
        139: "artifacts.potions.potion of resistance",
        140: "artifacts.potions.potion of restoration",
        141: "artifacts.potions.potion of speed",
        142: "artifacts.potions.potion of strength",
        143: "artifacts.miscellaneous.purse of gold",
        144: "artifacts.miscellaneous.purse of PennyPinching",
        146: "artifacts.staves.deadwood_staff",
        150: "artifacts.rings.ring of the elements",
        151: "artifacts.rings.ring of health",
        152: "artifacts.rings.ring of permanency",
        153: "artifacts.rings.ring of protection",
        154: "artifacts.rings.ring of regeneration",
        155: "artifacts.rings.ring of speed",
        156: "artifacts.rings.ring of strength",
        158: "artifacts.cloaks.robe of the guardian",
        161: "artifacts.miscellaneous.sack of gold",
        163: "artifacts.boots.Sandwalker Sandals",
        165: "artifacts.armor.scalemail of strength",
        166: "artifacts.tomes-books-manuals.scroll",
        167: "artifacts.helms.helm_seamans hat",
        169: "artifacts.miscellaneous.shackles of war",
        170: "artifacts.shields.shield",
        171: "artifacts.shields.shield of chaos",
        172: "artifacts.shields.death shield",
        173: "artifacts.shields.life shield",
        174: "artifacts.shields.shield of order",
        176: "artifacts.bows.sniper's crossbow",
        177: "artifacts.boots.Snow Shoes",
        178: "artifacts.weapons.soul stealer",
        179: "artifacts.miscellaneous.spiders silk",
        180: "artifacts.amulets.scarab summoning",
        181: "artifacts.staves.staff of death",
        182: "artifacts.staves.staff of enchantment",
        183: "artifacts.staves.staff of power",
        184: "artifacts.staves.staff of summoning",
        185: "artifacts.staves.staff of the WitchKing",
        186: "artifacts.amulets.statesmans medal",
        187: "artifacts.miscellaneous.statue of legion",
        188: "artifacts.shields.steadfast shield",
        189: "artifacts.helms.helm_supreme crown of the magi",
        190: "artifacts.boots.boots of the explorer",
        191: "artifacts.boots.crocodile",
        192: "artifacts.weapons.sword of swiftness",
        193: "artifacts.weapons.sword of the gods",
        194: "artifacts.bows.war sling",
        195: "artifacts.item.telescope",
        196: "artifacts.weapons.throwing spear",
        197: "artifacts.weapons.thunder_hammer",
        198: "artifacts.tomes-books-manuals.tome of chaos",
        199: "artifacts.tomes-books-manuals.tome of death",
        200: "artifacts.tomes-books-manuals.tome of life",
        201: "artifacts.tomes-books-manuals.tome of nature",
        202: "artifacts.tomes-books-manuals.tome of order",
        203: "artifacts.miscellaneous.torso of legion",
        204: "artifacts.weapons.tynans_dagger",
        205: "artifacts.armor.unnatural armor",
        206: "artifacts.shields.unnatural shield",
        207: "artifacts.bows.valders bow of sloth",
        209: "artifacts.potions.vial of acid",
        210: "artifacts.potions.vial of blinding smoke",
        211: "artifacts.potions.vial of choking gas",
        212: "artifacts.potions.vial of poison",
        214: "artifacts.miscellaneous.victory banner",
        215: "artifacts.wands.wand of animatedead",
        216: "artifacts.wands.wand of bless",
        217: "artifacts.wands.wand of curse",
        218: "artifacts.wands.wand of fire",
        219: "artifacts.wands.wand of fireball",
        220: "artifacts.wands.wand of haste",
        221: "artifacts.wands.wand of healing",
        222: "artifacts.wands.wand of ice",
        223: "artifacts.wands.wand of illusion",
        224: "artifacts.wands.wand of weakness",
        225: "artifacts.cloaks.warding robe",
        226: "artifacts.rings.warlords ring",
        227: "artifacts.boots.Winged Sandals",
        228: "artifacts.rings.wizards ring",
        229: "artifacts.weapons.gryphonhearts_true_blade",
        230: "artifacts.weapons.gryphonhearts_false_blade",
        231: "artifacts.miscellaneous.grail",
    ]

    /// [D] random tome ids in list order (0x972738).
    public static let tomeIDs = [200, 202, 199, 198, 201]
    /// [D] random staff ids in list order (0x97274c).
    public static let staffIDs = [29, 182, 181, 185, 184]
    /// [D] spell scroll and parchment ids (exe constants): always "used".
    public static let parchmentID = 124, scrollID = 166

    /// [D] faction names of the concrete town models, index = faction (table 0xa5b5d8).
    public static let factionNames = ["haven", "academy", "necropolis", "asylum", "preserve", "stronghold"]
    /// [D] tier names of the concrete town models (table 0xa5b5d8).
    public static let tierNames = ["village", "fort", "citadel", "castle"]
    /// [D] material pile models, index = material 0 gold ... 6 gem (0x791ce0).
    public static let resourceModels = ["resources.gold", "resources.wood", "resources.ore", "resources.crystal",
                                        "resources.sulfur", "resources.mercury", "resources.gem"]
    /// [D] weekly material generator models, index = material - 1 (table 0xa874fc).
    public static let weeklyModels = ["mine.weekly.woodcutters_cottage", "mine.weekly.miner's guilds",
                                      "mine.weekly.crystal pool", "mine.weekly.imp pit",
                                      "mine.weekly.apprentice's lab", "mine.weekly.leprechaun"]
    /// [D] weekly amount produced by the generator, index = material - 1 (table 0x997ff0). Like the reference's numeric
    /// constants, this is a constant table of the executable (not a game resource): it is kept here under the same rule,
    /// i.e. taken from the exe at that address and never re-derived from the game data.
    public static let weeklyAmounts = [10, 10, 5, 5, 5, 5]
    /// [D] shrine / temple / conservatory model parts, index = school (0x46d170, 0x473c00, 0x438030).
    public static let shrineSchools = ["Life", "Order", "Death", "Chaos", "Nature"]
    public static let templeModels = ["Temple of Light", "Temple of Order", "Temple of Darkness", "Temple of Chaos",
                                      "Temple of Nature"]
    public static let conservatorySchools = ["life", "order", "death", "chaos", "nature"]
    /// [D] teacher kind names, index = kind (0x971d48).
    public static let teacherNames = ["Tactician", "Combat", "Scout", "Noble", "Priest", "Scholar", "Lich", "Sorcerer",
                                      "Druid"]
    /// Alignment (= faction) enum names as written in the tables and in town subclasses (0x996634).
    public static let alignmentNames = ["life", "order", "death", "chaos", "nature", "might"]
    /// [D] sea creatures: mermaid, pirate, sea monster (0x7f3380).
    public static let seaCreatures: Set<Int> = [38, 50, 52]
}

/// Creature and artifact tables of one game installation.
public struct H4GameTables: Sendable {
    public struct Creature: Sendable, Equatable {
        public let keyword: String
        public let level: Int
        /// 0...5: life, order, death, chaos, nature, might.
        public let alignment: Int
        /// Column `Experience` (+0x74 of the creature record).
        public let experience: Int
        /// 0 base game, 1 Equilibris, 2 Winds of War.
        public let expansion: Int
        /// Dwelling model name, "" if none.
        public let dwelling: String
        /// Column `Weekly Growth` (0 when the table has no such column).
        public let weeklyGrowth: Int
        /// Columns `Gold` ... `Gems` (gold, wood, ore, crystal, sulfur, mercury, gems; a blank cell is 0).
        public let cost: [Int]
    }
    public struct Artifact: Sendable, Equatable {
        public let slot: String
        public let level: String
        /// `Allowed By Default` is not "X" (flag +0x61 of the record).
        public let flag: Bool
    }

    public let creatures: [Creature]
    public let artifacts: [Artifact]
    public let artifactModels: [Int: String]
    /// Lower-cased model -> artifact id (largest id never wins over a smaller one: models are unique).
    public let artifactIDByModel: [String: Int]
    /// Dwelling pools per level 1...4 (0x43c080): ids ascending, pirate excluded, dwelling present, expansion <= 2.
    public let dwellingPools: [Int: [Int]]

    public init(store: H4ResourceStore) throws {
        let creatureTable = try H4DataTable(data: store.data(for: "table.creatures.h4d"))
        let artifactTable = try H4DataTable(data: store.data(for: "table.Artifacts.h4d"))
        try self.init(creatures: creatureTable, artifacts: artifactTable)
    }

    init(creatures table: H4DataTable, artifacts artTable: H4DataTable) throws {
        let names = H4GameIdentifiers.creatureKeywords
        guard names.count == 74, H4GameIdentifiers.dwellingModels.count == 74 else { throw H4Error.malformed("creature identifier tables") }
        let kc = try table.column("Keyword"), lc = try table.column("Level"), ac = try table.column("Alignment"),
            ec = try table.column("Experience")
        let growthColumn = table.columns.firstIndex(of: "Weekly Growth")
        let costColumns = ["Gold", "Wood", "Ore", "Crystal", "Sulfur", "Mercury", "Gems"].map { table.columns.firstIndex(of: $0) }
        var byKeyword: [String: (level: Int, align: Int, exp: Int, expansion: Int, growth: Int, cost: [Int])] = [:]
        var expansion = 0
        for row in table.rows {
            let key = row[kc]
            if key.hasPrefix("Expansion "), key.hasSuffix(" Creatures below") {
                expansion = Int(key.dropFirst("Expansion ".count).prefix(while: \.isNumber)) ?? expansion
                continue
            }
            if key.hasPrefix("Version ") { continue }
            guard let level = Int(row[lc]), let align = H4GameIdentifiers.alignmentNames.firstIndex(of: row[ac].lowercased()),
                  let exp = Int(row[ec]), exp > 0 else { throw H4Error.malformed("table.creatures row '\(key)'") }
            let growth = growthColumn.flatMap { Int(row[$0]) } ?? 0
            byKeyword[key.lowercased()] = (level, align, exp, expansion, growth, costColumns.map { $0.flatMap { Int(row[$0]) } ?? 0 })
        }
        var list: [Creature] = []
        for (id, name) in names.enumerated() {
            guard let t = byKeyword[name.lowercased()] else { throw H4Error.malformed("table.creatures lacks '\(name)'") }
            list.append(Creature(keyword: name, level: t.level, alignment: t.align, experience: t.exp,
                                 expansion: t.expansion, dwelling: H4GameIdentifiers.dwellingModels[id],
                                 weeklyGrowth: t.growth, cost: t.cost))
        }
        creatures = list

        let akeys = H4GameIdentifiers.artifactKeywords
        let akc = try artTable.column("Keyword"), slotc = try artTable.column("Slot"),
            levelc = try artTable.column("Level"), allowc = try artTable.column("Allowed By Default")
        var byKey: [String: [String]] = [:]
        for row in artTable.rows { byKey[row[akc].lowercased()] = row }
        var arts: [Artifact] = []
        for key in akeys {
            guard let row = byKey[key.lowercased()] else { throw H4Error.malformed("table.Artifacts lacks '\(key)'") }
            arts.append(Artifact(slot: row[slotc], level: row[levelc], flag: row[allowc] != "X"))
        }
        artifacts = arts
        artifactModels = H4GameIdentifiers.artifactModels
        var inverse: [String: Int] = [:]
        for id in artifactModels.keys.sorted() { inverse[artifactModels[id]!.lowercased()] = id }
        artifactIDByModel = inverse
        var pools: [Int: [Int]] = [:]
        for lvl in 1...4 {
            pools[lvl] = list.indices.filter { list[$0].level == lvl && $0 != 50 && !list[$0].dwelling.isEmpty && list[$0].expansion <= 2 }
        }
        dwellingPools = pools
    }
}

/// A `table.*.h4d` resource: a header of column names followed by length-prefixed string rows.
/// The row boundaries are found by scanning (rows have `columns ... columns + 3` strings), as the reference parser does.
struct H4DataTable {
    let columns: [String]
    let rows: [[String]]

    func column(_ name: String) throws -> Int {
        guard let i = columns.firstIndex(of: name) else { throw H4Error.malformed("table column '\(name)'") }
        return i
    }

    init(columns: [String], rows: [[String]]) { self.columns = columns; self.rows = rows }

    init(data: Data) throws {
        let b = [UInt8](data)
        let key: [UInt8] = [0x07, 0x00] + Array("Keyword".utf8)
        guard b.count >= key.count + 2, let start = (2...(b.count - key.count)).first(where: { i in
            (0..<key.count).allSatisfy { b[i + $0] == key[$0] } }) else { throw H4Error.malformed("table header") }
        func u16(_ p: Int) -> Int { Int(b[p]) | Int(b[p + 1]) << 8 }
        func text(_ p: Int, _ n: Int) -> String {
            let d = Data(b[p..<(p + n)])
            return String(data: d, encoding: .windowsCP1252) ?? String(decoding: d, as: UTF8.self)
        }
        let ncol = u16(start - 2)
        guard ncol > 0 else { throw H4Error.malformed("table header without columns") }
        var p = start
        var names: [String] = []
        for _ in 0..<ncol {
            guard p + 2 <= b.count, p + 2 + u16(p) <= b.count else { throw H4Error.malformed("table header") }
            let l = u16(p)
            names.append(text(p + 2, l)); p += 2 + l
        }
        var out: [[String]] = []
        while p + 4 <= b.count {
            let c = u16(p)
            guard c >= ncol, c <= ncol + 3 else { p += 1; continue }
            var q = p + 2
            var row: [String] = []
            var ok = true
            for _ in 0..<c {
                if q + 2 > b.count { ok = false; break }
                let l = u16(q)
                if q + 2 + l > b.count { ok = false; break }
                row.append(text(q + 2, l)); q += 2 + l
            }
            if ok, !row[0].isEmpty { out.append(row); p = q } else { p += 1 }
        }
        columns = names
        rows = out
    }
}

/// Costs of the town buildings, read at runtime from the game's `table.buildings` (columns `Gold` ... `Gems`).
///
/// Layout [V]: u32, u16 column count, the column names, then rows of `u16 count` + length-prefixed strings. A row of the
/// table is a faction header (empty keyword, faction name in the second string), a building (its keyword first), or a
/// separator of one empty string. The n-th header opens the section of faction n (life, order, death, chaos, nature, might).
/// A building id is matched to its row by keyword inside the section of its faction (`H4TownRules.keywords`).
public struct H4BuildingTable: Sendable, Equatable {
    /// Per faction: building id -> 7 costs (gold, wood, ore, crystal, sulfur, mercury, gems).
    public let costs: [[Int: [Int]]]

    init(costs: [[Int: [Int]]]) { self.costs = costs }

    public init(store: H4ResourceStore) throws {
        try self.init(data: store.data(for: "table.buildings.h4d"))
    }

    public init(data: Data) throws {
        let b = [UInt8](data)
        func u16(_ p: Int) throws -> Int {
            guard p + 2 <= b.count else { throw H4Error.malformed("table.buildings truncated") }
            return Int(b[p]) | Int(b[p + 1]) << 8
        }
        func string(_ p: inout Int) throws -> String {
            let n = try u16(p)
            guard p + 2 + n <= b.count else { throw H4Error.malformed("table.buildings truncated") }
            let d = Data(b[(p + 2)..<(p + 2 + n)])
            p += 2 + n
            return String(data: d, encoding: .windowsCP1252) ?? String(decoding: d, as: UTF8.self)
        }
        var p = 4
        let ncol = try u16(p); p += 2
        var columns: [String] = []
        for _ in 0..<ncol { columns.append(try string(&p)) }
        guard let kc = columns.firstIndex(of: "Keyword") else { throw H4Error.malformed("table.buildings without Keyword") }
        let cc = try ["Gold", "Wood", "Ore", "Crystal", "Sulfur", "Mercury", "Gems"].map { name -> Int in
            guard let i = columns.firstIndex(of: name) else { throw H4Error.malformed("table.buildings column '\(name)'") }
            return i
        }
        var sections: [[String: [Int]]] = []
        while p < b.count {
            let c = try u16(p); p += 2
            var row: [String] = []
            for _ in 0..<c { row.append(try string(&p)) }
            if row.count == 1 { continue }
            guard row.count == ncol else { throw H4Error.malformed("table.buildings row of \(row.count) strings") }
            if row[kc].isEmpty { sections.append([:]); continue }
            guard !sections.isEmpty else { throw H4Error.malformed("table.buildings row before the first faction") }
            sections[sections.count - 1][row[kc]] = cc.map { Int(row[$0]) ?? 0 }
        }
        guard sections.count == H4TownRules.keywords.count else { throw H4Error.malformed("table.buildings has \(sections.count) sections") }
        var out: [[Int: [Int]]] = []
        for (f, names) in H4TownRules.keywords.enumerated() {
            var m: [Int: [Int]] = [:]
            for (id, kw) in names {
                guard let cost = sections[f][kw] else { throw H4Error.malformed("table.buildings lacks '\(kw)' (faction \(f))") }
                m[id] = cost
            }
            out.append(m)
        }
        costs = out
    }

    public func cost(faction: Int, building: Int) -> [Int]? { costs[faction][building] }
}
