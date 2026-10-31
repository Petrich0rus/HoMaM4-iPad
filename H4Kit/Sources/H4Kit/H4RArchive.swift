import Foundation

/// One resource listed in an H4R directory.
///
/// Directory record layout (little-endian), confirmed on every archive shipped with
/// HoMM4 Complete (GOG):
///
///     u32 dataOffset      absolute offset of the payload (0 for aliases)
///     u32 storedSize      payload size inside the archive
///     u32 size            decompressed size
///     u32 timestamp       Unix time of the original asset
///     u16 + bytes         name, e.g. "layers.button.cancel.h4d"
///     u16 + bytes         original build path (often empty)
///     u16 + bytes         alias target name (empty unless this entry is an alias)
///     u32 storage         1 = stored raw, 3 = gzip
public struct H4REntry: Sendable, Hashable {
    public enum Storage: UInt32, Sendable { case raw = 1, gzip = 3 }

    public let name: String
    public let dataOffset: Int
    public let storedSize: Int
    public let size: Int
    public let timestamp: Date
    public let sourcePath: String
    public let aliasTarget: String?
    public let storage: Storage

    public var isAlias: Bool { aliasTarget != nil }

    /// First dotted component, e.g. "layers", "actor_sequence", "sound", "bink".
    public var resourceType: String {
        name.split(separator: ".", maxSplits: 1).first.map(String.init) ?? name
    }
}

/// Read-only view of a single `.h4r` archive. The file is memory-mapped, so opening the
/// 600 MB `heroes4.h4r` only parses its directory.
public final class H4RArchive: @unchecked Sendable {
    public let url: URL
    public let entries: [H4REntry]
    private let data: Data
    private let index: [String: Int]

    public convenience init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped), url: url)
    }

    public init(data: Data, url: URL = URL(fileURLWithPath: "/memory.h4r")) throws {
        self.url = url
        self.data = data
        var r = ByteReader(data)
        guard data.count >= 8, try r.bytes(4) == Data("H4R".utf8 + [0x05]) else { throw H4Error.badMagic }
        try r.seek(to: Int(try r.u32()))
        let count = Int(try r.u32())
        // Smallest possible record is 26 bytes; reject absurd counts before allocating.
        guard count <= r.remaining / 26 else { throw H4Error.truncated(at: r.offset, needed: count * 26) }

        var list: [H4REntry] = []
        list.reserveCapacity(count)
        for _ in 0..<count {
            let offset = Int(try r.u32())
            let stored = Int(try r.u32())
            let size = Int(try r.u32())
            let time = try r.u32()
            let name = try r.string16()
            let path = try r.string16()
            let alias = try r.string16()
            let code = try r.u32()
            guard let storage = H4REntry.Storage(rawValue: code) else {
                throw H4Error.unknownStorage(name: name, code: code)
            }
            if alias.isEmpty {
                guard offset <= data.count, stored <= data.count - offset else {
                    throw H4Error.entryOutOfBounds(name: name)
                }
            }
            list.append(H4REntry(name: name, dataOffset: offset, storedSize: stored, size: size,
                                 timestamp: Date(timeIntervalSince1970: TimeInterval(time)),
                                 sourcePath: path, aliasTarget: alias.isEmpty ? nil : alias,
                                 storage: storage))
        }
        entries = list
        // Lookups ignore case, like the Windows game (aliases such as "adv_actor.Archdevil.h4d"
        // only resolve that way). If a name is listed twice in one archive, the later record wins.
        index = Dictionary(list.enumerated().map { ($1.name.lowercased(), $0) }, uniquingKeysWith: { _, new in new })
    }

    public func entry(named name: String) -> H4REntry? {
        index[name.lowercased()].map { entries[$0] }
    }

    /// Decompressed payload of a non-alias entry. Aliases must be resolved by the caller
    /// (see `H4ResourceStore`) because their target may live in another archive.
    /// Upper bound on one decompressed resource. The largest shipped entry is a 35 MB Bink
    /// movie; the cap stops a forged size field from forcing a multi-GB allocation on iPad.
    public static let maxResourceSize = 256 * 1024 * 1024

    public func payload(of entry: H4REntry) throws -> Data {
        guard !entry.isAlias else { throw H4Error.notFound(name: entry.name) }
        guard entry.size <= Self.maxResourceSize else { throw H4Error.tooLarge(name: entry.name, size: entry.size) }
        let start = data.startIndex + entry.dataOffset
        let stored = data[start..<(start + entry.storedSize)]
        switch entry.storage {
        case .raw:
            guard stored.count == entry.size else {
                throw H4Error.sizeMismatch(name: entry.name, expected: entry.size, actual: stored.count)
            }
            return Data(stored)
        case .gzip:
            return try Gzip.decompress(stored, expectedSize: entry.size, name: entry.name)
        }
    }
}
