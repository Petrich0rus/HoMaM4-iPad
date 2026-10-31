import Foundation

/// The transition masks of `transition.Transitions.h4d` (reader 0x8c4f20 / 0x8c4e70 in heroes4.exe).
///
///     u8 setCount (15)
///     per set: u16 nameLength, name (Latin-1, e.g. "water_to_land 1"), u32 count (93),
///              per mask: u32 key (edge/corner code, informational), u8 kind (1 or 4), bytes
///
/// A mask covers the 64×32 tile diamond, column by column (64 columns of heights 1,1,3,3 … 31,31,31,31 … 3,3,1,1,
/// vertically centred like the terrain tiles). Each column is byte-aligned:
/// kind 1 = 1 bit per pixel (ceil(h/8) bytes, least significant bit first, 160 bytes in all, alpha 0 or 15);
/// kind 4 = 4 bits per pixel (ceil(h/2) bytes, low nibble first, 544 bytes in all, alpha 0…15).
public struct H4TransitionLibrary: Sendable {
    public static let width = 64, height = 32
    /// Marks a pixel outside the diamond in `H4TransitionMask.storage`.
    static let outside: UInt8 = 255

    public struct Mask: Sendable, Equatable {
        /// Edge/corner code stored in the file (decimal digits 0…3); informational.
        public let key: UInt32
        /// 1 or 4: bits per pixel in the file.
        public let bitsPerPixel: Int
        /// 64×32 row-major; 0…15 inside the diamond, `H4TransitionLibrary.outside` (255) outside it.
        let storage: [UInt8]

        /// Alpha 0…15 of pixel (x, y), or nil outside the diamond.
        public func alpha(x: Int, y: Int) -> UInt8? {
            let a = storage[y * H4TransitionLibrary.width + x]
            return a == H4TransitionLibrary.outside ? nil : a
        }
    }

    public struct MaskSet: Sendable {
        public let name: String
        public let masks: [Mask]
    }

    public let sets: [MaskSet]

    /// Height of diamond column `k` (0…63); same shape as the terrain tiles.
    static func columnHeight(_ k: Int) -> Int { H4TerrainTexture.columnHeight(k) }

    public init(data: Data) throws {
        var r = ByteReader(data)
        let setCount = Int(try r.u8())
        var sets: [MaskSet] = []
        for _ in 0..<setCount {
            let nameLength = Int(try r.u16())
            let name = String(decoding: try r.bytes(nameLength), as: UTF8.self)
            let count = Int(try r.u32())
            guard count <= 4096 else { throw H4Error.malformed("transition set '\(name)' with \(count) masks") }
            var masks: [Mask] = []
            for _ in 0..<count {
                let key = try r.u32()
                let kind = Int(try r.u8())
                guard kind == 1 || kind == 4 else { throw H4Error.malformed("transition mask kind \(kind) in '\(name)'") }
                let bytes = try r.bytes(Self.encodedSize(bitsPerPixel: kind))
                masks.append(Mask(key: key, bitsPerPixel: kind, storage: Self.decode(bytes, bitsPerPixel: kind)))
            }
            sets.append(MaskSet(name: name, masks: masks))
        }
        guard r.remaining == 0 else { throw H4Error.malformed("\(r.remaining) trailing bytes after transition masks") }
        self.sets = sets
    }

    /// 160 for 1 bit per pixel, 544 for 4 bits per pixel.
    static func encodedSize(bitsPerPixel: Int) -> Int {
        (0..<64).reduce(0) { $0 + (bitsPerPixel == 4 ? (columnHeight($1) + 1) / 2 : (columnHeight($1) + 7) / 8) }
    }

    /// Decodes the column-major diamond into a 64×32 row-major grid.
    static func decode(_ data: Data, bitsPerPixel: Int) -> [UInt8] {
        var grid = [UInt8](repeating: outside, count: width * height)
        var o = data.startIndex
        for k in 0..<64 {
            let h = columnHeight(k), top = (31 - h) / 2
            if bitsPerPixel == 4 {
                for i in 0..<h {
                    let b = data[o + i / 2]
                    grid[(top + i) * width + k] = i & 1 == 0 ? b & 15 : b >> 4
                }
                o += (h + 1) / 2
            } else {
                for i in 0..<h {
                    grid[(top + i) * width + k] = (data[o + i / 8] >> UInt8(i % 8)) & 1 == 1 ? 15 : 0
                }
                o += (h + 7) / 8
            }
        }
        return grid
    }

    public func set(named name: String) -> MaskSet? { sets.first { $0.name == name } }

    public func mask(set name: String, index: Int) -> Mask? {
        guard let s = set(named: name), s.masks.indices.contains(index) else { return nil }
        return s.masks[index]
    }
}
