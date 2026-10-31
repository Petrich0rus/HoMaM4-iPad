import H4Kit
import SwiftUI

/// What a map screen tells whoever drives it (the DEBUG auto-tour).
enum MapScreenEvent: Equatable {
    case loaded
    case failed(String)
}

/// Full-screen map: loads the map off the main thread (with progress), then shows the tiled view with a title, a level
/// toggle for two-level maps, a close button, and an info card after a long press.
struct MapScreen: View {
    let entry: MapEntry
    let store: H4ResourceStore
    var initialLevel = 0
    var viewport: MapViewportHandle?
    var onEvent: (MapScreenEvent) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @StateObject private var loader = MapLoader()
    @State private var level = 0
    @State private var info: MapCellInfo?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            switch loader.phase {
            case .loading(let fraction, let message):
                VStack(spacing: 14) {
                    ProgressView(value: fraction).frame(maxWidth: 320)
                    Text(message).foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView("Cannot open this map", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
                    .environment(\.colorScheme, .dark)
            case .ready(let session):
                TiledMapView(session: session, level: min(level, session.levels.count - 1), displayScale: displayScale,
                             viewport: viewport) { info = $0 }
                    .ignoresSafeArea()
            }
            topBar
            if let info { infoCard(info) }
        }
        .task {
            level = initialLevel
            await loader.load(entry: entry, store: store)
            switch loader.phase {
            case .failed(let message): onEvent(.failed(message))
            default: onEvent(.loaded)
            }
        }
        .onDisappear { loader.release() }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button("Close", systemImage: "xmark.circle.fill") { dismiss() }
                .buttonStyle(.borderedProminent)
            Text(entry.title).font(.headline).foregroundStyle(.white).lineLimit(1)
            Spacer()
            if case .ready(let session) = loader.phase, session.levels.count > 1 {
                Picker("Level", selection: $level) {
                    Text("Surface").tag(0)
                    Text("Underground").tag(1)
                }
                .pickerStyle(.segmented).frame(maxWidth: 260)
                .environment(\.colorScheme, .dark)      // light labels on the dark bar
                .onChange(of: level) { _, _ in info = nil }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.black.opacity(0.45))
    }

    private func infoCard(_ cell: MapCellInfo) -> some View {
        VStack {
            Spacer()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Row \(cell.row), column \(cell.column)").font(.headline)
                    Text("Terrain: \(cell.terrain)")
                    if let model = cell.objectModel {
                        Text("Object: \(model)")
                        if let cls = cell.objectClass { Text("Class: \(cls)").foregroundStyle(.secondary) }
                    } else {
                        Text("No object").foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 24)
                Button("Done", systemImage: "xmark") { info = nil }.labelStyle(.iconOnly)
            }
            .padding(16)
            .frame(maxWidth: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .transition(.opacity)
    }
}

/// Loads a `MapSession` on a background thread and publishes the progress.
@MainActor
final class MapLoader: ObservableObject {
    enum Phase {
        case loading(Double, String)
        case ready(MapSession)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading(0, "Opening the map…")

    func load(entry: MapEntry, store: H4ResourceStore) async {
        let url = entry.url
        let me = self
        let result = await Task.detached(priority: .userInitiated) { () -> Result<MapSession, Error> in
            Result {
                try MapSession.load(url: url, store: store) { fraction, message in
                    Task { @MainActor in me.report(fraction, message) }
                }
            }
        }.value
        switch result {
        case .success(let session): phase = .ready(session)
        case .failure(let error): phase = .failed(String(describing: error))
        }
    }

    private func report(_ fraction: Double, _ message: String) {
        if case .loading = phase { phase = .loading(fraction, message) }
    }

    /// Frees the session (textures, plans, object pixels) when the screen goes away.
    func release() { phase = .loading(0, "") }
}
