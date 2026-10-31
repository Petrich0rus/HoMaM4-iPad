import Foundation

/// Where the player's game folder (containing `Data/` and `maps/`) lives, and how it is remembered.
enum GameLocation {
    private static let bookmarkKey = "H4GameFolderBookmark"

    /// Folder used by an app-private copy (`Documents/Game`).
    static var copyDirectory: URL {
        URL.documentsDirectory.appending(path: "Game", directoryHint: .isDirectory)
    }

    /// A folder is valid when it holds `Data` and `maps` (case-insensitive).
    static func isValid(_ root: URL) -> Bool {
        child(of: root, named: "Data") != nil && child(of: root, named: "maps") != nil
    }

    static func child(of root: URL, named name: String) -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return items.first { $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Developer override: `-H4GameDir <path>` launch argument or `H4_GAME_DIR` environment variable.
    static var overrideDirectory: URL? {
        let path = UserDefaults.standard.string(forKey: "H4GameDir") ?? ProcessInfo.processInfo.environment["H4_GAME_DIR"]
        return path.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Restores the folder: override, then app-private copy, then the saved bookmark.
    /// The returned URL is already security-scoped when it came from a bookmark.
    static func restore() -> URL? {
        if let url = overrideDirectory, isValid(url) { return url }
        if isValid(copyDirectory) { return copyDirectory }
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        if stale { save(url) }
        return isValid(url) ? url : nil
    }

    /// Starts access on a freshly picked folder and stores a bookmark for later launches.
    static func adopt(_ url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() else { return false }
        guard isValid(url) else { url.stopAccessingSecurityScopedResource(); return false }
        save(url)
        return true
    }

    private static func save(_ url: URL) {
        if let data = try? url.bookmarkData() { UserDefaults.standard.set(data, forKey: bookmarkKey) }
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        try? FileManager.default.removeItem(at: copyDirectory)
    }

    /// Copies `Data/` and `maps/` of a security-scoped folder into the app's Documents.
    static func copyIntoDocuments(from root: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: copyDirectory)
        try fm.createDirectory(at: copyDirectory, withIntermediateDirectories: true)
        for name in ["Data", "maps"] {
            guard let source = child(of: root, named: name) else { continue }
            try fm.copyItem(at: source, to: copyDirectory.appending(path: name))
        }
    }
}
