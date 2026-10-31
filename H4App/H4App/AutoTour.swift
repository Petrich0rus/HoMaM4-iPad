#if DEBUG
import Foundation
import H4Kit
import os
import SwiftUI

/// DEBUG only, launch argument `-H4AutoTour`: opens every supported map and level in turn in the real `MapScreen` /
/// `TiledMapView`, waits for the visible tiles to be drawn (fit view, then one device pixel per canvas pixel), and logs
/// `TOUR ok <relpath> L<level> tiles=<n> ms=<median tile ms>` or `TOUR fail <relpath> L<level> <error>` and finally
/// `TOUR done <ok> ok, <fail> fail` (print + os_log; also `TOUR mem <MB>` after every step).
@MainActor
final class AutoTour: ObservableObject {
    struct Step: Equatable {
        let entry: MapEntry
        let level: Int
        let token: Int
    }

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-H4AutoTour") }

    @Published private(set) var step: Step?
    @Published private(set) var status = "Starting the tour…"
    let viewport = MapViewportHandle()
    private var event: MapScreenEvent?
    private let logger = Logger(subsystem: "fr.petrichorus.H4App", category: "tour")
    private var token = 0

    func deliver(_ e: MapScreenEvent) { event = e }

    private func log(_ line: String) {
        print(line)
        logger.log("\(line, privacy: .public)")
    }

    func run(maps: [MapEntry], store: H4ResourceStore) async {
        var ok = 0, failed = 0
        let supported = maps.filter(\.isSupported)
        log("TOUR start \(supported.count) maps")
        for entry in supported {
            for level in 0..<(entry.info?.levels ?? 1) {
                status = "\(entry.path) L\(level)"
                let outcome = await visit(entry, level: level)
                switch outcome {
                case .success(let (tiles, median)):
                    ok += 1
                    log(String(format: "TOUR ok %@ L%d tiles=%d ms=%.1f", entry.path, level, tiles, median))
                case .failure(let error):
                    failed += 1
                    log("TOUR fail \(entry.path) L\(level) \(error.message)")
                }
                log(String(format: "TOUR mem %.0f MB", Self.footprintMB()))
                step = nil
                try? await Task.sleep(for: .milliseconds(400))      // let the screen and its session go
            }
        }
        status = "TOUR done \(ok) ok, \(failed) fail"
        log("TOUR done \(ok) ok, \(failed) fail")
        // Quit so a script waiting on the launch (simctl --console-pty) can go on.
        try? await Task.sleep(for: .milliseconds(500))
        exit(failed == 0 ? 0 : 1)
    }

    private struct TourError: Error { let message: String }

    private func visit(_ entry: MapEntry, level: Int) async -> Result<(Int, Double), TourError> {
        TileStats.shared.reset()
        event = nil
        token += 1
        step = Step(entry: entry, level: level, token: token)

        let loadDeadline = Date().addingTimeInterval(180)
        while event == nil, Date() < loadDeadline { try? await Task.sleep(for: .milliseconds(100)) }
        switch event {
        case .failed(let message): return .failure(TourError(message: message))
        case .none: return .failure(TourError(message: "timeout while loading"))
        case .loaded: break
        }
        guard await waitForTiles(after: 0, timeout: 60) else { return .failure(TourError(message: "timeout: fit-view tiles not drawn")) }
        let first = TileStats.shared.snapshot().count
        guard viewport.isAttached else { return .failure(TourError(message: "no scroll view")) }
        viewport.zoomToNativePixels()
        guard await waitForTiles(after: first, timeout: 20) else { return .failure(TourError(message: "timeout: 1:1 tiles not drawn")) }
        let s = TileStats.shared.snapshot()
        if let error = s.errors.first { return .failure(TourError(message: "tile error: \(error)")) }
        return .success((s.count, s.medianMs))
    }

    /// True once more than `after` tiles have been drawn and none for 0.7 s.
    private func waitForTiles(after: Int, timeout: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let s = TileStats.shared.snapshot()
            if s.count > after, s.idleSeconds > 0.7 { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}

struct AutoTourView: View {
    @EnvironmentObject private var library: GameLibrary
    @StateObject private var tour = AutoTour()

    var body: some View {
        ZStack {
            if let step = tour.step, let store = library.store {
                MapScreen(entry: step.entry, store: store, initialLevel: step.level, viewport: tour.viewport) { tour.deliver($0) }
                    .id(step.token)
            } else {
                Color.black.ignoresSafeArea()
                Text(tour.status).foregroundStyle(.white)
            }
        }
        .task {
            guard let store = library.store else { return }
            await tour.run(maps: library.maps, store: store)
        }
    }
}
#endif
