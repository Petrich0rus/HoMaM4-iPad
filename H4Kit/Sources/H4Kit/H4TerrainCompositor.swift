import Dispatch
import Foundation

/// CPU compositor for the terrain of a map region (rules R4–R7 of `H4MapTerrainRender`).
///
/// Holds caches of decoded textures, tiles and masks, so one instance should render many maps.
/// Resources that cannot be found are recorded in `missingTextures` / `missingMasks` (the affected
/// draw items are skipped) instead of aborting the render. Not safe to call from several threads at once.
public final class H4TerrainCompositor: @unchecked Sendable {
    /// Bytes of a 64×32 RGBA tile or mask grid, owned manually so bands can read it from several threads.
    private final class Pixels: @unchecked Sendable {
        let p: UnsafeMutablePointer<UInt8>
        init(_ bytes: [UInt8]) { p = .allocate(capacity: bytes.count); p.initialize(from: bytes, count: bytes.count) }
        deinit { p.deallocate() }
    }
    private struct TileKey: Hashable { var texture: H4TerrainTextureRef; var index: Int }
    private struct Resolved { var x: Int, y: Int; var tile: Pixels; var mask: Pixels? }

    private let loader: @Sendable (String) throws -> Data
    private let transitions: H4TransitionLibrary
    private var textures: [H4TerrainTextureRef: H4TerrainTexture?] = [:]
    private var tiles: [TileKey: Pixels] = [:]
    private var masks: [H4MaskRef: Pixels?] = [:]
    public private(set) var missingTextures: Set<String> = []
    public private(set) var missingMasks: Set<String> = []

    public init(transitions: H4TransitionLibrary, loader: @escaping @Sendable (String) throws -> Data) {
        self.transitions = transitions
        self.loader = loader
    }

    public convenience init(store: H4ResourceStore) throws {
        try self.init(transitions: H4TransitionLibrary(data: store.data(for: "transition.Transitions.h4d")),
                      loader: { try store.data(for: $0) })
    }

    // MARK: resolving (single-threaded)

    private func tile(_ item: H4TerrainDrawItem) throws -> Pixels? {
        let key = TileKey(texture: item.texture, index: item.tileIndex)
        if let hit = tiles[key] { return hit }
        let texture: H4TerrainTexture?
        if let cached = textures[item.texture] {
            texture = cached
        } else {
            let name = item.texture.resourceName
            do {
                texture = try H4TerrainTexture(data: loader(name))
            } catch H4Error.notFound {
                missingTextures.insert(name)
                texture = nil
            }
            textures[item.texture] = .some(texture)
        }
        guard let texture, texture.tiles.indices.contains(item.tileIndex) else { return nil }
        let made = Pixels(texture.image(ofTile: item.tileIndex).pixels)
        tiles[key] = made
        return made
    }

    private func mask(_ ref: H4MaskRef) -> Pixels? {
        if let cached = masks[ref] { return cached }
        var made: Pixels?
        if let set = ref.set, let m = transitions.mask(set: H4MapTerrainRender.maskSetNames[set], index: ref.index) {
            made = Pixels(m.storage.map { a in
                a == H4TransitionLibrary.outside ? 0 : (ref.inverted ? 15 - a : a)
            })
        } else {
            missingMasks.insert("\(ref.set.map { H4MapTerrainRender.maskSetNames[$0] } ?? "unknown set") #\(ref.index)")
        }
        masks[ref] = .some(made)
        return made
    }

    private func resolve(_ items: [H4TerrainDrawItem]) throws -> [Resolved] {
        var out: [Resolved] = []
        out.reserveCapacity(items.count)
        for item in items {
            var maskPixels: Pixels?
            if let ref = item.mask {
                guard let m = mask(ref) else { continue }
                maskPixels = m
            }
            guard let tile = try tile(item) else { continue }
            out.append(Resolved(x: item.x, y: item.y, tile: tile, mask: maskPixels))
        }
        return out
    }

    // MARK: compositing

    /// Renders `region` of `level`: the scale-1 canvas (R6/R7) reduced by a `scale`×`scale` box average of the
    /// four channels (integer floor); the image is floor(W/scale) × floor(H/scale).
    public func render(terrain: H4ScenarioTerrain, level: Int, region: H4MapTerrainRender.Region,
                       scale k: Int = 1) throws -> H4RGBAImage {
        guard (0..<terrain.levels).contains(level) else { throw H4Error.malformed("level \(level) outside 0..<\(terrain.levels)") }
        guard k >= 1, region.rows >= 1, region.columns >= 1 else { throw H4Error.malformed("empty region or scale") }
        let W = region.canvasWidth, H = region.canvasHeight
        let outW = W / k, outH = H / k
        guard outW > 0, outH > 0 else { throw H4Error.malformed("region too small for scale \(k)") }

        let list = H4MapTerrainRender.drawList(terrain: terrain, level: level, region: region)
        let passes = [try resolve(list.bases), try resolve(list.overlays), try resolve(list.roads)]

        // Items of each pass are sorted by y, so the ones touching a band of canvas rows form a contiguous range.
        @Sendable func range(_ items: [Resolved], _ y0: Int, _ y1: Int) -> Range<Int> {
            func lowerBound(_ v: Int) -> Int {          // first item with y >= v
                var lo = 0, hi = items.count
                while lo < hi { let mid = (lo + hi) / 2; if items[mid].y < v { lo = mid + 1 } else { hi = mid } }
                return lo
            }
            return lowerBound(y0 - 31)..<lowerBound(y1)
        }

        var out = [UInt8](repeating: 0, count: outW * outH * 4)
        let bandRows = max(1, 128 / k)                  // output rows per band
        let bands = (outH + bandRows - 1) / bandRows
        out.withUnsafeMutableBufferPointer { outBuffer in
            let dest = SendablePointer(p: outBuffer.baseAddress!)
            DispatchQueue.concurrentPerform(iterations: bands) { band in
                let o0 = band * bandRows, o1 = min(outH, o0 + bandRows)
                let y0 = o0 * k, bh = (o1 - o0) * k
                let canvas = UnsafeMutablePointer<UInt8>.allocate(capacity: W * bh * 4)
                canvas.initialize(repeating: 0, count: W * bh * 4)
                defer { canvas.deallocate() }
                for (n, items) in passes.enumerated() {
                    for i in range(items, y0, y0 + bh) {
                        Self.draw(items[i], base: n == 0, canvas: canvas, width: W, y0: y0, rows: bh)
                    }
                }
                Self.reduce(canvas, width: W, scale: k, outWidth: outW, outRows: o1 - o0,
                            into: dest.p + o0 * outW * 4)
            }
        }
        return H4RGBAImage(width: outW, height: outH, pixels: out)
    }

    private struct SendablePointer: @unchecked Sendable { let p: UnsafeMutablePointer<UInt8> }

    private static func draw(_ item: Resolved, base: Bool, canvas: UnsafeMutablePointer<UInt8>,
                             width W: Int, y0: Int, rows: Int) {
        let tile = item.tile.p
        for ty in 0..<32 {
            let by = item.y + ty - y0
            guard by >= 0, by < rows else { continue }
            let dst = canvas + (by * W + item.x) * 4
            let src = tile + ty * 64 * 4
            if base {
                for x in 0..<64 where src[x * 4 + 3] != 0 {
                    dst[x * 4] = src[x * 4]; dst[x * 4 + 1] = src[x * 4 + 1]
                    dst[x * 4 + 2] = src[x * 4 + 2]; dst[x * 4 + 3] = 255
                }
            } else {
                let m = item.mask!.p + ty * 64
                for x in 0..<64 {
                    let a = m[x]
                    guard a > 0, src[x * 4 + 3] != 0 else { continue }
                    let d = dst + x * 4, s = src + x * 4
                    if d[3] == 0 {
                        d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = 255
                    } else {
                        d[0] = H4MapTerrainRender.blend(dst: d[0], src: s[0], alpha: a)
                        d[1] = H4MapTerrainRender.blend(dst: d[1], src: s[1], alpha: a)
                        d[2] = H4MapTerrainRender.blend(dst: d[2], src: s[2], alpha: a)
                    }
                }
            }
        }
    }

    /// k×k box average (integer floor) of `outRows * k` canvas rows into `outRows` output rows.
    private static func reduce(_ canvas: UnsafeMutablePointer<UInt8>, width W: Int, scale k: Int, outWidth: Int,
                               outRows: Int, into out: UnsafeMutablePointer<UInt8>) {
        if k == 1 {
            out.update(from: canvas, count: outWidth * outRows * 4)
            return
        }
        var acc = [UInt32](repeating: 0, count: outWidth * 4)
        let area = UInt32(k * k)
        for oy in 0..<outRows {
            for i in 0..<acc.count { acc[i] = 0 }
            for ky in 0..<k {
                let row = canvas + ((oy * k + ky) * W) * 4
                for ox in 0..<outWidth {
                    let px = row + ox * k * 4
                    var r: UInt32 = 0, g: UInt32 = 0, b: UInt32 = 0, a: UInt32 = 0
                    for kx in 0..<k {
                        r += UInt32(px[kx * 4]); g += UInt32(px[kx * 4 + 1])
                        b += UInt32(px[kx * 4 + 2]); a += UInt32(px[kx * 4 + 3])
                    }
                    acc[ox * 4] += r; acc[ox * 4 + 1] += g; acc[ox * 4 + 2] += b; acc[ox * 4 + 3] += a
                }
            }
            let dst = out + oy * outWidth * 4
            for i in 0..<acc.count { dst[i] = UInt8(acc[i] / area) }
        }
    }
}
