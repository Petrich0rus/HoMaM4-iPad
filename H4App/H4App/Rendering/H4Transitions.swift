import Foundation

/// Reader for `transition.Transitions.h4d` (heroes4.exe 0x8c4f20 / 0x8c4e70).
///
///     u8 setCount (15)
///     setCount × { u16-prefixed name, u32 maskCount (93),
///                  maskCount × { u32 key, u8 kind (1 = 1 bit/pixel, 4 = 4 bits/pixel), mask bytes } }
///
/// A mask covers one 64×32 diamond tile, stored column by column like the terrain tiles
/// (column heights 1, 1, 3, 3 … 31, 31, 31, 31 … 1, 1, vertically centred); each column starts on
/// a byte boundary. 1 bpp masks hold ceil(h/8) bytes per column (LSB first), 4 bpp masks ceil(h/2)
/// (low nibble first). Independent of UIKit/Metal and of app types so it can move into H4Kit.
struct H4TransitionMask: Sendable {
    static let width = 64, height = 32
    /// Decimal digits 0–3 describing the edge/corner shape; informational.
    let key: UInt32
    /// Opacity 0…15 per pixel, row-major 64×32; 0 outside the diamond.
    let alpha: [UInt8]
}

struct H4TransitionSet: Sendable {
    let name: String
    let masks: [H4TransitionMask]
}

enum H4Transitions {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func parse(_ data: Data) throws -> [H4TransitionSet] {
        let d = [UInt8](data)
        var o = 0
        func need(_ n: Int) throws { if o + n > d.count { throw Failure(description: "transitions: truncated at \(o)") } }
        func u32() throws -> UInt32 {
            try need(4); defer { o += 4 }
            return UInt32(d[o]) | UInt32(d[o + 1]) << 8 | UInt32(d[o + 2]) << 16 | UInt32(d[o + 3]) << 24
        }
        try need(1)
        let setCount = Int(d[o]); o += 1
        var sets: [H4TransitionSet] = []
        for _ in 0..<setCount {
            try need(2)
            let nameLength = Int(d[o]) | Int(d[o + 1]) << 8; o += 2
            try need(nameLength)
            let name = String(decoding: d[o..<(o + nameLength)], as: UTF8.self); o += nameLength
            let count = Int(try u32())
            guard count <= 1024 else { throw Failure(description: "transitions: \(count) masks in '\(name)'") }
            var masks: [H4TransitionMask] = []
            for _ in 0..<count {
                let key = try u32()
                try need(1)
                let kind = d[o]; o += 1
                guard kind == 1 || kind == 4 else { throw Failure(description: "transitions: mask kind \(kind)") }
                masks.append(H4TransitionMask(key: key, alpha: try decode(d, &o, fourBit: kind == 4)))
            }
            sets.append(H4TransitionSet(name: name, masks: masks))
        }
        return sets
    }

    private static func columnHeight(_ k: Int) -> Int { k < 32 ? 2 * (k / 2) + 1 : 2 * ((63 - k) / 2) + 1 }

    private static func decode(_ d: [UInt8], _ o: inout Int, fourBit: Bool) throws -> [UInt8] {
        let w = H4TransitionMask.width
        var out = [UInt8](repeating: 0, count: w * H4TransitionMask.height)
        for k in 0..<w {
            let h = columnHeight(k), top = (31 - h) / 2
            let bytes = fourBit ? (h + 1) / 2 : (h + 7) / 8
            guard o + bytes <= d.count else { throw Failure(description: "transitions: truncated mask") }
            for i in 0..<h {
                let value: UInt8
                if fourBit {
                    let b = d[o + i / 2]
                    value = i & 1 == 0 ? b & 15 : b >> 4
                } else {
                    value = (d[o + i / 8] >> UInt8(i % 8)) & 1 != 0 ? 15 : 0
                }
                out[(top + i) * w + k] = value
            }
            o += bytes
        }
        return out
    }
}
