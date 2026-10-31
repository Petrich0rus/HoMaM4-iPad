import Foundation

/// An 8-bit RGBA image, rows top to bottom, straight (non-premultiplied) alpha.
public struct H4RGBAImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4)
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

/// One horizontal run of opaque-or-partly-opaque pixels in a layer row.
public struct H4Span: Sendable, Equatable {
    /// Columns `start..<end`, relative to the layer's left edge.
    public let start: Int
    public let end: Int
    /// Index of the run's first pixel in `H4Layer.indices`.
    public let offset: Int
}

/// A paletted, run-length-cropped picture (`t_paletted_layer` in heroes4.exe).
///
/// Format, from the game's reader at 0x595880:
///
///     u16 paletteCount, u16 hasCoverageMask
///     paletteCount × (B, G, R)
///     u16 + bytes  name
///     u8           kind (≥ 4: a 4-bit alpha mask follows the pixels)
///     i32 × 4      left, top, right, bottom
///     (bottom − top) × { u16 start, u16 end, u32 offset }   one span per row
///     pixelCount × u8 palette index
///     if kind ≥ 4: ⌈pixelCount / 2⌉ bytes of alpha nibbles (low nibble first, 0…15)
///     if kind ≥ 4 and hasCoverageMask: (pixelCount + 0x83) >> 7 bytes of a 2-bit-per-32-pixel
///                  summary the game can also recompute (0x590740); kept but not needed to draw
public struct H4Layer: Sendable, Equatable {
    public static let maxLayerSide = 4096

    /// Straight-alpha "over": source colour `src` with alpha `a` (1…254) onto `dst`
    /// (r, g, b, alpha). The destination weight is rounded once and used in both numerator and
    /// denominator, so each channel is a weighted mean of values ≤ 255 and cannot overflow.
    @inline(__always)
    static func blend(src: (UInt8, UInt8, UInt8), alpha a: Int, onto dst: inout (UInt8, UInt8, UInt8, UInt8)) {
        let dstWeight = Int(dst.3) * (255 - a) / 255
        let outA = a + dstWeight
        dst.0 = UInt8((Int(src.0) * a + Int(dst.0) * dstWeight) / outA)
        dst.1 = UInt8((Int(src.1) * a + Int(dst.1) * dstWeight) / outA)
        dst.2 = UInt8((Int(src.2) * a + Int(dst.2) * dstWeight) / outA)
        dst.3 = UInt8(outA)
    }

    public let name: String
    public let kind: UInt8
    public let left: Int, top: Int, right: Int, bottom: Int
    /// Palette as RGB triples.
    public let palette: [UInt8]
    public let spans: [H4Span]
    public let indices: Data
    /// 4-bit alpha, one nibble per pixel, or nil when the layer is fully opaque.
    public let alpha: Data?

    public var width: Int { right - left }
    public var height: Int { bottom - top }
    public var isEmpty: Bool { height <= 0 || width <= 0 }

    /// Alpha (0…255) of pixel `i` of `indices`.
    @inline(__always) func alphaValue(_ i: Int) -> UInt8 {
        guard let alpha else { return 255 }
        let byte = alpha[alpha.startIndex + (i >> 1)]
        return ((byte >> (UInt8(i & 1) * 4)) & 0x0F) &* 17
    }

    /// The layer on its own canvas of `width × height`.
    public func rgba() -> H4RGBAImage {
        var out = H4RGBAImage(width: max(width, 0), height: max(height, 0),
                              pixels: [UInt8](repeating: 0, count: max(width, 0) * max(height, 0) * 4))
        draw(into: &out, originX: -left, originY: -top)
        return out
    }

    /// Alpha-blends the layer onto `canvas`, with the layer's (left, top) placed at
    /// (left + originX, top + originY). Pixels outside the canvas are clipped.
    public func draw(into canvas: inout H4RGBAImage, originX: Int = 0, originY: Int = 0) {
        guard !isEmpty else { return }
        let base = indices.startIndex
        for (row, span) in spans.enumerated() {
            let y = top + originY + row
            guard y >= 0, y < canvas.height else { continue }
            for column in span.start..<span.end {
                let x = left + originX + column
                guard x >= 0, x < canvas.width else { continue }
                let i = span.offset + column - span.start
                let a = Int(alphaValue(i))
                guard a > 0 else { continue }
                let c = Int(indices[base + i]) * 3
                let p = (y * canvas.width + x) * 4
                if a == 255 {
                    canvas.pixels[p] = palette[c]
                    canvas.pixels[p + 1] = palette[c + 1]
                    canvas.pixels[p + 2] = palette[c + 2]
                    canvas.pixels[p + 3] = 255
                } else {
                    var d = (canvas.pixels[p], canvas.pixels[p + 1], canvas.pixels[p + 2], canvas.pixels[p + 3])
                    Self.blend(src: (palette[c], palette[c + 1], palette[c + 2]), alpha: a, onto: &d)
                    (canvas.pixels[p], canvas.pixels[p + 1], canvas.pixels[p + 2], canvas.pixels[p + 3]) = d
                }
            }
        }
    }

    static func read(_ r: inout ByteReader) throws -> H4Layer {
        let paletteCount = Int(try r.u16())
        let hasCoverage = try r.u16() != 0
        let bgr = try r.bytes(paletteCount * 3)
        var palette = [UInt8](repeating: 0, count: 256 * 3) // indices beyond the palette stay black
        for i in 0..<paletteCount where i < 256 {
            let o = bgr.startIndex + i * 3
            palette[i * 3] = bgr[o + 2]
            palette[i * 3 + 1] = bgr[o + 1]
            palette[i * 3 + 2] = bgr[o]
        }
        let name = try r.string16()
        let kind = try r.u8()
        let left = Int(try r.i32()), top = Int(try r.i32()), right = Int(try r.i32()), bottom = Int(try r.i32())
        let height = bottom - top, width = right - left
        // The game's largest layer is 1280×1024. The cap bounds what `rgba()` may allocate
        // (64 MiB) for a forged rectangle that has almost no pixel data behind it.
        guard height <= maxLayerSide, width <= maxLayerSide else {
            throw H4Error.malformed("layer '\(name)' is \(width)×\(height)")
        }

        var spans: [H4Span] = []
        var pixelCount = 0
        if height > 0 {
            guard height * 8 <= r.remaining else { throw H4Error.truncated(at: r.offset, needed: height * 8) }
            spans.reserveCapacity(height)
            for _ in 0..<height {
                let start = Int(try r.u16()), end = Int(try r.u16()), offset = Int(try r.u32())
                guard start <= end, end <= max(width, 0) else {
                    throw H4Error.malformed("layer '\(name)': span \(start)..<\(end) outside width \(width)")
                }
                spans.append(H4Span(start: start, end: end, offset: offset))
            }
            let last = spans[spans.count - 1]
            pixelCount = last.end + last.offset - last.start
            for s in spans where s.offset + (s.end - s.start) > pixelCount {
                throw H4Error.malformed("layer '\(name)': span past pixel data")
            }
        }
        let indices = try r.bytes(pixelCount)
        for byte in indices where Int(byte) >= max(paletteCount, 1) && paletteCount < 256 {
            throw H4Error.malformed("layer '\(name)': color \(byte) outside a \(paletteCount)-color palette")
        }
        var alpha: Data? = nil
        if kind >= 4, height > 0 {
            alpha = try r.bytes((pixelCount + 1) / 2)
            if hasCoverage { _ = try r.bytes((pixelCount + 0x83) >> 7) }
        }
        return H4Layer(name: name, kind: kind, left: left, top: top, right: right, bottom: bottom,
                       palette: palette, spans: spans, indices: indices, alpha: alpha)
    }
}

/// A named set of layers sharing one coordinate space (`t_bitmap_group`, reader 0x58e2e0).
/// Used directly by `layers.*` resources (UI screens, buttons, cursors), and as the frame list
/// of animations and actor sequences.
public struct H4LayerGroup: Sendable, Equatable {
    /// In file order. (The game sorts them by name after loading.)
    public let layers: [H4Layer]

    public func layer(named name: String) -> H4Layer? {
        layers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Union of all non-empty layer rectangles: (left, top, right, bottom).
    public var bounds: (left: Int, top: Int, right: Int, bottom: Int)? {
        let visible = layers.filter { !$0.isEmpty }
        guard let first = visible.first else { return nil }
        return visible.dropFirst().reduce((first.left, first.top, first.right, first.bottom)) {
            (min($0.0, $1.left), min($0.1, $1.top), max($0.2, $1.right), max($0.3, $1.bottom))
        }
    }

    public init(data: Data) throws {
        var r = ByteReader(data)
        self = try Self.read(&r)
        guard r.remaining == 0 else { throw H4Error.malformed("\(r.remaining) trailing bytes after layer group") }
    }

    init(layers: [H4Layer]) { self.layers = layers }

    static func read(_ r: inout ByteReader) throws -> H4LayerGroup {
        let count = Int(try r.u16())
        var layers: [H4Layer] = []
        layers.reserveCapacity(count)
        for _ in 0..<count { layers.append(try H4Layer.read(&r)) }
        return H4LayerGroup(layers: layers)
    }
}

/// Timed frame animation (`animation.*`, `t_animation`): spell effects, town buildings, flags.
public struct H4Animation: Sendable, Equatable {
    public let frames: H4LayerGroup
    public let version: UInt16
    public let frameDurationMilliseconds: Int
    /// Playback order as indices into `frames.layers`.
    public let frameOrder: [Int]
    /// Version-2 extra block: two flag bytes and a point, meaning not yet identified.
    public let extra: (flags: [UInt8], x: Int32, y: Int32)?

    public static func == (a: H4Animation, b: H4Animation) -> Bool {
        a.frames == b.frames && a.version == b.version && a.frameDurationMilliseconds == b.frameDurationMilliseconds
            && a.frameOrder == b.frameOrder && a.extra?.flags == b.extra?.flags && a.extra?.x == b.extra?.x
            && a.extra?.y == b.extra?.y
    }

    public init(data: Data) throws {
        var r = ByteReader(data)
        frames = try H4LayerGroup.read(&r)
        version = try r.u16()
        frameDurationMilliseconds = Int(try r.u16())
        let count = Int(try r.u32())
        guard count <= r.remaining / 4 else { throw H4Error.truncated(at: r.offset, needed: count * 4) }
        var order: [Int] = []
        for _ in 0..<count {
            let index = Int(try r.u32())
            guard index < frames.layers.count else { throw H4Error.malformed("animation frame \(index) out of range") }
            order.append(index)
        }
        frameOrder = order
        if version >= 2 {
            let flags = [try r.u8(), try r.u8()]
            extra = (flags, try r.i32(), try r.i32())
        } else {
            extra = nil
        }
        guard r.remaining == 0 else { throw H4Error.malformed("\(r.remaining) trailing bytes after animation") }
    }
}

/// One direction of a creature or hero action (`actor_sequence.<actor>.<action>.<dir>`).
public struct H4ActorSequence: Sendable, Equatable {
    public let version: UInt16
    /// 2 or 3; kind 3 carries an extra (u16, i32) header pair of unknown meaning.
    public let kind: UInt16
    public let frames: H4LayerGroup
    /// Anchor point of the sprite (e.g. −361, −347 for most actors).
    public let originX: Int32
    public let originY: Int32
    /// Remaining metadata (links to combat_actor resources, events…), not decoded yet.
    public let trailer: Data

    public init(data: Data) throws {
        var r = ByteReader(data)
        version = try r.u16()
        kind = try r.u16()
        switch kind {
        case 2: break
        case 3: _ = try r.u16(); _ = try r.i32()
        default: throw H4Error.malformed("unknown actor sequence kind \(kind)")
        }
        frames = try H4LayerGroup.read(&r)
        originX = try r.i32()
        originY = try r.i32()
        trailer = Data(try r.bytes(r.remaining))
    }
}

/// Full-screen 24-bit picture (`bitmap_raw.*`, e.g. the main menu backgrounds).
public struct H4RawBitmap: Sendable {
    public let image: H4RGBAImage

    public init(data: Data) throws {
        var r = ByteReader(data)
        let version = try r.u32()
        let height = Int(try r.u32()), width = Int(try r.u32()), size = Int(try r.u32())
        guard version == 1, width > 0, height > 0, width <= 8192, height <= 8192, size == width * height * 3 else {
            throw H4Error.malformed("raw bitmap header v\(version) \(width)×\(height) size \(size)")
        }
        let bgr = try r.bytes(size)
        guard r.remaining == 0 else { throw H4Error.malformed("\(r.remaining) trailing bytes after raw bitmap") }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var src = bgr.startIndex
        for p in stride(from: 0, to: pixels.count, by: 4) {
            pixels[p] = bgr[src + 2]
            pixels[p + 1] = bgr[src + 1]
            pixels[p + 2] = bgr[src]
            src += 3
        }
        image = H4RGBAImage(width: width, height: height, pixels: pixels)
    }
}
