import Foundation

/// A single-scenario map file (`maps/*.h4c`), container and header.
///
/// Container (readers 0x5ab3e0 / 0x5ab590 in heroes4.exe):
///
///     "H4CAMPAIGN", u32 version (21 or 22), u8 isCampaign (0 = single scenario)
///     gzip stream with the scenario
///
/// Scenario header (reader 0x77a420, the data the game shows in its scenario list):
///
///     u16 version (20…29); if version ≥ 28: u16 (unknown)
///     u16 size (tiles per side), u8 levels (1 = surface, 2 = with underground), u32 (unknown)
///     u8 playerCount (1…6), per player: u8 colour (0…5), u8 humanPlayable, u8 (unknown),
///                                       u8 0, u8 allowed-alignments mask (6 bits)
///     name, u8 difficulty (0…4), description          (u16-prefixed Windows-1252 strings)
///     u16 0, u8 teamCount, teamCount × u8 player mask
///     u8 + [victory text], u8 + [defeat text]
///     version ≥ 25: u8 (unknown flag)
///     version ≥ 24: victory and defeat blocks, each a u8 flag followed, when set, by a cinematic record
///                   (reader 0x816970: u16 0, str16 text, str16 movie name, str16 second name)
///     version ≥ 27: string (unknown); version ≥ 29: u8 (unknown)
///
/// The scenario body follows (players, availability tables, objects, then terrain — reader
/// 0x4d12d0); it is kept as raw bytes until its object serializers are reconstructed.
public struct H4Scenario: Sendable {
    /// Victory or defeat block of the header (version ≥ 24, reader 0x816970): text plus the names of
    /// two cinematic resources (either may be empty). Not a script.
    public struct Cinematic: Sendable, Equatable {
        public let text: String
        public let movie: String
        public let secondName: String
    }

    public struct Player: Sendable, Equatable {
        public let colour: Int
        public let humanPlayable: Bool
        public let unknown: UInt8
        /// Bit i set = alignment i allowed (6 alignments).
        public let alignments: UInt8
    }

    public let containerVersion: UInt32
    public let version: Int
    public let size: Int
    public let levels: Int
    public let players: [Player]
    public let name: String
    public let difficulty: Int
    public let description: String
    /// One bitmask of player slots per team.
    public let teams: [UInt8]
    public let victoryText: String?
    public let defeatText: String?
    /// Version ≥ 24: the victory block, when its flag is set.
    public let victoryCinematic: Cinematic?
    /// Version ≥ 24: the defeat block, when its flag is set.
    public let defeatCinematic: Cinematic?
    /// Decompressed scenario bytes after the header.
    public let body: Data

    /// Largest decompressed scenario accepted (the biggest shipped map is about 2 MB).
    public static let maxDecompressedSize = 64 * 1024 * 1024

    public init(fileData: Data) throws {
        var r = ByteReader(fileData)
        guard try r.bytes(10) == Data("H4CAMPAIGN".utf8) else { throw H4Error.malformed("not an H4CAMPAIGN file") }
        let containerVersion = try r.u32()
        guard (21...22).contains(containerVersion) else {
            throw H4Error.malformed("campaign container version \(containerVersion)")
        }
        guard try r.u8() == 0 else { throw H4Error.malformed("multi-map campaigns are not supported yet") }
        let stream = try r.bytes(r.remaining)
        guard stream.count >= 18 else { throw H4Error.truncated(at: r.offset, needed: 18) }
        var trailer = ByteReader(stream, offset: stream.count - 4)
        let size = Int(try trailer.u32())
        guard size <= Self.maxDecompressedSize else { throw H4Error.tooLarge(name: "scenario", size: size) }
        try self.init(scenario: Gzip.decompress(stream, expectedSize: size, name: "scenario"),
                      containerVersion: containerVersion)
    }

    init(scenario data: Data, containerVersion: UInt32) throws {
        self.containerVersion = containerVersion
        var r = ByteReader(data)
        version = Int(try r.u16())
        guard (20...29).contains(version) else { throw H4Error.malformed("scenario version \(version)") }
        if version >= 28 { _ = try r.u16() }
        size = Int(try r.u16())
        levels = Int(try r.u8())
        guard (1...2).contains(levels), (1...1024).contains(size) else {
            throw H4Error.malformed("scenario of \(size) tiles × \(levels) levels")
        }
        _ = try r.u32()
        let playerCount = Int(try r.u8())
        guard (1...6).contains(playerCount) else { throw H4Error.malformed("\(playerCount) players") }
        var list: [Player] = []
        for _ in 0..<playerCount {
            let colour = Int(try r.u8())
            guard colour <= 5 else { throw H4Error.malformed("player colour \(colour)") }
            let human = try r.u8() != 0
            let unknown = try r.u8()
            guard try r.u8() == 0 else { throw H4Error.malformed("player alignment block version") }
            list.append(Player(colour: colour, humanPlayable: human, unknown: unknown, alignments: try r.u8()))
        }
        players = list
        guard players.contains(where: \.humanPlayable) else { throw H4Error.malformed("no human-playable player") }
        name = try r.string16()
        difficulty = Int(try r.u8())
        guard difficulty < 5 else { throw H4Error.malformed("difficulty \(difficulty)") }
        description = try r.string16()
        guard try r.u16() == 0 else { throw H4Error.malformed("team block version") }
        let teamCount = Int(try r.u8())
        teams = try (0..<teamCount).map { _ in try r.u8() }
        victoryText = try r.u8() != 0 ? try r.string16() : nil
        defeatText = try r.u8() != 0 ? try r.string16() : nil
        if version >= 25 { _ = try r.u8() }
        func cinematic() throws -> Cinematic? {
            guard try r.u8() != 0 else { return nil }
            guard try r.u16() == 0 else { throw H4Error.malformed("header cinematic version") }
            return Cinematic(text: try r.string16(), movie: try r.string16(), secondName: try r.string16())
        }
        if version >= 24 {
            victoryCinematic = try cinematic()
            defeatCinematic = try cinematic()
        } else {
            victoryCinematic = nil
            defeatCinematic = nil
        }
        if version >= 27 { _ = try r.string16() }
        if version >= 29 { _ = try r.u8() }
        body = Data(try r.bytes(r.remaining))
    }
}
