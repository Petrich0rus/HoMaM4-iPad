#if DEBUG
import Foundation
import H4Kit
import os
import SwiftUI

/// DEBUG only, launch argument `-H4AutoPlay`: starts a game (seed 12345, difficulty 2) on every supported map in list order
/// and plays the nearest pickup with the real `GameModel` (no screen): select the lowest-id army of the current player,
/// `nearestPickup`, then each day plan to the same target cell, move, and end the turn (through all humans) until the
/// object is picked up (at most 10 days); after a pick the turn is ended twice. Logs one line per map
/// `PLAY ok <map> picked=<id> days=<n>` / `PLAY skip <map> <reason>` / `PLAY fail <map> <why>`, `PLAY perf <map> peakMB=<n>
/// moveMs=<median>`, and finally `PLAY summary ok=N skip=M fail=K` (print + os_log), then exits.
@MainActor
final class AutoPlay: ObservableObject {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-H4AutoPlay") }
    static let seed: UInt32 = 12345
    static let difficulty = 2

    @Published private(set) var status = "Starting the auto-play…"
    private let logger = Logger(subsystem: "fr.petrichorus.H4App", category: "play")

    private func log(_ line: String) {
        print(line)
        logger.log("\(line, privacy: .public)")
    }

    private enum Outcome {
        case ok(picked: Int, days: Int)
        case skip(String)
        case fail(String)
    }

    @MainActor private struct Perf {
        var peakMB = 0.0
        var moveMs: [Double] = []
        mutating func sample() { peakMB = max(peakMB, AutoTour.footprintMB()) }
        var median: Double { moveMs.isEmpty ? 0 : moveMs.sorted()[moveMs.count / 2] }
    }

    func run(maps: [MapEntry], store: H4ResourceStore) async {
        let supported = maps.filter(\.isSupported)
        log("PLAY start \(supported.count) maps seed=\(Self.seed) difficulty=\(Self.difficulty)")
        var ok = 0, skip = 0, fail = 0
        for entry in supported {
            status = entry.path
            var perf = Perf()
            let outcome = await play(entry, store: store, perf: &perf)
            switch outcome {
            case .ok(let picked, let days):
                ok += 1
                log("PLAY ok \(entry.path) picked=\(picked) days=\(days)")
            case .skip(let reason):
                skip += 1
                log("PLAY skip \(entry.path) \(reason)")
            case .fail(let why):
                fail += 1
                log("PLAY fail \(entry.path) \(why)")
            }
            log(String(format: "PLAY perf %@ peakMB=%.0f moveMs=%.1f", entry.path, perf.peakMB, perf.median))
            try? await Task.sleep(for: .milliseconds(300))      // let the game and its map session go
        }
        status = "PLAY summary ok=\(ok) skip=\(skip) fail=\(fail)"
        log("PLAY summary ok=\(ok) skip=\(skip) fail=\(fail)")
        log(String(format: "PLAY mem final=%.0f MB", AutoTour.footprintMB()))
        try? await Task.sleep(for: .milliseconds(500))
        exit(fail == 0 ? 0 : 1)
    }

    private func play(_ entry: MapEntry, store: H4ResourceStore, perf: inout Perf) async -> Outcome {
        let loaded = await GameModel.load(entry: entry, store: store, seed: Self.seed, difficulty: Self.difficulty) { _, _ in }
        let model: GameModel
        switch loaded {
        case .success(let m): model = m
        case .failure(let error): return .fail("load: \(error)")
        }
        #if DEBUG
        model.dumpDirectory = nil
        #endif
        perf.sample()
        let session = model.session
        let player = session.currentPlayer
        guard let army = session.armies.filter({ $0.owner == player }).map(\.id).min() else { return .skip("no-human-army") }
        if case .failure(let why) = model.select(army: army) { return .fail("select \(why.rawValue)") }
        perf.sample()
        guard let target = session.nearestPickup(for: army) else { return .skip("no-reachable-pickup") }
        perf.sample()

        var picked: Int?
        var days = 0
        while picked == nil && days < 10 {
            days += 1
            let p = model.plan(to: target.targetCell)
            guard p.ok else { return .fail("plan \(p.why?.rawValue ?? "?") day=\(days)") }
            let t0 = DispatchTime.now().uptimeNanoseconds
            let out = model.move(animated: false)
            perf.moveMs.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
            perf.sample()
            guard out.ok else { return .fail("move \(out.why?.rawValue ?? "?") day=\(days)") }
            picked = out.picked
            if picked != nil { break }
            // end the turn through all the humans, back to this player
            var guardCount = 0
            repeat {
                model.endTurn()
                guardCount += 1
            } while session.currentPlayer != player && guardCount < 16
            guard session.currentPlayer == player else { return .fail("endturn did not return to player \(player)") }
            if case .failure(let why) = model.select(army: army) { return .fail("select \(why.rawValue) day=\(days)") }
        }
        guard let picked else { return .fail("not-picked-10d") }
        model.endTurn(); model.endTurn()
        perf.sample()
        return .ok(picked: picked, days: days)
    }
}

struct AutoPlayView: View {
    @EnvironmentObject private var library: GameLibrary
    @StateObject private var play = AutoPlay()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text(play.status).foregroundStyle(.white)
        }
        .task {
            guard let store = library.store else { return }
            await play.run(maps: library.maps, store: store)
        }
    }
}
#endif
