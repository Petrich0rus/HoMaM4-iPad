import Foundation
import os

/// Tile draw telemetry: the render time of every tile (logged in DEBUG builds as `TILE ms=<x> scale=<s>`) and the
/// counters the DEBUG auto-tour waits on. Thread-safe: CATiledLayer draws tiles on several background threads.
final class TileStats: @unchecked Sendable {
    static let shared = TileStats()
    private let lock = NSLock()
    private var times: [Double] = []
    private var errorMessages: [String] = []
    private var last = Date()
    private let log = Logger(subsystem: "fr.petrichorus.H4App", category: "tiles")

    func record(ms: Double, scale: Int) {
        lock.lock(); times.append(ms); last = Date(); lock.unlock()
        #if DEBUG
        let line = String(format: "TILE ms=%.1f scale=%d", ms, scale)
        print(line)
        log.log("\(line, privacy: .public)")
        #endif
    }

    func recordError(_ message: String) {
        lock.lock(); errorMessages.append(message); last = Date(); lock.unlock()
    }

    func reset() {
        lock.lock(); times = []; errorMessages = []; last = Date(); lock.unlock()
    }

    struct Snapshot { var count: Int; var medianMs: Double; var errors: [String]; var idleSeconds: Double }

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        let sorted = times.sorted()
        return Snapshot(count: sorted.count, medianMs: sorted.isEmpty ? 0 : sorted[sorted.count / 2],
                        errors: errorMessages, idleSeconds: Date().timeIntervalSince(last))
    }
}
