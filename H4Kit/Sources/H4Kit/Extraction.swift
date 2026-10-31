import Foundation

public enum H4Extraction {
    /// Maps a resource name to a relative output path: "<type>/<rest of name>".
    /// Names come from untrusted archive bytes, so anything that could escape the
    /// output directory is rejected.
    public static func relativePath(for name: String) throws -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:\0")
        guard !name.isEmpty, name.count <= 255, name.rangeOfCharacter(from: forbidden) == nil,
              !name.hasPrefix("."), !name.contains("..") else {
            throw H4Error.unsafeName(name)
        }
        let parts = name.split(separator: ".", maxSplits: 1)
        return parts.count == 2 ? "\(parts[0])/\(parts[1])" : name
    }

    public struct Report: Sendable {
        public var written = 0
        /// Resources that could not be extracted (e.g. the dangling alias shipped with the game).
        public var failures: [(name: String, error: String)] = []
    }

    /// Writes every resource whose name starts with `prefix` (aliases resolved) under `directory`.
    /// A broken entry is reported and skipped instead of aborting the whole run.
    @discardableResult
    public static func extract(store: H4ResourceStore, to directory: URL, prefix: String = "",
                               progress: ((Int, Int) -> Void)? = nil) -> Report {
        let names = store.names.filter { $0.hasPrefix(prefix) }
        let fm = FileManager.default
        var report = Report()
        for (i, name) in names.enumerated() {
            do {
                let destination = directory.appendingPathComponent(try relativePath(for: name))
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try store.data(for: name).write(to: destination, options: .atomic)
                report.written += 1
            } catch {
                report.failures.append((name, "\(error)"))
            }
            progress?(i + 1, names.count)
        }
        return report
    }
}
