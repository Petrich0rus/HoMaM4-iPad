#if DEBUG
import Foundation
import H4Kit
import os
import SwiftUI

/// DEBUG only, launch argument `-H4AutoTown`: on every supported map starts a game (seed 12345, difficulty 2), takes the first
/// town of the first human player and drives the town screen like a finger would: open it (the scene must render with a
/// non-empty draw list), build the first grid building whose status is nil, recruit everything affordable in the first
/// dwelling with creatures available, move the first garrison stack to the first empty garrison slot, exit. Every result is
/// compared with the prediction of the queries (`buildStatus`, `recruitPreview`, `transferPreview`) and with the q3 override
/// rule. Logs `TOWN ok|skip|fail <map> <details>`, `TOWN perf <map> peakMB=<n>` and `TOWN summary ok=N skip=M fail=K peakMB=P`.
@MainActor
final class AutoTown: ObservableObject {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-H4AutoTown") }
    static let seed: UInt32 = 12345
    static let difficulty = 2

    @Published private(set) var status = "Starting the town test…"
    private let logger = Logger(subsystem: "fr.petrichorus.H4App", category: "town")

    private func log(_ line: String) {
        print(line)
        logger.log("\(line, privacy: .public)")
    }

    private enum Outcome {
        case ok(String)
        case skip(String)
        case fail(String)
    }

    func run(maps: [MapEntry], store: H4ResourceStore) async {
        let supported = maps.filter(\.isSupported)
        log("TOWN start \(supported.count) maps seed=\(Self.seed) difficulty=\(Self.difficulty)")
        var ok = 0, skip = 0, fail = 0
        var peak = 0.0
        for entry in supported {
            status = entry.path
            var mapPeak = AutoTour.footprintMB()
            let outcome = await test(entry, store: store, peak: &mapPeak)
            peak = max(peak, mapPeak)
            switch outcome {
            case .ok(let d): ok += 1; log("TOWN ok \(entry.path) \(d)")
            case .skip(let d): skip += 1; log("TOWN skip \(entry.path) \(d)")
            case .fail(let d): fail += 1; log("TOWN fail \(entry.path) \(d)")
            }
            log(String(format: "TOWN perf %@ peakMB=%.0f", entry.path, mapPeak))
            try? await Task.sleep(for: .milliseconds(300))
        }
        log(String(format: "TOWN summary ok=%d skip=%d fail=%d peakMB=%.0f", ok, skip, fail, peak))
        status = "TOWN summary ok=\(ok) skip=\(skip) fail=\(fail)"
        try? await Task.sleep(for: .milliseconds(500))
        exit(fail == 0 ? 0 : 1)
    }

    private func test(_ entry: MapEntry, store: H4ResourceStore, peak: inout Double) async -> Outcome {
        let loaded = await GameModel.load(entry: entry, store: store, seed: Self.seed, difficulty: Self.difficulty) { _, _ in }
        let model: GameModel
        switch loaded {
        case .success(let m): model = m
        case .failure(let error): return .fail("load: \(error)")
        }
        model.dumpDirectory = nil
        peak = max(peak, AutoTour.footprintMB())
        let session = model.session
        guard session.currentPlayer >= 0, let first = session.towns.first(where: { $0.owner == session.currentPlayer }) else {
            return .skip("no-human-town")
        }
        let town = model.town
        let index = first.index
        let startTier = Dictionary(uniqueKeysWithValues: session.towns.map { ($0.index, H4TownRules.tier(mask: $0.mask)) })
        var notes: [String] = []

        // 1. open: the scene renders
        guard town.open(index) else { return .fail("open refused for town \(index)") }
        await town.settle()
        if let error = town.sceneError { return .fail("scene town \(index): \(error)") }
        guard town.image != nil, town.drawCount > 0 else { return .fail("scene town \(index): empty draw list") }
        peak = max(peak, AutoTour.footprintMB())
        notes.append("town=\(index) faction=\(first.faction) draw=\(town.drawCount)")

        // 2. build the first grid building with status nil
        let grid = H4TownRules.gridBuildings(faction: first.faction)
        if let b = grid.first(where: { session.buildStatus(town: index, building: $0) == nil }) {
            let record: H4LogRecord
            do { record = try town.perform(["op": "build", "town": index, "building": b]) } catch { return .fail("build threw \(error)") }
            if !record.ok { return .fail("build \(b): predicted ok, got \(record.why ?? "?")") }
            if session.buildStatus(town: index, building: b) != "already-built" { return .fail("build \(b): status afterwards \(session.buildStatus(town: index, building: b) ?? "nil")") }
            await town.settle()
            if town.sceneError != nil || town.drawCount == 0 { return .fail("scene after build \(b): \(town.sceneError ?? "empty")") }
            // q3: an override exists exactly for the towns whose tier differs from the start
            var expected: [Int: String] = [:]
            for t in session.towns where H4TownRules.tier(mask: t.mask) != startTier[t.index] { expected[t.index] = t.model }
            let got = session.renderState.modelOverride
            if got != expected { return .fail("override after build \(b): got \(got) expected \(expected)") }
            notes.append("build=\(b)\(got.isEmpty ? "" : " tier->" + (got[index] ?? "?"))")
        } else {
            notes.append("build=none")
        }

        // 3. recruit everything affordable in the first dwelling with creatures
        let cur = session.town(index)!
        if let b = (12...19).first(where: { (session.recruitPreview(town: index, building: $0)?.available ?? 0) > 0 }),
           let p = session.recruitPreview(town: index, building: b) {
            if p.maxAffordable > 0 {
                let resBefore = session.resources(player: session.currentPlayer)!.amounts
                let countBefore = session.town(index)!.garrison.filter { $0.creature == p.creature }.reduce(0) { $0 + $1.count }
                let record: H4LogRecord
                do { record = try town.perform(["op": "recruit", "town": index, "building": b, "count": p.maxAffordable]) } catch { return .fail("recruit threw \(error)") }
                let n = record.int("recruited") ?? -1
                if !record.ok || n != p.maxAffordable { return .fail("recruit \(b): preview \(p.maxAffordable), got ok=\(record.ok) n=\(n) why=\(record.why ?? "-")") }
                let resAfter = session.resources(player: session.currentPlayer)!.amounts
                let cost = session.creatureCost(p.creature)!
                for k in 0..<7 where resBefore[k] - resAfter[k] != n * cost[k] {
                    return .fail("recruit \(b): resource \(k) delta \(resBefore[k] - resAfter[k]) != \(n) x \(cost[k])")
                }
                let countAfter = session.town(index)!.garrison.filter { $0.creature == p.creature }.reduce(0) { $0 + $1.count }
                if countAfter - countBefore != n { return .fail("recruit \(b): garrison delta \(countAfter - countBefore) != \(n)") }
                notes.append("recruit=\(b)x\(n)")
            } else {
                notes.append("recruit=\(b) none-affordable")
            }
        } else {
            notes.append("recruit=none")
        }

        // 4. transfer the first stack into the first empty garrison slot
        let g = session.town(index)!.garrison
        if let from = g.firstIndex(where: { $0.creature >= 0 }), let to = g.indices.first(where: { $0 != from && g[$0].creature == -1 }) {
            let predicted = session.transferPreview(from: ["town": index, "slot": from], to: ["town": index, "slot": to])
            let record: H4LogRecord
            do {
                record = try town.perform(["op": "transfer", "from": ["town": index, "slot": from], "to": ["town": index, "slot": to]])
            } catch { return .fail("transfer threw \(error)") }
            if record.ok != predicted.ok || record.why != predicted.why || record.int("moved") != predicted.count {
                return .fail("transfer \(from)->\(to): preview \(predicted) got ok=\(record.ok) why=\(record.why ?? "-") moved=\(record.int("moved") ?? -1)")
            }
            let after = session.town(index)!.garrison
            if record.ok && (after[to] != g[from] || after[from] != .empty) { return .fail("transfer \(from)->\(to): slots not moved") }
            notes.append("transfer=\(from)->\(to)")
        } else {
            notes.append("transfer=none")
        }
        _ = cur
        // 5. exit
        town.close()
        peak = max(peak, AutoTour.footprintMB())
        return .ok(notes.joined(separator: " "))
    }
}

struct AutoTownView: View {
    @EnvironmentObject private var library: GameLibrary
    @StateObject private var run = AutoTown()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text(run.status).foregroundStyle(.white)
        }
        .task {
            guard let store = library.store else { return }
            await run.run(maps: library.maps, store: store)
        }
    }
}
#endif
