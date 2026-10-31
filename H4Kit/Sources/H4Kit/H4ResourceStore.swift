import Foundation

/// All game archives merged into one namespace, the way the game sees them.
///
/// `heroes4.exe` opens its archives in `defaultLoadOrder`. Here an archive later in the
/// list overrides earlier ones for the same resource name, matching the "_override" /
/// "_updates" naming. That precedence rule is inferred and still has to be confirmed in
/// the decompiled loader.
public final class H4ResourceStore: @unchecked Sendable {
    public static let defaultLoadOrder = [
        "heroes4.h4r", "storm.h4r", "x2.h4r", "movies.h4r", "music.h4r", "text.h4r",
        "updates.h4r", "storm_override.h4r", "storm_updates.h4r", "x2_override.h4r",
        "x2_updates.h4r", "new.h4r",
    ]

    public let archives: [H4RArchive]
    private var winners: [String: (archive: Int, entry: H4REntry)] = [:]

    /// Opens every archive of `loadOrder` present in `dataDirectory` (matched
    /// case-insensitively, since Windows paths are). Missing archives are skipped.
    public convenience init(dataDirectory: URL, loadOrder: [String] = H4ResourceStore.defaultLoadOrder) throws {
        let files = try FileManager.default.contentsOfDirectory(at: dataDirectory, includingPropertiesForKeys: nil)
        let byLowerName = Dictionary(files.map { ($0.lastPathComponent.lowercased(), $0) },
                                     uniquingKeysWith: { a, _ in a })
        try self.init(archives: loadOrder.compactMap { byLowerName[$0.lowercased()] }.map(H4RArchive.init(url:)))
    }

    public init(archives: [H4RArchive]) throws {
        self.archives = archives
        for (i, archive) in archives.enumerated() {
            for entry in archive.entries { winners[entry.name.lowercased()] = (i, entry) }
        }
    }

    /// Names of the winning entries, with the letter case of the archive that provides them.
    public var names: [String] { winners.values.map(\.entry.name).sorted() }

    /// The winning entry for `name` (case-insensitive) and its archive, without following aliases.
    public func locate(_ name: String) -> (archive: H4RArchive, entry: H4REntry)? {
        winners[name.lowercased()].map { (archives[$0.archive], $0.entry) }
    }

    /// Follows alias chains to the entry that actually holds bytes.
    public func resolve(_ name: String) throws -> (archive: H4RArchive, entry: H4REntry) {
        var current = name
        var seen: Set<String> = []
        while true {
            guard seen.insert(current.lowercased()).inserted else { throw H4Error.aliasCycle(name: name) }
            guard let hit = locate(current) else { throw H4Error.notFound(name: current) }
            guard let target = hit.entry.aliasTarget else { return hit }
            current = target
        }
    }

    public func data(for name: String) throws -> Data {
        let hit = try resolve(name)
        return try hit.archive.payload(of: hit.entry)
    }
}
