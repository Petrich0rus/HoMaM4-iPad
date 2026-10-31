import Foundation
import H4Kit

/// Reads the headers of every `.h4c` below a `maps/` folder. Synchronous and heavy: call off the main thread.
enum MapScanner {
    static func scan(mapsDirectory: URL, progress: ((Int, Int) -> Void)? = nil) -> [MapEntry] {
        let base = mapsDirectory.standardizedFileURL.path
        let urls = (FileManager.default.enumerator(at: mapsDirectory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension.lowercased() == "h4c" }
        var entries: [MapEntry] = []
        for (i, url) in urls.enumerated() {
            let path = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            entries.append(entry(url: url, path: path))
            progress?(i + 1, urls.count)
        }
        return entries.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func entry(url: URL, path: String) -> MapEntry {
        do {
            let s = try H4Scenario(fileData: Data(contentsOf: url))
            let info = MapEntry.Info(
                name: s.name, size: s.size, levels: s.levels, players: s.players.count,
                humanPlayers: s.players.filter(\.humanPlayable).count, difficulty: s.difficulty,
                description: s.description, victoryText: s.victoryText, defeatText: s.defeatText)
            return MapEntry(path: path, url: url, info: info, error: nil)
        } catch {
            return MapEntry(path: path, url: url, info: nil, error: String(describing: error))
        }
    }
}
