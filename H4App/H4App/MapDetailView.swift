import SwiftUI

struct MapDetailView: View {
    @EnvironmentObject private var library: GameLibrary
    let entry: MapEntry
    @State private var minimaps: [CGImage] = []
    @State private var minimapError: String?
    @State private var loading = true
    @State private var showMap = false

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
                    Button("Open map", systemImage: "play.fill") { showMap = true }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    Label("Unsupported map", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(entry.error ?? "").textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showMap) { MapView(title: entry.title) }
        .task { await loadMinimaps() }
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
