import Foundation
import H4Kit

/// Owns the game folder, the resource store and the scanned map list.
@MainActor
final class GameLibrary: ObservableObject {
    enum State { case needsFolder, loading(String), ready, failed(String) }

    @Published var state: State = .needsFolder
    @Published var maps: [MapEntry] = []
    @Published var scanProgress: (done: Int, total: Int)?
    private(set) var renderer: MinimapRenderer?
    private var root: URL?

    init() {
        Task { await restore() }
    }

    func restore() async {
        state = .loading("Looking for the game folder…")
        if let url = await Task.detached(operation: { GameLocation.restore() }).value {
            await open(url)
        } else {
            state = .needsFolder
        }
    }

    /// Called with a folder chosen in the picker.
    func adopt(_ url: URL) async {
        guard await Task.detached(operation: { GameLocation.adopt(url) }).value else {
            state = .failed("This folder must contain “Data” and “maps” (the GOG HoMM 4 game folder).")
            return
        }
        await open(url)
    }

    /// Copies the chosen folder into the app's Documents, then opens the copy.
    func copyAndAdopt(_ url: URL) async {
        state = .loading("Copying the game files into the app…")
        let result = await Task.detached { () -> Result<Void, Error> in
            guard url.startAccessingSecurityScopedResource() else { return .failure(H4Error.malformed("access denied")) }
            defer { url.stopAccessingSecurityScopedResource() }
            guard GameLocation.isValid(url) else { return .failure(H4Error.malformed("missing Data or maps")) }
            return Result { try GameLocation.copyIntoDocuments(from: url) }
        }.value
        switch result {
        case .success: await open(GameLocation.copyDirectory)
        case .failure(let error): state = .failed("Copy failed: \(error)")
        }
    }

    func forgetFolder() {
        GameLocation.forget()
        maps = []
        renderer = nil
        root = nil
        state = .needsFolder
    }

    private func open(_ root: URL) async {
        self.root = root
        state = .loading("Opening archives…")
        let opened = await Task.detached { () -> Result<(MinimapRenderer, URL), Error> in
            Result {
                guard let data = GameLocation.child(of: root, named: "Data"),
                      let maps = GameLocation.child(of: root, named: "maps") else { throw H4Error.malformed("missing Data or maps") }
                return (MinimapRenderer(store: try H4ResourceStore(dataDirectory: data)), maps)
            }
        }.value
        switch opened {
        case .failure(let error):
            state = .failed("Cannot open the game data: \(error)")
        case .success(let (renderer, mapsDir)):
            self.renderer = renderer
            state = .loading("Reading maps…")
            maps = await scan(mapsDir)
            scanProgress = nil
            state = .ready
        }
    }

    private func scan(_ dir: URL) async -> [MapEntry] {
        await Task.detached { [weak self] in
            MapScanner.scan(mapsDirectory: dir) { done, total in
                if done % 10 == 0 || done == total {
                    Task { @MainActor in self?.scanProgress = (done, total) }
                }
            }
        }.value
    }
}
