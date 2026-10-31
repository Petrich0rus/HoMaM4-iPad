import Foundation

/// One scenario file found under `maps/`, with the header fields shown in the list.
struct MapEntry: Identifiable, Hashable {
    struct Info: Hashable {
        var name: String
        var size: Int
        var levels: Int
        var players: Int
        var humanPlayers: Int
        var difficulty: Int
        var description: String
        var victoryText: String?
        var defeatText: String?
    }

    let path: String           // relative to maps/
    let url: URL
    let info: Info?
    let error: String?

    var id: String { path }
    var title: String { info?.name.nilIfEmpty ?? (path as NSString).lastPathComponent }
    var isSupported: Bool { info != nil }

    var sizeLabel: String? {
        info.map { "\($0.size)×\($0.size)" }
    }

    static func difficultyName(_ value: Int) -> String {
        let names = ["Easy", "Normal", "Hard", "Expert", "Impossible"]
        return names.indices.contains(value) ? names[value] : "Difficulty \(value)"
    }
}

extension String {
    var nilIfEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
