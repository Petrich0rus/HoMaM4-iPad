import SwiftUI

struct MapDetailView: View {
    @EnvironmentObject private var library: GameLibrary
    let entry: MapEntry
    @State private var minimaps: [CGImage] = []
    @State private var minimapError: String?
    @State private var loading = true
    @State private var showMap = false
    @State private var showGame = false
    @State private var difficulty = 1
    #if DEBUG
    /// Seed of the new game; the scripted runs use 12345 with difficulty 2 (Hard).
    @State private var seedText = "12345"
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(entry.title).font(.largeTitle.bold())
                Text(entry.path).font(.footnote).foregroundStyle(.secondary)
                if let info = entry.info {
                    facts(info)
                    minimapSection(info)
                    text("Description", info.description)
                    text("Victory", info.victoryText)
                    text("Defeat", info.defeatText)
                    HStack(spacing: 16) {
                        Button("Open map", systemImage: "map.fill") { showMap = true }
                            .buttonStyle(.bordered).controlSize(.large)
                        Button("New game", systemImage: "play.fill") { showGame = true }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(0..<5, id: \.self) { Text(MapEntry.difficultyName($0)).tag($0) }
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 480)
                    #if DEBUG
                    HStack {
                        Text("Seed").foregroundStyle(.secondary)
                        TextField("Seed", text: $seedText).keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(maxWidth: 160)
                    }
                    #endif
                } else {
                    Label("Unsupported map", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(entry.error ?? "").textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showMap) {
            if let store = library.store { MapScreen(entry: entry, store: store) }
        }
        .fullScreenCover(isPresented: $showGame) {
            if let store = library.store { GameScreen(entry: entry, store: store, difficulty: difficulty, seed: gameSeed) }
        }
        .task { await loadMinimaps() }
        #if DEBUG
        .onAppear {
            // Developer aid: `-H4NewGame` starts the game of the preselected map at once (difficulty 2, seed field as is).
            // `-H4Seed <n>` and `-H4Difficulty <n>` set the seed and the difficulty of that game.
            let defaults = UserDefaults.standard
            if let seed = defaults.string(forKey: "H4Seed") { seedText = seed }
            if defaults.bool(forKey: "H4NewGame") {
                difficulty = defaults.object(forKey: "H4Difficulty") == nil ? 2 : defaults.integer(forKey: "H4Difficulty")
                showGame = true
            }
        }
        #endif
    }

    private var gameSeed: UInt32 {
        #if DEBUG
        return UInt32(seedText) ?? 12345
        #else
        return UInt32.random(in: 1...UInt32.max)
        #endif
    }

    private func facts(_ info: MapEntry.Info) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
            GridRow { Text("Size").foregroundStyle(.secondary); Text(entry.sizeLabel ?? "") }
            GridRow { Text("Levels").foregroundStyle(.secondary); Text("\(info.levels)") }
            GridRow { Text("Players").foregroundStyle(.secondary); Text("\(info.players) (\(info.humanPlayers) human)") }
            GridRow { Text("Difficulty").foregroundStyle(.secondary); Text(MapEntry.difficultyName(info.difficulty)) }
        }
    }

    @ViewBuilder private func minimapSection(_ info: MapEntry.Info) -> some View {
        if loading {
            ProgressView("Rendering minimap…")
        } else if let minimapError {
            Label("Minimap unavailable: \(minimapError)", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        } else {
            HStack(alignment: .top, spacing: 20) {
                ForEach(Array(minimaps.enumerated()), id: \.offset) { i, image in
                    VStack {
                        Image(decorative: image, scale: 1)
                            .resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 360).border(.secondary)
                        Text(i == 0 ? "Surface" : "Underground").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private func text(_ title: String, _ value: String?) -> some View {
        if let value = value?.nilIfEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(value)
            }
        }
    }

    private func loadMinimaps() async {
        guard let renderer = library.renderer, entry.isSupported else { return }
        let url = entry.url
        let result = await Task.detached { Result { try renderer.minimaps(for: url) } }.value
        switch result {
        case .success(let images): minimaps = images
        case .failure(let error): minimapError = String(describing: error)
        }
        loading = false
    }
}
