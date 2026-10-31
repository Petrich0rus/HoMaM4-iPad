import Foundation
import H4Kit
import Metal

/// GPU textures shared by all levels of a map: one 640×320 slice per terrain texture and a mask atlas.
final class TerrainAtlas: @unchecked Sendable {
    let textures: MTLTexture
    let masks: MTLTexture
    private let slices: [H4TextureKey: UInt16]
    private let maskSets: [String: Int]

    func slice(_ key: H4TextureKey) -> UInt16? { slices[key] }

    /// Origin of mask `index` of the named set in the mask atlas.
    func maskOrigin(set: String, index: Int) -> SIMD2<UInt16>? {
        guard let s = maskSets[set], (0..<H4TerrainLayout.maskCount).contains(index) else { return nil }
        return SIMD2(UInt16(index * 64), UInt16(s * 32))
    }

    /// Loads `keys` from the store. Heavy: call off the main thread.
    init(device: MTLDevice, store: H4ResourceStore, keys: Set<H4TextureKey>, progress: (Double) -> Void) throws {
        let ordered = keys.sorted { H4TerrainLayout.resourceName($0) < H4TerrainLayout.resourceName($1) }
        let size = H4TerrainLayout.atlasSize
        let td = MTLTextureDescriptor()
        td.textureType = .type2DArray
        td.pixelFormat = .rgba8Unorm
        td.width = size.x; td.height = size.y
        td.arrayLength = max(ordered.count, 1)
        td.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: td) else { throw H4Error.malformed("cannot allocate terrain texture array") }
        var map: [H4TextureKey: UInt16] = [:]
        var pixels = [UInt8](repeating: 0, count: size.x * size.y * 4)
        for (i, key) in ordered.enumerated() {
            map[key] = UInt16(i)
            let name = H4TerrainLayout.resourceName(key)
            do {
                let texture = try H4TerrainTexture(data: store.data(for: name))
                Self.compose(texture, into: &pixels, width: size.x)
            } catch {
                print("[H4] missing terrain texture \(name): \(error)")
                pixels = [UInt8](repeating: 0, count: pixels.count)
            }
            pixels.withUnsafeBytes {
                tex.replace(region: MTLRegionMake2D(0, 0, size.x, size.y), mipmapLevel: 0, slice: i,
                            withBytes: $0.baseAddress!, bytesPerRow: size.x * 4, bytesPerImage: pixels.count)
            }
            progress(Double(i + 1) / Double(ordered.count))
        }
        textures = tex
        slices = map

        let sets = try H4Transitions.parse(store.data(for: "transition.Transitions.h4d"))
        let width = H4TerrainLayout.maskCount * 64, height = sets.count * 32
        var mask = [UInt8](repeating: 0, count: width * height)
        for (s, set) in sets.enumerated() {
            for (m, item) in set.masks.prefix(H4TerrainLayout.maskCount).enumerated() {
                for y in 0..<32 { for x in 0..<64 { mask[(s * 32 + y) * width + m * 64 + x] = item.alpha[y * 64 + x] * 17 } }
            }
        }
        let md = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        md.usage = .shaderRead
        guard let maskTexture = device.makeTexture(descriptor: md) else { throw H4Error.malformed("cannot allocate mask atlas") }
        maskTexture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: mask, bytesPerRow: width)
        masks = maskTexture
        maskSets = Dictionary(sets.enumerated().map { ($1.name, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Lays the 100 tiles of a texture out on a 10×10 grid of 64×32 boxes (tile i at column i%10, row i/10).
    private static func compose(_ texture: H4TerrainTexture, into pixels: inout [UInt8], width: Int) {
        for i in pixels.indices { pixels[i] = 0 }
        for (index, tile) in texture.tiles.enumerated() {
            let ox = index % 10 * 64, oy = index / 10 * 32
            for (x, runs) in tile.columns.enumerated() {
                let top = (31 - H4TerrainTexture.columnHeight(x)) / 2
                for run in runs {
                    for (k, c) in run.indices.enumerated() {
                        let p = ((oy + top + run.start + k) * width + ox + x) * 4, ci = Int(c) * 3
                        pixels[p] = texture.palette[ci]; pixels[p + 1] = texture.palette[ci + 1]
                        pixels[p + 2] = texture.palette[ci + 2]; pixels[p + 3] = 255
                    }
                }
            }
        }
    }
}
