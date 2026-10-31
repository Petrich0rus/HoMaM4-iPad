import Foundation

// Formats of slice 3, reconstructed with REA/Ghidra from heroes4.exe and validated on every
// file shipped with HoMM4 Complete (GOG): 21 fonts, 61 terrain textures, 2,798 adventure-map
// objects and 1,048 combat objects, all consumed to the exact byte.

// MARK: - Fonts

/// Bitmap font (`font.*`, reader `t_font` at 0x71bee0, glyphs at 0x71baa0).
///
///     u16 version (< 256), u8 firstCharacter, u8 height, u8 lineSpacing, u8 baseline, u8 count
///     count × glyph { i32 width, i32 height, i32 leftSpacing, i32 rightSpacing, width×height bytes }
///
/// Each glyph byte holds two 4-bit coverages: high nibble = the letter, low nibble = its
/// drop shadow (shifted one pixel down-right). The names of the three size bytes and the two
/// spacing fields are inferred from the data (the space glyph is 1 px wide with 7 px after it;
/// "f" has −1 so the next letter tucks under it).
public struct H4Font: Sendable {
    public struct Glyph: Sendable, Equatable {
        public let width: Int, height: Int, leftSpacing: Int, rightSpacing: Int
        /// Horizontal pen advance for this character.
        public var advance: Int { leftSpacing + width + rightSpacing }
        /// width × height bytes, high nibble letter coverage, low nibble shadow coverage.
        public let pixels: Data
    }

    public let version: UInt16
    public let firstCharacter: UInt8
    public let height: Int
    public let lineSpacing: Int
    public let baseline: Int
    public let glyphs: [Glyph]

    /// Glyph for a Windows-1252 code point, if the font has it.
    public func glyph(for code: UInt8) -> Glyph? {
        guard code >= firstCharacter else { return nil }
        let i = Int(code - firstCharacter)
        return i < glyphs.count ? glyphs[i] : nil
    }

    public init(data: Data) throws {
        var r = ByteReader(data)
        version = try r.u16()
        guard version < 256 else { throw H4Error.malformed("legacy font header (version \(version)) not supported") }
        firstCharacter = try r.u8()
        height = Int(try r.u8())
        lineSpacing = Int(try r.u8())
        baseline = Int(try r.u8())
        let count = Int(try r.u8())
        var list: [Glyph] = []
        for _ in 0..<count {
            let w = Int(try r.i32()), h = Int(try r.i32()), x = Int(try r.i32()), y = Int(try r.i32())
            guard (0...256).contains(w), (0...256).contains(h) else {
                throw H4Error.malformed("glyph of \(w)×\(h)")
            }
            // Shipped fonts use −3…7. The bound keeps render(text:) allocations proportional
            // to the text, whatever a modified font file says.
            guard (-256...256).contains(x), (-256...256).contains(y) else {
                throw H4Error.malformed("glyph spacing \(x), \(y)")
            }
            var pixels = try r.bytes(w * h)
            if version == 0 {
                // Version-0 fonts store 1 for shadow and 2 for letter (remapped by the game at 0x71bc0d).
                pixels = Data(pixels.map { $0 == 1 ? 0x0F : $0 == 2 ? 0xF0 : $0 })
            }
            list.append(Glyph(width: w, height: h, leftSpacing: x, rightSpacing: y, pixels: pixels))
        }
        glyphs = list
        guard r.remaining == 0 else { throw H4Error.malformed("\(r.remaining) trailing bytes after font") }
    }

    /// Widest line `render(text:)` produces; longer text is cut.
    public static let maxRenderWidth = 8192

    /// Renders `text` (Windows-1252) on one line in `color`, with the game's drop shadow.
    /// Spacing follows the game's text code (0x71bd50 / 0x71bde0): the first character's
    /// leading space and the last one's trailing space are not applied, and characters the
    /// font lacks are drawn with its first glyph.
    public func render(text: String, color: (UInt8, UInt8, UInt8) = (255, 255, 255)) -> H4RGBAImage {
        let codes = [UInt8](text.data(using: .windowsCP1252, allowLossyConversion: true) ?? Data())
        let glyphsToDraw = codes.compactMap { glyph(for: $0) ?? glyphs.first }
        // Pen position before each glyph, and total width, stopping at maxRenderWidth.
        var positions: [Int] = []
        var pen = 0, width = 0
        for (i, g) in glyphsToDraw.enumerated() {
            let x = pen + (i == 0 ? 0 : g.leftSpacing)
            guard x + g.width <= Self.maxRenderWidth else { break }
            positions.append(x)
            width = max(width, x + g.width)
            pen = x + g.width + g.rightSpacing
        }
        width = max(width, 1)
        var canvas = H4RGBAImage(width: width, height: max(height, 1),
                                 pixels: [UInt8](repeating: 0, count: width * max(height, 1) * 4))
        for (g, origin) in zip(glyphsToDraw, positions) {
            let img = render(g, color: color)
            for y in 0..<min(g.height, canvas.height) {
                for x in 0..<g.width {
                    let cx = origin + x
                    guard cx >= 0, cx < canvas.width else { continue }
                    let s = (y * g.width + x) * 4, d = (y * canvas.width + cx) * 4
                    let a = Int(img.pixels[s + 3])
                    guard a > 0 else { continue }
                    var dst = (canvas.pixels[d], canvas.pixels[d + 1], canvas.pixels[d + 2], canvas.pixels[d + 3])
                    if a == 255 {
                        dst = (img.pixels[s], img.pixels[s + 1], img.pixels[s + 2], 255)
                    } else {
                        H4Layer.blend(src: (img.pixels[s], img.pixels[s + 1], img.pixels[s + 2]), alpha: a, onto: &dst)
                    }
                    (canvas.pixels[d], canvas.pixels[d + 1], canvas.pixels[d + 2], canvas.pixels[d + 3]) = dst
                }
            }
        }
        return canvas
    }

    /// Renders a glyph in `color` with a black drop shadow.
    public func render(_ glyph: Glyph, color: (UInt8, UInt8, UInt8) = (255, 255, 255)) -> H4RGBAImage {
        var img = H4RGBAImage(width: glyph.width, height: glyph.height,
                              pixels: [UInt8](repeating: 0, count: glyph.width * glyph.height * 4))
        for i in 0..<(glyph.width * glyph.height) {
            let v = glyph.pixels[glyph.pixels.startIndex + i]
            let letter = Int(v >> 4) * 17, shadow = Int(v & 0x0F) * 17
            var d: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
            if shadow > 0 { d = (0, 0, 0, UInt8(shadow)) }
            if letter == 255 {
                d = (color.0, color.1, color.2, 255)
            } else if letter > 0 {
                H4Layer.blend(src: color, alpha: letter, onto: &d)
            }
            (img.pixels[i * 4], img.pixels[i * 4 + 1], img.pixels[i * 4 + 2], img.pixels[i * 4 + 3]) = d
        }
        return img
    }
}

// MARK: - Terrain

/// Terrain texture (`terrain.<type>.<n>`, `t_metatile_texture`, reader 0x797260).
///
///     100 × tile { u32 n, n bytes of row data, 64 × u32 row offsets }
///     u32 paletteCount (256), paletteCount × BGR
///
/// A tile is a 64×32 isometric diamond stored column by column: "row" k of the file is
/// screen column k, whose height is 1, 1, 3, 3 … 31, 31, 31, 31 … 1, 1 pixels, vertically
/// centred. Each column is a sequence of runs { u8 gap, u8 count, count palette indices },
/// optionally ending with a final gap; a column with nothing drawn is a single gap byte.
public struct H4TerrainTexture: Sendable {
    public static let tileWidth = 64, tileHeight = 32, tileCount = 100

    public struct Tile: Sendable {
        /// Per column: runs of (y offset within the column, palette indices).
        public let columns: [[(start: Int, indices: Data)]]
    }

    public let tiles: [Tile]
    /// RGB triples, 256 entries.
    public let palette: [UInt8]

    /// Height of diamond column `k` (0…63).
    public static func columnHeight(_ k: Int) -> Int {
        k < 32 ? 2 * (k / 2) + 1 : 2 * ((63 - k) / 2) + 1
    }

    public init(data: Data) throws {
        var r = ByteReader(data)
        var list: [Tile] = []
        for _ in 0..<Self.tileCount {
            let n = Int(try r.u32())
            let body = try r.bytes(n)
            var offsets: [Int] = []
            for _ in 0..<64 { offsets.append(Int(try r.u32())) }
            var columns: [[(start: Int, indices: Data)]] = []
            for k in 0..<64 {
                let start = offsets[k], end = k < 63 ? offsets[k + 1] : n
                guard start <= end, end <= n else { throw H4Error.malformed("terrain column \(k) offsets \(start)…\(end)") }
                columns.append(try Self.decodeColumn(body[(body.startIndex + start)..<(body.startIndex + end)],
                                                     height: Self.columnHeight(k)))
            }
            list.append(Tile(columns: columns))
        }
        tiles = list
        let paletteCount = Int(try r.u32())
        guard paletteCount <= 256 else { throw H4Error.malformed("terrain palette of \(paletteCount) colours") }
        let bgr = try r.bytes(paletteCount * 3)
        var rgb = [UInt8](repeating: 0, count: 256 * 3)
        for i in 0..<paletteCount {
            let o = bgr.startIndex + i * 3
            (rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2]) = (bgr[o + 2], bgr[o + 1], bgr[o])
        }
        palette = rgb
        guard r.remaining == 0 else { throw H4Error.malformed("\(r.remaining) trailing bytes after terrain") }
    }

    static func decodeColumn(_ bytes: Data, height: Int) throws -> [(start: Int, indices: Data)] {
        var runs: [(start: Int, indices: Data)] = []
        var i = bytes.startIndex, y = 0
        while i < bytes.endIndex {
            y += Int(bytes[i]); i += 1
            guard i < bytes.endIndex else { break }      // trailing gap
            let count = Int(bytes[i]); i += 1
            guard count <= bytes.endIndex - i else { throw H4Error.malformed("terrain run past column data") }
            runs.append((y, bytes[i..<(i + count)]))
            i += count; y += count
        }
        guard y == height else { throw H4Error.malformed("terrain column covers \(y) of \(height) pixels") }
        return runs
    }

    /// One tile as a 64×32 image (transparent outside the diamond and in gaps).
    public func image(ofTile index: Int) -> H4RGBAImage {
        precondition(tiles.indices.contains(index), "terrain tile \(index) outside 0..<\(tiles.count)")
        var img = H4RGBAImage(width: Self.tileWidth, height: Self.tileHeight,
                              pixels: [UInt8](repeating: 0, count: Self.tileWidth * Self.tileHeight * 4))
        for (x, runs) in tiles[index].columns.enumerated() {
            let top = (31 - Self.columnHeight(x)) / 2
            for run in runs {
                for (k, c) in run.indices.enumerated() {
                    let p = ((top + run.start + k) * Self.tileWidth + x) * 4
                    let ci = Int(c) * 3
                    (img.pixels[p], img.pixels[p + 1], img.pixels[p + 2], img.pixels[p + 3]) =
                        (palette[ci], palette[ci + 1], palette[ci + 2], 255)
                }
            }
        }
        return img
    }
}

// MARK: - Shared object image block

/// Animated sprite used by map and combat objects (reader 0x749b20 / 0x749c80):
///
///     u16 version; if version > 2: u16 × 3 (meaning not identified)
///     layer group (frames)
///     i32 originX, i32 originY
///     if version == 1: u16-prefixed name
public struct H4ObjectSprite: Sendable, Equatable {
    public let version: UInt16
    public let extra: [UInt16]
    public let frames: H4LayerGroup
    public let originX: Int32
    public let originY: Int32
    public let name: String?

    /// Sprite header u16 #1 (reader 0x749b20 -> +0x4c): 1 = no base layers, 2 = base layers present.
    /// nil when the sprite version is below 3 (no header).
    public var mode: UInt16? { extra.count == 3 ? extra[0] : nil }
    /// Header u16 #2 (+0x4e): index of the `base_frame` layer in `frames.layers`; nil if absent (65535) or no header.
    public var baseFrameIndex: Int? { extra.count == 3 && extra[1] != 0xFFFF ? Int(extra[1]) : nil }
    /// Header u16 #3 (+0x50): index of the `base_shadow` layer in `frames.layers`; nil if absent (65535) or no header.
    public var baseShadowIndex: Int? { extra.count == 3 && extra[2] != 0xFFFF ? Int(extra[2]) : nil }

    static func read(_ r: inout ByteReader, version: UInt16) throws -> H4ObjectSprite {
        var extra: [UInt16] = []
        if version > 2 { extra = [try r.u16(), try r.u16(), try r.u16()] }
        let frames = try H4LayerGroup.read(&r)
        let x = try r.i32(), y = try r.i32()
        let name = version == 1 ? try r.string16() : nil
        return H4ObjectSprite(version: version, extra: extra, frames: frames, originX: x, originY: y, name: name)
    }
}

// MARK: - Adventure-map objects

/// Adventure-map object model (`adv_object.*`, `t_adv_object_model`, reader 0x44d860).
public struct H4AdventureObject: Sendable {
    public let version: UInt16
    public let objectType: UInt8
    /// Footprint in map tiles.
    public let width: Int
    public let height: Int
    /// One flag per footprint cell (row-major): cells the object occupies/blocks.
    public let blockedCells: [Bool]
    /// Entrance edges (edge flag 1 only, else nil): `edgesHorizontal` has (height + 1) × width bits, index j × width + i;
    /// `edgesVertical` has (width + 1) × height bits, index i × height + j. Only the boundary lines are used by movement.
    public let edgesHorizontal: [Bool]?
    public let edgesVertical: [Bool]?
    /// Classification triple (id, name), e.g. (80, "sphinx"); empty names when unused.
    public let classification: [(id: UInt16, name: String)]
    /// Draw-layer byte (version >= 4): 0 small items, 1 normal, 2 bridges and fields (ground objects).
    /// Versions below 4 do not store it; 1 is reported then [I], as the reference renderer does.
    public let drawLayer: UInt8
    /// Owner-flag attach point (version >= 5, present only on ownable models): offset from the object anchor.
    public let flagAttachPoint: (dx: Int32, dy: Int32)?
    public let imageKind: UInt8
    public let sprite: H4ObjectSprite
    /// Kind-0 images only: one depth value per 32-pixel column (draw ordering).
    public let columnDepths: [Int16]

    public init(data: Data) throws {
        var r = ByteReader(data)
        version = try r.u16()
        // Version 0 uses a different image reader in the game (0x7cdc20 / 0x8c98e0) that no
        // shipped file needs; the game data has versions 3–6.
        guard (1...6).contains(version) else { throw H4Error.malformed("adventure object version \(version)") }
        objectType = try r.u8()
        let edgeFlag = version >= 3 ? try r.u16() : 0
        guard edgeFlag <= 1 else { throw H4Error.malformed("adventure object edge flag \(edgeFlag)") }
        width = Int(try r.u16())
        height = Int(try r.u16())
        guard width <= 64, height <= 64 else { throw H4Error.malformed("adventure object \(width)×\(height) tiles") }
        func bits(_ n: Int) throws -> [Bool] {
            let raw = try r.bytes((n + 7) / 8)
            return (0..<n).map { raw[raw.startIndex + $0 / 8] & (1 << ($0 % 8)) != 0 }
        }
        blockedCells = try bits(width * height)
        if edgeFlag < 1 {
            _ = try bits(width * height)
            edgesHorizontal = nil
            edgesVertical = nil
        } else {
            edgesHorizontal = try bits((height + 1) * width)
            edgesVertical = try bits((width + 1) * height)
        }
        if version > 5 {
            _ = try bits(2 * (height + 1) * width)
            _ = try bits(2 * (width + 1) * height)
            _ = try r.bytes((width + 1) * (height + 1))
        }
        var classes: [(id: UInt16, name: String)] = []
        if version > 1 {
            guard try r.u16() == 0 else { throw H4Error.malformed("adventure object classification version") }
            for _ in 0..<3 { classes.append((try r.u16(), try r.string16())) }
        }
        classification = classes
        var layer: UInt8 = 1
        if version >= 4 {
            layer = try r.u8()
            guard layer <= 2 else { throw H4Error.malformed("adventure object layer value") }
        }
        drawLayer = layer
        if version >= 5, try r.u8() != 0 {
            flagAttachPoint = (try r.i32(), try r.i32())
        } else {
            flagAttachPoint = nil
        }

        imageKind = try r.u8()
        guard imageKind <= 1 else { throw H4Error.malformed("adventure object image kind \(imageKind)") }
        let imageVersion = try r.u16()
        guard imageVersion < 3 else { throw H4Error.malformed("adventure object image version \(imageVersion)") }
        let spriteVersion = imageVersion == 0 ? 0 : try r.u16()
        let innerVersion = spriteVersion == 0 ? 0 : try r.u16()
        sprite = try H4ObjectSprite.read(&r, version: innerVersion)
        if imageKind == 0 {
            let n = Int(try r.u32())
            guard n <= r.remaining / 2 else { throw H4Error.truncated(at: r.offset, needed: n * 2) }
            var depths: [Int16] = []
            for _ in 0..<n { depths.append(Int16(bitPattern: try r.u16())) }
            columnDepths = depths
        } else {
            columnDepths = []
        }
        guard r.remaining == 0 else { throw H4Error.malformed("\(r.remaining) trailing bytes after adventure object") }
    }
}

// MARK: - Combat objects

/// Battlefield obstacle or castle piece (`combat_object.*`, reader 0x606eb0, header 0x606aa0).
public struct H4CombatObject: Sendable {
    public let version: UInt16
    /// Footprint in battlefield cells.
    public let width: Int
    public let height: Int
    public let elevation: Int
    /// Animation speed; the game uses 1000 / framesPerSecond ms per frame.
    public let framesPerSecond: Int
    public let flag: Bool
    public let properties: [UInt8]
    public let typeID: UInt16?
    public let typeName: String?
    public let sprite: H4ObjectSprite

    public init(data: Data) throws {
        var r = ByteReader(data)
        version = try r.u16()
        guard version <= 2 else { throw H4Error.malformed("combat object version \(version)") }
        if version < 2 {
            width = Int(try r.u8()); height = width
        } else {
            width = Int(try r.u8()); height = Int(try r.u8())
        }
        elevation = Int(try r.u8())
        framesPerSecond = Int(try r.u8())
        guard framesPerSecond > 0 else { throw H4Error.malformed("combat object frame rate 0") }
        flag = try r.u8() != 0
        if version >= 1 {
            properties = try (0..<5).map { _ in try r.u8() }
            typeID = try r.u16()
            typeName = try r.string16()
        } else {
            properties = []; typeID = nil; typeName = nil
        }
        sprite = try H4ObjectSprite.read(&r, version: try r.u16())
        guard r.remaining == 0 else { throw H4Error.malformed("\(r.remaining) trailing bytes after combat object") }
    }
}
