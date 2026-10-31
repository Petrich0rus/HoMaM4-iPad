import Dispatch
import Foundation

/// CPU compositor for the terrain of a map region (rules R4–R7 of `H4MapTerrainRender`).
///
/// Holds caches of decoded textures, tiles and masks, so one instance should render many maps.
/// Resources that cannot be found are recorded in `missingTextures` / `missingMasks` (the affected
/// draw items are skipped) instead of aborting the render.
///
/// Thread safety (slice 6b): every access to the caches and the missing lists goes through one `NSLock`
/// (resolving a draw list is one locked step), so any number of threads may render on one instance;
/// compositing itself runs without the lock, in parallel bands.
public final class H4TerrainCompositor: @unchecked Sendable {
    /// Bytes of a 64×32 RGBA tile or mask grid, owned manually so bands can read it from several threads.
    final class Pixels: @unchecked Sendable {
        let p: UnsafeMutablePointer<UInt8>
        init(_ bytes: [UInt8]) { p = .allocate(capacity: bytes.count); p.initialize(from: bytes, count: bytes.count) }
        deinit { p.deallocate() }
    }
    private struct TileKey: Hashable { var texture: H4TerrainTextureRef; var index: Int }
    fileprivate struct Resolved { var x: Int, y: Int; var tile: Pixels; var mask: Pixels? }

    private let loader: @Sendable (String) throws -> Data
    private let transitions: H4TransitionLibrary
    private var textures: [H4TerrainTextureRef: H4TerrainTexture?] = [:]
    private var tiles: [TileKey: Pixels] = [:]
    private var masks: [H4MaskRef: Pixels?] = [:]
    private let lock = NSLock()
    private var missingTexturesStore: Set<String> = []
    private var missingMasksStore: Set<String> = []
    public var missingTextures: Set<String> { lock.lock(); defer { lock.unlock() }; return missingTexturesStore }
    public var missingMasks: Set<String> { lock.lock(); defer { lock.unlock() }; return missingMasksStore }

    public init(transitions: H4TransitionLibrary, loader: @escaping @Sendable (String) throws -> Data) {
        self.transitions = transitions
        self.loader = loader
    }

    public convenience init(store: H4ResourceStore) throws {
        try self.init(transitions: H4TransitionLibrary(data: store.data(for: "transition.Transitions.h4d")),
                      loader: { try store.data(for: $0) })
    }

    // MARK: resolving (under `lock`)

    func tile(_ item: H4TerrainDrawItem) throws -> Pixels? {
        lock.lock(); defer { lock.unlock() }
        return try tileLocked(item)
    }

    private func tileLocked(_ item: H4TerrainDrawItem) throws -> Pixels? {
        let key = TileKey(texture: item.texture, index: item.tileIndex)
        if let hit = tiles[key] { return hit }
        let texture: H4TerrainTexture?
        let name = item.texture.resourceName
        if let cached = textures[item.texture] {
            texture = cached
        } else {
            do {
                texture = try H4TerrainTexture(data: loader(name))
            } catch H4Error.notFound {
                missingTexturesStore.insert(name)
                texture = nil
            }
            textures[item.texture] = .some(texture)
        }
        guard let texture else { return nil }
        guard texture.tiles.indices.contains(item.tileIndex) else {
            missingTexturesStore.insert("\(name) tile \(item.tileIndex)")
            return nil
        }
        let made = Pixels(texture.image(ofTile: item.tileIndex).pixels)
        tiles[key] = made
        return made
    }

    private func maskLocked(_ ref: H4MaskRef) -> Pixels? {
        if let cached = masks[ref] { return cached }
        var made: Pixels?
        if let set = ref.set, let m = transitions.mask(set: H4MapTerrainRender.maskSetNames[set], index: ref.index) {
            made = Pixels(m.storage.map { a in
                a == H4TransitionLibrary.outside ? 0 : (ref.inverted ? 15 - a : a)
            })
        } else {
            missingMasksStore.insert("\(ref.set.map { H4MapTerrainRender.maskSetNames[$0] } ?? "unknown set") #\(ref.index)")
        }
        masks[ref] = .some(made)
        return made
    }

    private func resolve(_ items: [H4TerrainDrawItem]) throws -> [Resolved] {
        lock.lock(); defer { lock.unlock() }
        var out: [Resolved] = []
        out.reserveCapacity(items.count)
        for item in items {
            var maskPixels: Pixels?
            if let ref = item.mask {
                guard let m = maskLocked(ref) else { continue }
                maskPixels = m
            }
            guard let tile = try tileLocked(item) else { continue }
            out.append(Resolved(x: item.x, y: item.y, tile: tile, mask: maskPixels))
        }
        return out
    }

    // MARK: compositing

    /// A rectangle of pixels of the scale-`k` image of a region (origin top-left, y down).
    /// Pixels of the rectangle outside the canvas stay transparent.
    public struct PixelRect: Sendable, Equatable {
        public var x: Int, y: Int, width: Int, height: Int
        public init(x: Int, y: Int, width: Int, height: Int) { self.x = x; self.y = y; self.width = width; self.height = height }
    }

    /// The resolved draw passes of one (terrain, level, region): built once (`prepare`), then used for any number of
    /// `render(plan:…)` calls from any thread. The textures and masks stay alive as long as the plan does.
    public final class Plan: @unchecked Sendable {
        public let region: H4MapTerrainRender.Region
        public let level: Int
        fileprivate let passes: [[Resolved]]
        fileprivate init(region: H4MapTerrainRender.Region, level: Int, passes: [[Resolved]]) {
            self.region = region; self.level = level; self.passes = passes
        }
    }

    public func prepare(terrain: H4ScenarioTerrain, level: Int, region: H4MapTerrainRender.Region) throws -> Plan {
        guard (0..<terrain.levels).contains(level) else { throw H4Error.malformed("level \(level) outside 0..<\(terrain.levels)") }
        guard region.rows >= 1, region.columns >= 1 else { throw H4Error.malformed("empty region") }
        let list = H4MapTerrainRender.drawList(terrain: terrain, level: level, region: region)
        return Plan(region: region, level: level, passes: [try resolve(list.bases), try resolve(list.overlays), try resolve(list.roads)])
    }

    /// Renders `region` of `level`: the scale-1 canvas (R6/R7) reduced by a `scale`×`scale` box average of the
    /// four channels (integer floor); the image is floor(W/scale) × floor(H/scale). `objects` (slice 6a-O) are drawn
    /// over the terrain of each band, in list order, before the reduction.
    public func render(terrain: H4ScenarioTerrain, level: Int, region: H4MapTerrainRender.Region,
                       scale k: Int = 1, objects: H4ObjectDrawList? = nil) throws -> H4RGBAImage {
        guard k >= 1 else { throw H4Error.malformed("empty region or scale") }
        guard region.rows >= 1, region.columns >= 1 else { throw H4Error.malformed("empty region or scale") }
        let outW = region.canvasWidth / k, outH = region.canvasHeight / k
        guard outW > 0, outH > 0 else { throw H4Error.malformed("region too small for scale \(k)") }
        return try render(terrain: terrain, level: level, region: region,
                          pixelRect: PixelRect(x: 0, y: 0, width: outW, height: outH), scale: k, objects: objects)
    }

    /// Renders the pixel rectangle `pixelRect` of the scale-`k` image of `region` (the image `render(…scale:)` returns):
    /// the same pixels, so the mosaic of any tiling of that image equals the whole render.
    public func render(terrain: H4ScenarioTerrain, level: Int, region: H4MapTerrainRender.Region, pixelRect: PixelRect,
                       scale k: Int = 1, objects: H4ObjectDrawList? = nil) throws -> H4RGBAImage {
        try render(plan: prepare(terrain: terrain, level: level, region: region), pixelRect: pixelRect, scale: k, objects: objects)
    }

    public func render(plan: Plan, pixelRect r: PixelRect, scale k: Int = 1, objects: H4ObjectDrawList? = nil) throws -> H4RGBAImage {
        guard k >= 1, r.width > 0, r.height > 0 else { throw H4Error.malformed("empty pixel rectangle or scale") }
        let outW = r.width, outH = r.height
        let cx0 = r.x * k, cy0 = r.y * k, cw = outW * k

        // Items of each pass are sorted by y, so the ones touching a band of canvas rows form a contiguous range.
        @Sendable func range(_ items: [Resolved], _ y0: Int, _ y1: Int) -> Range<Int> {
            func lowerBound(_ v: Int) -> Int {          // first item with y >= v
                var lo = 0, hi = items.count
                while lo < hi { let mid = (lo + hi) / 2; if items[mid].y < v { lo = mid + 1 } else { hi = mid } }
                return lo
            }
            return lowerBound(y0 - 31)..<lowerBound(y1)
        }

        let passes = plan.passes
        var out = [UInt8](repeating: 0, count: outW * outH * 4)
        let bandRows = max(1, 128 / k)                  // output rows per band
        let bands = (outH + bandRows - 1) / bandRows
        out.withUnsafeMutableBufferPointer { outBuffer in
            let dest = SendablePointer(p: outBuffer.baseAddress!)
            DispatchQueue.concurrentPerform(iterations: bands) { band in
                let o0 = band * bandRows, o1 = min(outH, o0 + bandRows)
                let y0 = cy0 + o0 * k, bh = (o1 - o0) * k
                let canvas = UnsafeMutablePointer<UInt8>.allocate(capacity: cw * bh * 4)
                canvas.initialize(repeating: 0, count: cw * bh * 4)
                defer { canvas.deallocate() }
                for (n, items) in passes.enumerated() {
                    for i in range(items, y0, y0 + bh) where items[i].x < cx0 + cw && items[i].x + 64 > cx0 {
                        Self.draw(items[i], base: n == 0, canvas: canvas, width: cw, x0: cx0, y0: y0, rows: bh)
                    }
                }
                if let objects {
                    for item in objects.items where item.top < y0 + bh && item.top + item.pixels.height > y0
                        && item.left < cx0 + cw && item.left + item.pixels.width > cx0 {
                        H4MapObjectRender.draw(item, canvas: canvas, width: cw, x0: cx0, y0: y0, rows: bh)
                    }
                }
                Self.reduce(canvas, width: cw, scale: k, outWidth: outW, outRows: o1 - o0,
                            into: dest.p + o0 * outW * 4)
            }
        }
        return H4RGBAImage(width: outW, height: outH, pixels: out)
    }

    private struct SendablePointer: @unchecked Sendable { let p: UnsafeMutablePointer<UInt8> }

    /// Draws `item` into `canvas` (RGBA, `width` wide) holding canvas columns x0 ..< x0 + width of rows y0 ..< y0 + rows.
    private static func draw(_ item: Resolved, base: Bool, canvas: UnsafeMutablePointer<UInt8>,
                             width W: Int, x0: Int, y0: Int, rows: Int) {
        let tile = item.tile.p
        let xs = max(0, x0 - item.x), xe = min(64, x0 + W - item.x)
        guard xs < xe else { return }
        for ty in 0..<32 {
            let by = item.y + ty - y0
            guard by >= 0, by < rows else { continue }
            let dst = canvas + (by * W + item.x - x0) * 4
            let src = tile + ty * 64 * 4
            if base {
                for x in xs..<xe where src[x * 4 + 3] != 0 {
                    dst[x * 4] = src[x * 4]; dst[x * 4 + 1] = src[x * 4 + 1]
                    dst[x * 4 + 2] = src[x * 4 + 2]; dst[x * 4 + 3] = 255
                }
            } else {
                let m = item.mask!.p + ty * 64
                for x in xs..<xe {
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
