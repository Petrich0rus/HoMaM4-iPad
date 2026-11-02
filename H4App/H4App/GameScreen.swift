import H4Kit
import SwiftUI

/// Loads a started game off the main thread and publishes the progress.
@MainActor
final class GameLoader: ObservableObject {
    enum Phase {
        case loading(Double, String)
        case ready(GameModel)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading(0, "Opening the map…")

    func load(entry: MapEntry, store: H4ResourceStore, seed: UInt32, difficulty: Int) async {
        let me = self
        let result = await GameModel.load(entry: entry, store: store, seed: seed, difficulty: difficulty) { fraction, message in
            Task { @MainActor in me.report(fraction, message) }
        }
        switch result {
        case .success(let model): phase = .ready(model)
        case .failure(let error): phase = .failed(String(describing: error))
        }
    }

    private func report(_ fraction: Double, _ message: String) {
        if case .loading = phase { phase = .loading(fraction, message) }
    }

    func release() { phase = .loading(0, "") }
}

/// The play screen: the tiled map of a started game with a SwiftUI HUD (date, current player, resources, selected army,
/// End turn). Original HUD art is not used yet.
struct GameScreen: View {
    let entry: MapEntry
    let store: H4ResourceStore
    let difficulty: Int
    let seed: UInt32

    @Environment(\.dismiss) private var dismiss
    @StateObject private var loader = GameLoader()

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            switch loader.phase {
            case .loading(let fraction, let message):
                VStack(spacing: 14) {
                    ProgressView(value: fraction).frame(maxWidth: 320)
                    Text(message).foregroundStyle(.white.opacity(0.8))
                    Button("Close") { dismiss() }.buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VStack(spacing: 12) {
                    ContentUnavailableView("Cannot start this game", systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                        .environment(\.colorScheme, .dark)
                    Button("Close") { dismiss() }.buttonStyle(.borderedProminent)
                }
            case .ready(let model):
                GameContent(model: model, close: { dismiss() })
            }
        }
        .task { await loader.load(entry: entry, store: store, seed: seed, difficulty: difficulty) }
        .onDisappear { loader.release() }
        .statusBarHidden()
    }
}

private struct GameContent: View {
    @ObservedObject var model: GameModel
    let close: () -> Void
    @Environment(\.displayScale) private var displayScale
    @State private var info: MapCellInfo?
    @State private var showTowns = false

    private static let playerColours: [Color] = [.red, .blue, .green, .orange, .purple, .teal]

    var body: some View {
        ZStack {
            TiledMapView(session: model.map, level: min(model.level, model.map.levels.count - 1), displayScale: displayScale,
                         viewport: nil, hooks: model.hooks) { info = $0 }
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                resourceBar
                Spacer()
                bottomBar
            }
            if let info { infoCard(info) }
            TownHost(model: model, town: model.town)
            if let text = model.message {
                VStack {
                    Spacer()
                    Text(text)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 110)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.default, value: model.message)
        .sheet(isPresented: $showTowns) {
            TownListSheet(model: model) { index in
                showTowns = false
                model.town.open(index)
            }
            .presentationDetents([.medium, .large])
        }
        #if DEBUG
        .task {
            await Self.runLaunchScript(model)
            await ScriptFileRunner.runIfRequested(model)
        }
        #endif
    }

    #if DEBUG
    /// Developer aid: `-H4GameScript "select:297;plan:51,57;move;endturn"` runs these commands on the model, waiting for
    /// the walk of a move to finish (the same calls a tap makes).
    private static func runLaunchScript(_ model: GameModel) async {
        guard let script = UserDefaults.standard.string(forKey: "H4GameScript") else { return }
        try? await Task.sleep(for: .seconds(4))
        for command in script.split(separator: ";") {
            let parts = command.split(separator: ":", maxSplits: 1).map(String.init)
            switch parts[0] {
            case "select": if let id = parts.count > 1 ? Int(parts[1]) : nil { model.select(army: id) }
            case "plan":
                let v = (parts.count > 1 ? parts[1] : "").split(separator: ",").compactMap { Int($0) }
                if v.count == 2 { model.plan(to: H4MoveCell(v[0], v[1])) }
            case "move": model.move()
            case "endturn": model.endTurn()
            case "level": if parts.count > 1, let l = Int(parts[1]) { model.level = l }
            default: break
            }
            while model.isWalking { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .seconds(2.5))
        }
        print("GAMESCRIPT done")
    }
    #endif

    private var playerColour: Color { Self.playerColours.indices.contains(model.player) ? Self.playerColours[model.player] : .gray }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button("Close", systemImage: "xmark.circle.fill") { close() }.buttonStyle(.borderedProminent)
            Button("Towns", systemImage: "building.columns.fill") { showTowns = true }
                .buttonStyle(.bordered).disabled(model.isWalking)
            Text(model.title).font(.headline).foregroundStyle(.white).lineLimit(1)
            #if DEBUG
            Text("seed \(model.seed) · difficulty \(model.difficulty)").font(.caption).foregroundStyle(.white.opacity(0.6))
            #endif
            Spacer()
            if model.map.levels.count > 1 {
                Picker("Level", selection: $model.level) {
                    Text("Surface").tag(0)
                    Text("Underground").tag(1)
                }
                .pickerStyle(.segmented).frame(maxWidth: 240)
                .environment(\.colorScheme, .dark)
                .onChange(of: model.level) { _, _ in info = nil }
            }
            HStack(spacing: 6) {
                Circle().fill(playerColour).frame(width: 14, height: 14)
                Text("\(model.playerName) · Day \(model.day) · Week \(model.week) · Month \(model.month)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.white).lineLimit(1).fixedSize()
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.black.opacity(0.45))
    }

    private var resourceBar: some View { ResourceBar(amounts: model.resources) }

    private var bottomBar: some View {
        HStack(alignment: .bottom) {
            armyCard
            Spacer()
            Button {
                model.endTurn()
            } label: {
                Label("End turn", systemImage: "moon.zzz.fill").font(.headline).padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(model.isWalking)
        }
        .padding()
    }

    @ViewBuilder private var armyCard: some View {
        if let a = model.selected {
            VStack(alignment: .leading, spacing: 4) {
                Text(a.label).font(.headline)
                Text("Army \(a.id) · row \(a.cell.r), column \(a.cell.c)").font(.caption).foregroundStyle(.secondary)
                Text("Movement \(a.points) / \(H4GameSession.fullPoints)").font(.callout.monospacedDigit())
                if let p = model.plan, p.ok {
                    Text(p.days > 1 ? "Path: \(p.cost) points, \(p.days) days — tap again to walk" : "Path: \(p.cost) points — tap again to walk")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: 360, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        } else {
            Text("Tap one of your armies").font(.callout).foregroundStyle(.white.opacity(0.85))
                .padding(10).background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func infoCard(_ cell: MapCellInfo) -> some View {
        VStack {
            Spacer()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Row \(cell.row), column \(cell.column)").font(.headline)
                    Text("Terrain: \(cell.terrain)")
                    if let m = cell.objectModel {
                        Text("Object: \(m)")
                        if let c = cell.objectClass { Text("Class: \(c)").foregroundStyle(.secondary) }
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
            .padding(.bottom, 90).padding(.horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
