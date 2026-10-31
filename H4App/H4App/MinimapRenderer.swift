import CoreGraphics
import Foundation
import H4Kit

/// Terrain minimaps coloured with the average colour of each terrain texture
/// (same approach as `h4tool minimap`).
final class MinimapRenderer: @unchecked Sendable {
    private let store: H4ResourceStore
    private let lock = NSLock()
    private var colours: [Int: (UInt8, UInt8, UInt8)]?

    init(store: H4ResourceStore) { self.store = store }

    /// Average opaque colour per (terrain, variant), keyed by `terrain * 2 + variant`.
    private func terrainColours() -> [Int: (UInt8, UInt8, UInt8)] {
        lock.lock(); defer { lock.unlock() }
        if let colours { return colours }
        var result: [Int: (UInt8, UInt8, UInt8)] = [:]
        for (t, name) in H4TerrainCell.terrainNames.enumerated() {
            for v in 0..<2 {
                guard let tex = try? H4TerrainTexture(data: store.data(for: "terrain.\(name).\(v + 1).1.h4d")) else { continue }
                var sum = (0, 0, 0), count = 0
                for i in 0..<H4TerrainTexture.tileCount {
                    let px = tex.image(ofTile: i).pixels
                    for p in stride(from: 0, to: px.count, by: 4) where px[p + 3] == 255 {
                        sum.0 += Int(px[p]); sum.1 += Int(px[p + 1]); sum.2 += Int(px[p + 2]); count += 1
                    }
                }
                if count > 0 { result[t * 2 + v] = (UInt8(sum.0 / count), UInt8(sum.1 / count), UInt8(sum.2 / count)) }
            }
        }
        colours = result
        return result
    }

    /// One image per level (surface first). Synchronous and heavy: call off the main thread.
    func minimaps(for mapURL: URL) throws -> [CGImage] {
        let scenario = try H4Scenario(fileData: Data(contentsOf: mapURL))
        let terrain = try H4ScenarioTerrain(scenario: scenario)
        let colours = terrainColours()
        return (0..<terrain.levels).compactMap { level in
            terrain.minimap(level: level) { colours[Int($0.terrain) * 2 + Int($0.variant)] ?? (255, 0, 255) }.cgImage()
        }
    }
}
